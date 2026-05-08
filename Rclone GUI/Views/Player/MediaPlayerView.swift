//
//  MediaPlayerView.swift
//  Rclone GUI — Views/Player
//
//  AVPlayerViewController wrapper for SwiftUI. Hands a local URL —
//  obtained via MediaCacheService — to AVPlayer.
//
//  Phase D v1: download-then-play. Phase D2 will swap the source for a
//  custom AVAssetResourceLoaderDelegate that streams via librclone
//  range reads (loopback fallback per FR-030b).
//

import SwiftUI
import AVKit
import AVFoundation

#if canImport(UIKit)
import UIKit

struct MediaPlayerView: UIViewControllerRepresentable {
    let url: URL
    let title: String?

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let player = AVPlayer(url: url)
        let controller = AVPlayerViewController()
        controller.player = player
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        controller.entersFullScreenWhenPlaybackBegins = true
        controller.exitsFullScreenWhenPlaybackEnds = false
        controller.modalPresentationStyle = .fullScreen
        if let title {
            // iOS 16+ : show title via Now Playing metadata
            let item = AVMutableMetadataItem()
            item.identifier = .commonIdentifierTitle
            item.value = title as NSString
            item.extendedLanguageTag = "und"
            player.currentItem?.externalMetadata = [item]
        }

        // Auto-play
        player.play()
        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {}

    static func dismantleUIViewController(_ uiViewController: AVPlayerViewController, coordinator: ()) {
        uiViewController.player?.pause()
        uiViewController.player = nil
    }
}
#else
// macOS placeholder — AVPlayerView is in AVKit on macOS but needs a different bridge.
struct MediaPlayerView: View {
    let url: URL
    let title: String?
    var body: some View {
        Text("Lecteur vidéo non disponible sur cette plateforme")
            .padding()
    }
}
#endif

/// Convenience host that handles the "download then play" lifecycle.
struct MediaPlayerHost: View {
    let remote: String
    let entry: RemoteEntryDTO

    @State private var localURL: URL?
    @State private var preparing = true
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if preparing {
                VStack(spacing: 12) {
                    ProgressView().controlSize(.large)
                    Text("Téléchargement pour lecture…")
                        .foregroundStyle(.secondary)
                    if let sizeText = entrySizeText {
                        Text(sizeText).font(.caption).foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let url = localURL {
                MediaPlayerView(url: url, title: entry.name)
                    .ignoresSafeArea()
            } else if let error {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.red)
                    Text("Lecture impossible").font(.headline)
                    Text(error).font(.caption).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    Button("Fermer") { dismiss() }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .task { await prepare() }
    }

    private var entrySizeText: String? {
        guard entry.size > 0 else { return nil }
        return ByteCountFormatter.string(fromByteCount: entry.size, countStyle: .file)
    }

    private func prepare() async {
        preparing = true
        do {
            let url = try await MediaCacheService.shared.localPlayableURL(
                remote: remote,
                path: entry.pathInRemote,
                sizeHint: entry.size,
                policy: .reuseIfCached
            )
            localURL = url
        } catch {
            self.error = error.localizedDescription
        }
        preparing = false
    }
}
