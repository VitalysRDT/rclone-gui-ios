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
            return cacheURL
        }

        try fm.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        // Run rclone copyfile to land the file locally. Source = "<remote>:" with `path`,
        // destination = the cache parent dir (as local fs) with the cache filename.
        let jobID = try await TransferService.shared.copyFileAsync(
            srcFs: "\(remote):",
            srcPath: path,
            dstFs: cacheURL.deletingLastPathComponent().path,
            dstPath: cacheURL.lastPathComponent
        )

        try await waitForJob(jobID: jobID)
        return cacheURL
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
            try await Task.sleep(for: .milliseconds(500))
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
