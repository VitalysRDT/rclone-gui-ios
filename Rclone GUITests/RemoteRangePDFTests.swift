//
//  RemoteRangePDFTests.swift
//  Rclone GUITests
//
//  Rendu PDF par accès aléatoire (RemoteRangePDFProvider) sans réseau : on
//  génère un PDF multi-pages en mémoire, on l'expose via une RangeByteSource
//  mémoire (éventuellement instrumentée pour compter les lectures par plage),
//  et on vérifie le compte de pages + le rendu de la 1re page.
//

import Testing
import Foundation
import CoreGraphics
@testable import Rclone_GUI

private func makeTestPDF(pages: Int, width: CGFloat = 200, height: CGFloat = 300) -> Data? {
    let data = NSMutableData()
    guard let consumer = CGDataConsumer(data: data as CFMutableData) else { return nil }
    var mediaBox = CGRect(x: 0, y: 0, width: width, height: height)
    guard let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return nil }
    for i in 0..<pages {
        ctx.beginPDFPage(nil)
        ctx.setFillColor(CGColor(red: CGFloat(i) / CGFloat(max(pages, 1)),
                                 green: 0.4, blue: 0.6, alpha: 1))
        ctx.fill(mediaBox)
        ctx.endPDFPage()
    }
    ctx.closePDF()
    return data as Data
}

/// Compteur thread-safe de lectures (les reads viennent de Task.detached).
private final class ReadCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func bump() { lock.lock(); value += 1; lock.unlock() }
    var count: Int { lock.lock(); defer { lock.unlock() }; return value }
}

@Suite("RemoteRangePDFProvider — rendu par plages")
struct RemoteRangePDFTests {

    @Test("Compte les pages et rend la 1re page, downsamplée")
    func rendersFirstPage() async throws {
        let pdf = try #require(makeTestPDF(pages: 3))
        let source = RangeByteSource.inMemory(pdf)

        let result = try #require(
            await RemoteRangePDFProvider.render(source: source, totalSize: Int64(pdf.count))
        )
        #expect(result.pageCount == 3)
        let page = try #require(result.firstPage)
        #expect(page.image.width > 0)
        #expect(page.image.height > 0)
        #expect(page.image.width <= 400)
        #expect(page.image.height <= 400)
    }

    @Test("Lit bien via la RangeByteSource (accès par plages, pas un pull unique)")
    func readsThroughRangeSource() async throws {
        let pdf = try #require(makeTestPDF(pages: 2))
        let base = RangeByteSource.inMemory(pdf)
        let counter = ReadCounter()
        let instrumented = RangeByteSource(
            size: { await base.size() },
            read: { range in
                counter.bump()
                return await base.read(range)
            }
        )

        let result = await RemoteRangePDFProvider.render(
            source: instrumented, totalSize: Int64(pdf.count)
        )
        #expect(result?.pageCount == 2)
        // CoreGraphics a demandé au moins une plage via notre source.
        #expect(counter.count >= 1)
    }

    @Test("Octets non-PDF → pas de document (nil ou sans 1re page)")
    func garbageIsRejected() async {
        let junk = Data(repeating: 0x25, count: 800)   // « %%%… » : pas un vrai PDF
        let result = await RemoteRangePDFProvider.render(
            source: .inMemory(junk), totalSize: 800
        )
        #expect(result == nil || result?.firstPage == nil)
    }

    @Test("Taille nulle → nil")
    func zeroSize() async {
        let result = await RemoteRangePDFProvider.render(source: .inMemory(Data()), totalSize: 0)
        #expect(result == nil)
    }
}
