//
//  MediaCacheService.swift
//  Rclone GUI — Services
//
//  Media playback cache. Phase D v1 strategy: "download-then-play".
//  Hits operations/copyfile to land the source in a local cache file,
//  then plays it with AVPlayer. Crypt fully transparent because rclone
//  unwraps before writing the local copy.
//
//  Phase D2 (P1) will replace this with `AVAssetResourceLoaderDelegate`
//  + librclone range reads for true streaming (FR-030b in the PRD).
//

import Foundation
import AVFoundation

public actor MediaCacheService {
    public static let shared = MediaCacheService()
    private init() {}

    // Limite LRU configurable via Settings → Cache. Default 5GB :
    // confortable pour quelques films + photos sans saturer le device.
    // Stocké en UserDefaults pour survivre aux relaunchs.
    private static let defaultMaxSizeBytes: Int64 = 5 * 1024 * 1024 * 1024
    private static let maxSizeKey = "mediaCache.maxSizeBytes"
    private static let staleAfter: TimeInterval = 24 * 60 * 60

    public var maxSizeBytes: Int64 {
        let stored = UserDefaults.standard.object(forKey: Self.maxSizeKey) as? Int64
        return stored.flatMap { $0 > 0 ? $0 : nil } ?? Self.defaultMaxSizeBytes
    }

    public func setMaxSizeBytes(_ bytes: Int64) {
        UserDefaults.standard.set(bytes, forKey: Self.maxSizeKey)
    }

    /// Returns a local URL ready to feed to `AVPlayer`. Will download
    /// the file (cached on subsequent calls if `policy == .reuseIfCached`).
    public func localPlayableURL(
        remote: String,
        path: String,
        sizeHint: Int64? = nil,
        policy: CachePolicy = .reuseIfCached
    ) async throws -> URL {
        let cacheURL = Self.cacheURL(remote: remote, path: path)
        let fm = FileManager.default

        if policy == .reuseIfCached, fm.fileExists(atPath: cacheURL.path) {
            // Bumper la date d'accès pour préserver la fraîcheur LRU.
            try? fm.setAttributes([.modificationDate: Date()], ofItemAtPath: cacheURL.path)
            return cacheURL
        }

        try fm.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        // Anticipation : si on sait que ce nouveau fichier dépasserait la
        // limite, on évince d'abord.
        if let sizeHint, sizeHint > 0 {
            try? evictIfNeeded(reservingBytes: sizeHint)
        }

        // Le téléchargement bypasse le throttle d'activité utilisateur : sinon
        // l'UserActivityMonitor le bride à 512 Ko/s dès qu'on touche l'écran (un
        // gros fichier mettrait des heures) ET le va-et-vient core/bwlimit ajoute
        // des RPC lentes qui font ramer l'app. Le streaming partage le process
        // rclone, donc on évite toute contention superflue pendant le download.
        await TransferQueue.shared.incrementActivityBypass()
        defer { Task { await TransferQueue.shared.decrementActivityBypass() } }

        // Run rclone copyfile to land the file locally. Source = "<remote>:" with `path`,
        // destination = the cache parent dir (as local fs) with the cache filename.
        let jobID = try await TransferService.shared.copyFileAsync(
            srcFs: "\(remote):",
            srcPath: path,
            dstFs: cacheURL.deletingLastPathComponent().path,
            dstPath: cacheURL.lastPathComponent
        )

        try await waitForJob(jobID: jobID)
        // Post-download : éviction au cas où le fichier réel est plus gros
        // que sizeHint (ou qu'il n'y avait pas de hint).
        try? evictIfNeeded(reservingBytes: 0)
        return cacheURL
    }

    /// Supprime les fichiers les moins récemment accédés jusqu'à passer
    /// sous `maxSizeBytes - reservingBytes`. Appelé avant + après chaque
    /// download pour borner le cache (Phase E2).
    public func evictIfNeeded(reservingBytes: Int64 = 0) throws {
        let fm = FileManager.default
        let root = Self.cacheRoot
        guard fm.fileExists(atPath: root.path) else { return }
        let target = max(0, maxSizeBytes - reservingBytes)

        struct Entry { let url: URL; let size: Int64; let mtime: Date }
        var entries: [Entry] = []
        var total: Int64 = 0
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: keys) else { return }
        for case let url as URL in enumerator {
            let res = try? url.resourceValues(forKeys: Set(keys))
            guard res?.isRegularFile == true else { continue }
            let size = Int64(res?.fileSize ?? 0)
            let mtime = res?.contentModificationDate ?? .distantPast
            entries.append(Entry(url: url, size: size, mtime: mtime))
            total += size
        }
        guard total > target else { return }

        // Évince du plus ancien au plus récent jusqu'à passer sous la cible.
        entries.sort { $0.mtime < $1.mtime }
        for entry in entries {
            if total <= target { break }
            try? fm.removeItem(at: entry.url)
            total -= entry.size
        }
    }

    /// Supprime les fichiers temporaires `.partial-*` plus vieux que 24h.
    /// Ces partials sont laissés par les downloads interrompus côté
    /// AppGroupBridge — sans cleanup, ils s'accumulent.
    @discardableResult
    public func cleanupStalePartials() throws -> Int {
        let fm = FileManager.default
        let root = Self.cacheRoot
        guard fm.fileExists(atPath: root.path) else { return 0 }
        let now = Date()
        var removed = 0
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: keys) else { return 0 }
        for case let url as URL in enumerator {
            let name = url.lastPathComponent
            guard name.hasPrefix(".partial-") || name.hasSuffix(".partial") else { continue }
            let res = try? url.resourceValues(forKeys: Set(keys))
            guard res?.isRegularFile == true else { continue }
            let mtime = res?.contentModificationDate ?? now
            if now.timeIntervalSince(mtime) > Self.staleAfter {
                try? fm.removeItem(at: url)
                removed += 1
            }
        }
        return removed
    }

    public func purge() throws {
        let fm = FileManager.default
        let root = Self.cacheRoot
        if fm.fileExists(atPath: root.path) {
            try fm.removeItem(at: root)
        }
    }

    public func currentSize() throws -> Int64 {
        let fm = FileManager.default
        let root = Self.cacheRoot
        guard fm.fileExists(atPath: root.path) else { return 0 }
        var total: Int64 = 0
        if let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey]) {
            for case let url as URL in enumerator {
                let res = try url.resourceValues(forKeys: [.fileSizeKey])
                total += Int64(res.fileSize ?? 0)
            }
        }
        return total
    }

    public enum CachePolicy: Sendable {
        case reuseIfCached
        case alwaysFresh
    }

    // MARK: - Internals

    private func waitForJob(jobID: Int) async throws {
        while !Task.isCancelled {
            // 2 s (et non 500 ms) : pendant un gros download rclone est saturé,
            // chaque job/status met 1–4 s et un poll trop fréquent monopolise le
            // bridge RPC → l'app rame. 2 s suffit largement pour un transfert long.
            try await Task.sleep(for: .seconds(2))
            let info = try await TransferService.shared.jobStatus(jobID: jobID)
            if info.finished {
                if info.success { return }
                throw RcloneError.rcloneError(
                    code: -1,
                    method: "operations/copyfile",
                    message: info.error ?? "Échec téléchargement pour lecture"
                )
            }
        }
        throw CancellationError()
    }

    static var cacheRoot: URL {
        let caches = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return caches.appending(path: "MediaCache", directoryHint: .isDirectory)
    }

    static func cacheURL(remote: String, path: String) -> URL {
        // Encode the remote name + path into a flat filename to avoid
        // surprises when the path contains "/" or special characters.
        let safe = (remote + ":" + path).addingPercentEncoding(
            withAllowedCharacters: .alphanumerics
        ) ?? UUID().uuidString
        let ext = (path as NSString).pathExtension
        var url = cacheRoot.appending(path: safe)
        if !ext.isEmpty {
            url = url.appendingPathExtension(ext)
        }
        return url
    }
}
