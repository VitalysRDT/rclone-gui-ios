//
//  ThumbnailService.swift
//  Rclone GUI — Services
//
//  Génère et met en cache les vignettes des médias distants pour la galerie.
//
//  Stratégie (économe) :
//    - Images : bridge loopback live → URLSession → downsampling ImageIO
//      (CGImageSourceCreateThumbnailAtIndex). Plafond de taille pour éviter de
//      télécharger un fichier énorme juste pour une miniature.
//    - Vidéos : bridge loopback live → AVAssetImageGenerator (1re seconde),
//      qui ne lit que les plages nécessaires (pas de téléchargement complet).
//    - Cache : mémoire (LRU) + disque (JPEG dans thumbnailCacheURL), clé =
//      SHA-256 de remote:chemin|modTime|taille.
//    - Concurrence bornée (sémaphore) + politique données (Wi-Fi seulement /
//      toujours / jamais). On NE déclenche jamais le download complet d'un
//      fichier (liveSession uniquement) pour une vignette.
//

import Foundation
import CoreGraphics
import ImageIO
import AVFoundation
import CryptoKit
import UniformTypeIdentifiers

public enum ThumbnailPolicy: String, CaseIterable, Sendable {
    case always
    case wifiOnly
    case never

    public static let defaultsKey = "thumbnails.policy"

    public var label: String {
        switch self {
        case .always:   return String(localized: "Toujours")
        case .wifiOnly: return String(localized: "Wi-Fi seulement")
        case .never:    return String(localized: "Jamais")
        }
    }
}

/// Boîte Sendable autour d'un CGImage (immuable) pour le passer entre acteurs
/// sans avertissement de concurrence.
public struct CGImageBox: @unchecked Sendable {
    public let image: CGImage
}

/// Sémaphore asynchrone pour borner le nombre de générations simultanées.
actor AsyncSemaphore {
    private var value: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(value: Int) { self.value = value }

    func wait() async {
        if value > 0 { value -= 1; return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func signal() {
        if waiters.isEmpty {
            value += 1
        } else {
            waiters.removeFirst().resume()
        }
    }
}

public actor ThumbnailService {
    public static let shared = ThumbnailService()
    private init() {}

    // Taille max d'un côté de la vignette (px). Uniforme pour un cache stable.
    static let maxPixel: Int = 400
    // Au-delà, on ne télécharge pas l'image pour une vignette (icône à la place).
    static let imageSizeCap: Int64 = 80 * 1024 * 1024
    // Générations réseau simultanées.
    private let limiter = AsyncSemaphore(value: 3)

    // Cache mémoire LRU (par nombre).
    private var memCache: [String: CGImageBox] = [:]
    private var memOrder: [String] = []
    private let memLimit = 300

    /// Vignette pour une entrée média. nil ⇒ afficher l'icône de repli.
    public func thumbnail(for entry: RemoteEntryDTO, remote: String) async -> CGImageBox? {
        guard MediaFormat.isVisualMedia(entry.name) else { return nil }
        let key = Self.cacheKey(remote: remote, entry: entry)

        if let cached = memCache[key] { return cached }
        if let disk = Self.loadFromDisk(key: key) {
            store(disk, key: key)
            return disk
        }

        // Politique données : on ne GÉNÈRE pas si interdit (le cache reste servi).
        switch Self.policy {
        case .never:
            return nil
        case .wifiOnly where NetworkReachability.shared.isExpensive:
            return nil
        default:
            break
        }

        await limiter.wait()
        defer { Task { await limiter.signal() } }

        // Re-vérifie après l'attente (réentrance : une autre tâche a pu générer).
        if let cached = memCache[key] { return cached }

        guard let box = await Self.generate(entry: entry, remote: remote) else { return nil }
        Self.writeToDisk(box.image, key: key)
        store(box, key: key)
        return box
    }

    private func store(_ box: CGImageBox, key: String) {
        if memCache[key] == nil { memOrder.append(key) }
        memCache[key] = box
        if memOrder.count > memLimit {
            let evicted = memOrder.removeFirst()
            memCache.removeValue(forKey: evicted)
        }
    }

    public func clearCache() {
        memCache.removeAll()
        memOrder.removeAll()
        let fm = FileManager.default
        try? fm.removeItem(at: AppGroup.thumbnailCacheURL)
        try? fm.createDirectory(at: AppGroup.thumbnailCacheURL, withIntermediateDirectories: true)
    }

    // MARK: - Génération (hors acteur → s'exécute en parallèle)

    nonisolated static var policy: ThumbnailPolicy {
        ThumbnailPolicy(rawValue: UserDefaults.standard.string(forKey: ThumbnailPolicy.defaultsKey) ?? "") ?? .wifiOnly
    }

    nonisolated static func generate(entry: RemoteEntryDTO, remote: String) async -> CGImageBox? {
        if MediaFormat.isImage(entry.name) {
            return await generateImageThumbnail(remote: remote, entry: entry)
        }
        if MediaFormat.isVideo(entry.name) {
            return await generateVideoThumbnail(remote: remote, entry: entry)
        }
        return nil
    }

    nonisolated static func generateImageThumbnail(remote: String, entry: RemoteEntryDTO) async -> CGImageBox? {
        if entry.size > 0, entry.size > imageSizeCap { return nil }
        guard let session = await RcloneStreamingService.shared.liveSession(
            remote: remote, path: entry.pathInRemote
        ) else { return nil }
        defer { Task { await RcloneStreamingService.shared.stop(session) } }

        guard let (data, _) = try? await URLSession.shared.data(from: session.url),
              let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return CGImageBox(image: cg)
    }

    nonisolated static func generateVideoThumbnail(remote: String, entry: RemoteEntryDTO) async -> CGImageBox? {
        guard let session = await RcloneStreamingService.shared.liveSession(
            remote: remote, path: entry.pathInRemote
        ) else { return nil }
        defer { Task { await RcloneStreamingService.shared.stop(session) } }

        let asset = AVURLAsset(url: session.url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxPixel, height: maxPixel)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 2, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 3, preferredTimescale: 600)

        let time = CMTime(seconds: 1, preferredTimescale: 600)
        guard let result = try? await generator.image(at: time) else { return nil }
        return CGImageBox(image: result.image)
    }

    // MARK: - Cache disque

    nonisolated static func cacheKey(remote: String, entry: RemoteEntryDTO) -> String {
        let raw = "\(remote):\(entry.pathInRemote)|\(Int(entry.modTime.timeIntervalSince1970))|\(entry.size)|\(maxPixel)"
        let digest = SHA256.hash(data: Data(raw.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    nonisolated static func cacheFileURL(key: String) -> URL {
        AppGroup.thumbnailCacheURL.appending(path: key).appendingPathExtension("jpg")
    }

    nonisolated static func loadFromDisk(key: String) -> CGImageBox? {
        let url = cacheFileURL(key: key)
        guard FileManager.default.fileExists(atPath: url.path),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }
        return CGImageBox(image: cg)
    }

    nonisolated static func writeToDisk(_ image: CGImage, key: String) {
        let url = cacheFileURL(key: key)
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        guard let dest = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.jpeg.identifier as CFString, 1, nil
        ) else { return }
        let props: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.8]
        CGImageDestinationAddImage(dest, image, props as CFDictionary)
        CGImageDestinationFinalize(dest)
    }

    nonisolated public static func cacheSizeBytes() -> Int64 {
        let root = AppGroup.thumbnailCacheURL
        let fm = FileManager.default
        guard fm.fileExists(atPath: root.path),
              let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            total += Int64(size)
        }
        return total
    }
}
