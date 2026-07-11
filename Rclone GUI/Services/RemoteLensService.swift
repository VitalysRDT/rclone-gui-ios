//
//  RemoteLensService.swift
//  Rclone GUI — Services
//
//  « Remote Lens » : produit un aperçu (vignette + métadonnées) d'un fichier
//  distant en lisant SEULEMENT les octets nécessaires via range requests
//  (RemoteRangeReader), sans télécharger tout le fichier.
//
//  Image (PR2) : un unique fetch partiel incrémental fournit à la fois le
//  dictionnaire EXIF (ImageIO) et la vignette 400 px. On tente d'abord une
//  fenêtre de tête (EXIF + vignette embarquée sont presque toujours au début
//  d'un JPEG/HEIC/RAW) ; si la vignette n'est pas dans le préfixe, on escalade
//  vers un GET complet borné.
//  PDF (PR3) : câblé plus tard via RemoteRangePDFProvider.
//
//  Cache : métadonnées en mémoire (LRU, même clé SHA-256 que ThumbnailService),
//  vignette partagée avec la galerie via le cache disque de ThumbnailService.
//

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// MARK: - DTO

public struct RemoteImageMetadata: Sendable, Hashable {
    public let pixelWidth: Int?
    public let pixelHeight: Int?
    public let cameraMake: String?
    public let cameraModel: String?
    public let lensModel: String?
    public let captureDate: Date?
    public let exposure: String?
    public let fNumber: String?
    public let iso: String?
    public let focalLength: String?
    public let latitude: Double?
    public let longitude: Double?

    /// Vrai si aucun champ exploitable — l'UI peut alors masquer la section.
    public var isEmpty: Bool {
        pixelWidth == nil && pixelHeight == nil && cameraMake == nil && cameraModel == nil
            && lensModel == nil && captureDate == nil && exposure == nil && fNumber == nil
            && iso == nil && focalLength == nil && latitude == nil && longitude == nil
    }
}

public struct RemotePDFMetadata: Sendable, Hashable {
    public let pageCount: Int?
    public let title: String?
    public let author: String?
    public let firstPageAvailable: Bool
}

public enum RemoteLensKind: Sendable, Equatable {
    case image
    case pdf
    case unsupported
}

public struct RemoteLensPreview: Sendable {
    public let kind: RemoteLensKind
    public let thumbnail: CGImageBox?
    public let image: RemoteImageMetadata?
    public let pdf: RemotePDFMetadata?
    /// Message d'état facultatif (« trop volumineux », « aperçu indisponible »).
    public let note: String?

    public init(kind: RemoteLensKind, thumbnail: CGImageBox? = nil,
                image: RemoteImageMetadata? = nil, pdf: RemotePDFMetadata? = nil,
                note: String? = nil) {
        self.kind = kind
        self.thumbnail = thumbnail
        self.image = image
        self.pdf = pdf
        self.note = note
    }
}

// MARK: - Service

public actor RemoteLensService {
    public static let shared = RemoteLensService()
    private init() {}

    // Même bornage de concurrence réseau que ThumbnailService.
    private let limiter = AsyncSemaphore(value: 3)

    // Cache mémoire LRU des aperçus (métadonnées légères + boîte vignette).
    private var cache: [String: RemoteLensPreview] = [:]
    private var order: [String] = []
    private let cacheLimit = 200

    /// Aperçu d'une entrée. nil ⇒ non applicable (ni image ni PDF) ou bridge KO.
    public func preview(for entry: RemoteEntryDTO, remote: String) async -> RemoteLensPreview? {
        guard MediaFormat.hasLens(entry.name) else { return nil }
        let key = ThumbnailService.cacheKey(remote: remote, entry: entry)
        if let hit = cache[key] { return hit }

        // Politique données : identique aux vignettes (never / Wi-Fi seulement).
        switch ThumbnailService.policy {
        case .never:
            return nil
        case .wifiOnly:
            if await NetworkReachability.shared.isExpensive { return nil }
        case .always:
            break
        }

        await limiter.wait()
        defer { Task { await limiter.signal() } }
        if Task.isCancelled { return nil }
        if let hit = cache[key] { return hit }

        let result: RemoteLensPreview?
        if MediaFormat.isPDF(entry.name) {
            // Chemin PDF branché en PR3 (RemoteRangePDFProvider).
            result = RemoteLensPreview(kind: .pdf, pdf: RemotePDFMetadata(
                pageCount: nil, title: nil, author: nil, firstPageAvailable: false
            ))
        } else {
            result = await Self.buildImagePreview(remote: remote, entry: entry)
        }

        if let result, result.thumbnail != nil || result.image != nil {
            store(result, key: key)
        }
        return result
    }

    public func clearCache() {
        cache.removeAll()
        order.removeAll()
    }

    private func store(_ preview: RemoteLensPreview, key: String) {
        if cache[key] == nil { order.append(key) }
        cache[key] = preview
        if order.count > cacheLimit {
            let evicted = order.removeFirst()
            cache.removeValue(forKey: evicted)
        }
    }

    // MARK: - Image (hors acteur)

    nonisolated static func buildImagePreview(remote: String, entry: RemoteEntryDTO) async -> RemoteLensPreview? {
        let strategy = RemoteLensPlan.imageStrategy(size: entry.size)
        if strategy == .skip {
            return RemoteLensPreview(kind: .image,
                                     note: String(localized: "Image trop volumineuse pour l'aperçu."))
        }

        let built: RemoteLensPreview? = await RemoteRangeReader.withSession(
            remote: remote, path: entry.pathInRemote
        ) { source in
            let total = await source.size() ?? entry.size

            // 1. Fenêtre de tête (EXIF + vignette embarquée sont presque toujours
            //    en début de fichier). Si elle donne une vignette, on s'arrête là.
            if case .headRange(let window) = strategy,
               let range = RemoteLensPlan.clampedRange(start: 0, window: window, totalSize: total),
               let head = await source.read(range),
               let decoded = decodeImage(head), decoded.thumbnail != nil {
                persistThumbnail(decoded.thumbnail, remote: remote, entry: entry)
                return RemoteLensPreview(kind: .image, thumbnail: decoded.thumbnail,
                                         image: decoded.meta)
            }

            // 2. GET complet borné (fullBounded, ou fenêtre de tête sans vignette).
            let cap = min(total > 0 ? total : RemoteLensPlan.imageFullCap,
                          RemoteLensPlan.imageFullCap)
            guard cap > 0,
                  let full = await source.read(0...(cap - 1)),
                  let decoded = decodeImage(full) else {
                return RemoteLensPreview(kind: .image,
                                         note: String(localized: "Aperçu indisponible."))
            }
            persistThumbnail(decoded.thumbnail, remote: remote, entry: entry)
            return RemoteLensPreview(kind: .image, thumbnail: decoded.thumbnail, image: decoded.meta)
        }

        // withSession renvoie nil si le bridge est indisponible.
        return built ?? RemoteLensPreview(kind: .image,
                                          note: String(localized: "Aperçu indisponible (pont hors ligne)."))
    }

    /// Décode vignette + métadonnées à partir d'octets (possiblement partiels).
    /// nil seulement si ImageIO ne reconnaît rien du tout.
    nonisolated static func decodeImage(_ data: Data) -> (thumbnail: CGImageBox?, meta: RemoteImageMetadata?)? {
        autoreleasepool {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
            let meta = extractMetadata(from: source)
            let thumb = makeThumbnail(from: source)
            if meta == nil && thumb == nil { return nil }
            return (thumb, meta)
        }
    }

    nonisolated static func makeThumbnail(from source: CGImageSource) -> CGImageBox? {
        // Si l'image n'est pas complète (données partielles), on ne décode PAS
        // l'image pleine (risque de bitmap tronqué) : on privilégie la vignette
        // EXIF embarquée via IfAbsent.
        let complete = CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: complete,
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceThumbnailMaxPixelSize: ThumbnailService.maxPixel,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return CGImageBox(image: cg)
    }

    // MARK: - Extraction EXIF (pure ImageIO, testable)

    nonisolated static let exifDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy:MM:dd HH:mm:ss"
        f.timeZone = TimeZone.current
        return f
    }()

    nonisolated static func extractMetadata(from source: CGImageSource) -> RemoteImageMetadata? {
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return nil
        }
        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        let gps = props[kCGImagePropertyGPSDictionary] as? [CFString: Any]

        func dbl(_ any: Any?) -> Double? { (any as? NSNumber)?.doubleValue }
        func integer(_ any: Any?) -> Int? { (any as? NSNumber)?.intValue }

        let width = integer(props[kCGImagePropertyPixelWidth])
        let height = integer(props[kCGImagePropertyPixelHeight])
        let make = tiff?[kCGImagePropertyTIFFMake] as? String
        let model = tiff?[kCGImagePropertyTIFFModel] as? String
        let lens = exif?[kCGImagePropertyExifLensModel] as? String

        let date = (exif?[kCGImagePropertyExifDateTimeOriginal] as? String)
            .flatMap { exifDateFormatter.date(from: $0) }

        let exposure = dbl(exif?[kCGImagePropertyExifExposureTime])
            .map(RemoteLensPlan.formatExposureTime)
        let fnumber = dbl(exif?[kCGImagePropertyExifFNumber])
            .map(RemoteLensPlan.formatFNumber)
        let focal = dbl(exif?[kCGImagePropertyExifFocalLength])
            .map(RemoteLensPlan.formatFocalLength)
        let iso = (exif?[kCGImagePropertyExifISOSpeedRatings] as? [Any])?
            .first.flatMap { integer($0) }
            .map(RemoteLensPlan.formatISO)

        var lat: Double?
        var lon: Double?
        if let la = dbl(gps?[kCGImagePropertyGPSLatitude]),
           let lo = dbl(gps?[kCGImagePropertyGPSLongitude]) {
            lat = RemoteLensPlan.gpsDecimal(la, ref: gps?[kCGImagePropertyGPSLatitudeRef] as? String)
            lon = RemoteLensPlan.gpsDecimal(lo, ref: gps?[kCGImagePropertyGPSLongitudeRef] as? String)
        }

        let meta = RemoteImageMetadata(
            pixelWidth: width, pixelHeight: height,
            cameraMake: make, cameraModel: model, lensModel: lens,
            captureDate: date, exposure: exposure, fNumber: fnumber,
            iso: iso, focalLength: focal, latitude: lat, longitude: lon
        )
        return meta.isEmpty ? nil : meta
    }

    // MARK: - Cache disque partagé avec la galerie

    nonisolated static func persistThumbnail(_ box: CGImageBox?, remote: String, entry: RemoteEntryDTO) {
        guard let box else { return }
        let key = ThumbnailService.cacheKey(remote: remote, entry: entry)
        ThumbnailService.writeToDisk(box.image, key: key)
    }
}
