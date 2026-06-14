//
//  SubtitleService.swift
//  Rclone GUI — Services
//
//  Découverte des sous-titres « sidecar » (fichiers .srt/.ass/… portant le
//  même nom de base que la vidéo, dans le même dossier du remote) et
//  préparation d'une URL locale à passer à `addPlaybackSlave` de VLCKit.
//

import Foundation

public struct SidecarSubtitle: Identifiable, Sendable, Hashable {
    public var id: String { pathInRemote }
    public let pathInRemote: String
    public let name: String
    /// Langue devinée depuis le nom (« film.en.srt » → "en"), best-effort.
    public let language: String?
}

public actor SubtitleService {
    public static let shared = SubtitleService()
    private init() {}

    /// Liste les sous-titres portant le même nom de base que `videoPath`,
    /// dans le dossier qui le contient.
    public func discover(remote: String, videoPath: String) async -> [SidecarSubtitle] {
        let dir = (videoPath as NSString).deletingLastPathComponent
        let videoBase = ((videoPath as NSString).lastPathComponent as NSString)
            .deletingPathExtension
            .lowercased()
        guard !videoBase.isEmpty,
              let entries = try? await RemoteService.shared.list(remote: remote, path: dir) else {
            return []
        }
        return entries.compactMap { entry -> SidecarSubtitle? in
            guard !entry.isDirectory, MediaFormat.isSubtitle(entry.name) else { return nil }
            let subBase = (entry.name as NSString).deletingPathExtension.lowercased()
            // Accepte « film.srt » et « film.en.srt » / « film.eng.forced.srt ».
            guard subBase == videoBase || subBase.hasPrefix(videoBase + ".") else { return nil }
            var lang: String?
            if subBase.hasPrefix(videoBase + ".") {
                lang = subBase
                    .dropFirst(videoBase.count + 1)
                    .split(separator: ".")
                    .first
                    .map(String.init)
            }
            return SidecarSubtitle(pathInRemote: entry.pathInRemote, name: entry.name, language: lang)
        }
    }

    /// Télécharge le sous-titre (petit fichier) et renvoie l'URL locale prête
    /// pour `addPlaybackSlave`.
    public func localURL(remote: String, subtitle: SidecarSubtitle) async throws -> URL {
        try await MediaCacheService.shared.localPlayableURL(
            remote: remote,
            path: subtitle.pathInRemote,
            sizeHint: nil,
            policy: .reuseIfCached
        )
    }
}
