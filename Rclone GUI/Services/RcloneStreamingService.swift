//
//  RcloneStreamingService.swift
//  Rclone GUI — Services
//
//  Front door for media playback. Prefers the Go loopback HTTP range bridge
//  so AVPlayer can seek without pre-downloading the whole object. Falls back
//  to MediaCacheService if the bridge cannot start.
//

import Foundation
#if canImport(RcloneKit)
import RcloneKit
#endif

public struct StreamingSession: Sendable, Identifiable {
    public let id: String
    public let url: URL
    public let isLiveStream: Bool
}

public actor RcloneStreamingService {
    public static let shared = RcloneStreamingService()
    private init() {}

    public func session(remote: String, path: String, sizeHint: Int64?) async throws -> StreamingSession {
        if let live = await liveSession(remote: remote, path: path) {
            return live
        }
        let localURL = try await MediaCacheService.shared.localPlayableURL(
            remote: remote,
            path: path,
            sizeHint: sizeHint,
            policy: .reuseIfCached
        )
        return StreamingSession(id: UUID().uuidString, url: localURL, isLiveStream: false)
    }

    /// Session de streaming « live » via le bridge loopback **uniquement**
    /// (pas de fallback téléchargement). Renvoie nil si le bridge est
    /// indisponible. Utilisé par les vignettes pour ne jamais déclencher le
    /// download complet d'un fichier juste pour une miniature.
    public func liveSession(remote: String, path: String) async -> StreamingSession? {
        #if canImport(RcloneKit)
        do {
            _ = try await RcloneCore.shared.version()
            let raw = RclonebridgeStartFileHTTP(remote, path)
            let data = Data(raw.utf8)
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard let id = object?["id"] as? String,
                  let urlString = object?["url"] as? String,
                  let url = URL(string: urlString),
                  !id.isEmpty else {
                return nil
            }
            // Glass Engine : le pont rclone écoute en loopback (127.0.0.1). On
            // enregistre l'egress (catégorie .loopback — reste sur l'appareil)
            // sans envelopper le transport de download.
            GlassEngineMonitor.record(
                host: url.host,
                purpose: String(localized: "Pont rclone local (streaming/téléchargement)")
            )
            return StreamingSession(id: id, url: url, isLiveStream: true)
        } catch {
            await LogService.shared.log(
                .info,
                category: "streaming",
                message: "Bridge streaming indisponible pour \(remote):\(path) : \(error.localizedDescription)"
            )
            return nil
        }
        #else
        return nil
        #endif
    }

    public func stop(_ session: StreamingSession) async {
        guard session.isLiveStream else { return }
        #if canImport(RcloneKit)
        RclonebridgeStopFileHTTP(session.id)
        #endif
    }
}
