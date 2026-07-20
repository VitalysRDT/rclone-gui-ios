//
//  RemoteRangePDFProvider.swift
//  Rclone GUI — Services
//
//  Rendu de la 1re page d'un PDF distant SANS le télécharger en entier.
//  CoreGraphics lit un PDF via un `CGDataProvider` à accès aléatoire : son
//  callback `getBytesAtPosition` demande des plages arbitraires (la table xref
//  est en fin de fichier, puis les objets de la 1re page). On adosse ce
//  callback à une `RangeByteSource` (bridge loopback range) → CG ne lit que le
//  xref + la 1re page, quelle que soit la taille du PDF.
//
//  Contrainte : le callback CG est SYNCHRONE alors que les lectures range sont
//  async. On exécute donc tout le rendu sur un thread OS dédié (jamais le main
//  ni le pool coopératif) et on attend chaque plage via un DispatchSemaphore
//  (URLSession complète sur ses propres threads → pas de deadlock). Un plafond
//  d'octets distincts protège contre un PDF pathologique qui forcerait la
//  lecture de tout le fichier.
//

import Foundation
import CoreGraphics

public struct PDFRenderResult: Sendable {
    public let pageCount: Int
    public let firstPage: CGImageBox?
}

/// Lecteur adossé à une `RangeByteSource`, exposé à CoreGraphics via un
/// `CGDataProvider` direct. Manipulé séquentiellement sur le thread de rendu
/// dédié → `@unchecked Sendable` assumé.
nonisolated final class RangeBackedPDFReader: @unchecked Sendable {
    let source: RangeByteSource
    let totalSize: Int64
    let blockSize: Int64
    let maxBytes: Int64
    private var blocks: [Int64: Data] = [:]
    private var distinctBytesRead: Int64 = 0

    init(source: RangeByteSource, totalSize: Int64, maxBytes: Int64, blockSize: Int64 = 64 * 1024) {
        self.source = source
        self.totalSize = totalSize
        self.maxBytes = maxBytes
        self.blockSize = blockSize
    }

    /// Sert `count` octets à partir de `position` depuis les blocs (lus à la
    /// demande, alignés, cachés). Renvoie le nombre d'octets réellement copiés.
    func getBytes(at position: off_t, count: Int, into buffer: UnsafeMutableRawPointer) -> Int {
        let pos = Int64(position)
        guard pos >= 0, pos < totalSize, count > 0 else { return 0 }
        let end = min(pos + Int64(count), totalSize)
        var written = 0
        var cursor = pos
        while cursor < end {
            let blockIndex = cursor / blockSize
            guard let block = ensureBlock(blockIndex) else { break }
            let blockStart = blockIndex * blockSize
            let offsetInBlock = Int(cursor - blockStart)
            if offsetInBlock >= block.count { break }
            let avail = block.count - offsetInBlock
            let need = Int(min(end - cursor, Int64(avail)))
            if need <= 0 { break }
            block.withUnsafeBytes { raw in
                if let base = raw.baseAddress {
                    memcpy(buffer.advanced(by: written), base.advanced(by: offsetInBlock), need)
                }
            }
            written += need
            cursor += Int64(need)
        }
        return written
    }

    private func ensureBlock(_ index: Int64) -> Data? {
        if let cached = blocks[index] { return cached }
        let start = index * blockSize
        guard start >= 0, start < totalSize else { return nil }
        if distinctBytesRead >= maxBytes { return nil }   // plafond anti lecture-totale
        let endInclusive = min(start + blockSize - 1, totalSize - 1)
        guard let data = readSync(start...endInclusive) else { return nil }
        blocks[index] = data
        distinctBytesRead += Int64(data.count)
        return data
    }

    /// Pont synchrone → async : lit une plage en bloquant le thread dédié.
    private func readSync(_ range: ClosedRange<Int64>) -> Data? {
        let semaphore = DispatchSemaphore(value: 0)
        let box = ByteResultBox()
        let src = source
        Task.detached {
            box.data = await src.read(range)
            semaphore.signal()
        }
        semaphore.wait()
        return box.data
    }
}

/// Transporte le résultat d'une lecture async vers le thread synchrone.
private nonisolated final class ByteResultBox: @unchecked Sendable {
    var data: Data?
}

public nonisolated enum RemoteRangePDFProvider {

    /// Plafond d'octets DISTINCTS lus avant abandon (PDF pathologique).
    public static let maxDistinctBytes: Int64 = 16 * 1024 * 1024

    /// Rend la 1re page + compte les pages en lisant par plages. nil si le PDF
    /// est illisible ou la taille inconnue.
    public static func render(source: RangeByteSource, totalSize: Int64, maxPixel: Int = 400) async -> PDFRenderResult? {
        guard totalSize > 0 else { return nil }
        return await withCheckedContinuation { (continuation: CheckedContinuation<PDFRenderResult?, Never>) in
            let thread = Thread {
                let result = renderSync(source: source, totalSize: totalSize, maxPixel: maxPixel)
                continuation.resume(returning: result)
            }
            thread.name = "RemoteLens.PDF"
            thread.stackSize = 4 << 20
            thread.start()
        }
    }

    private static func renderSync(source: RangeByteSource, totalSize: Int64, maxPixel: Int) -> PDFRenderResult? {
        autoreleasepool {
            let reader = RangeBackedPDFReader(source: source, totalSize: totalSize, maxBytes: maxDistinctBytes)
            let info = Unmanaged.passRetained(reader).toOpaque()
            var callbacks = CGDataProviderDirectCallbacks(
                version: 0,
                getBytePointer: nil,
                releaseBytePointer: nil,
                getBytesAtPosition: { info, buffer, position, count in
                    guard let info else { return 0 }
                    let reader = Unmanaged<RangeBackedPDFReader>.fromOpaque(info).takeUnretainedValue()
                    return reader.getBytes(at: position, count: count, into: buffer)
                },
                releaseInfo: { info in
                    guard let info else { return }
                    Unmanaged<RangeBackedPDFReader>.fromOpaque(info).release()
                }
            )
            guard let provider = CGDataProvider(directInfo: info, size: off_t(totalSize), callbacks: &callbacks) else {
                // Provider non créé → releaseInfo ne sera pas appelé : on libère ici.
                Unmanaged<RangeBackedPDFReader>.fromOpaque(info).release()
                return nil
            }
            guard let document = CGPDFDocument(provider) else { return nil }
            let count = document.numberOfPages
            guard count > 0 else { return PDFRenderResult(pageCount: 0, firstPage: nil) }
            let firstImage = document.page(at: 1).flatMap { renderFirstPage($0, maxPixel: maxPixel) }
            return PDFRenderResult(pageCount: count, firstPage: firstImage.map { CGImageBox(image: $0) })
        }
    }

    private static func renderFirstPage(_ page: CGPDFPage, maxPixel: Int) -> CGImage? {
        let cropBox = page.getBoxRect(.cropBox)
        let usesCrop = !cropBox.isEmpty
        let rect = usesCrop ? cropBox : page.getBoxRect(.mediaBox)
        guard rect.width > 0, rect.height > 0 else { return nil }

        let scale = min(CGFloat(maxPixel) / rect.width, CGFloat(maxPixel) / rect.height)
        let width = max(1, Int((rect.width * scale).rounded()))
        let height = max(1, Int((rect.height * scale).rounded()))

        let space = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: 0, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // Fond blanc (les PDF ont un fond transparent par défaut).
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

        // getDrawingTransform mappe la box source vers notre rect cible (échelle
        // + rotation intégrées, ratio préservé).
        let transform = page.getDrawingTransform(
            usesCrop ? .cropBox : .mediaBox,
            rect: CGRect(x: 0, y: 0, width: width, height: height),
            rotate: 0, preserveAspectRatio: true
        )
        ctx.concatenate(transform)
        ctx.drawPDFPage(page)
        return ctx.makeImage()
    }
}
