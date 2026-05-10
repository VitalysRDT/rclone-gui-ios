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
    /// Taille du média en octets — sert à décider si PiP/full-screen valent
    /// le coût d'init (skip pour les très petits clips).
    var sizeHint: Int64 = 0

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let player = AVPlayer(url: url)
        // Preroll buffer 2s : limite le stalling initial sans dégrader le TTFP.
        player.automaticallyWaitsToMinimizeStalling = true
        let controller = AVPlayerViewController()
        controller.player = player

        // Feature-gate PiP : init est coûteuse (~50-100ms) et inutile pour
        // les petits clips audio/vidéo. Activé pour ≥ ~5MB ou taille inconnue.
        let isPiPEligible = sizeHint == 0 || sizeHint >= 5_000_000
        controller.allowsPictureInPicturePlayback = isPiPEligible
        controller.canStartPictureInPictureAutomaticallyFromInline = isPiPEligible
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

        // Preroll 2s pour limiter les stalls initiaux.
        player.currentItem?.preferredForwardBufferDuration = 2.0
        // Auto-play
        player.play()
        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {}

    static func dismantleUIViewController(_ uiViewController: AVPlayerViewController, coordinator: ()) {
        // Cleanup explicite : libère decodage HW, buffers HTTP, et casse les
        // observers KVO internes avant que le controller ne soit dealloc.
        if let player = uiViewController.player {
            player.pause()
            player.replaceCurrentItem(with: nil)
        }
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

    @State private var session: StreamingSession?
    @State private var preparing = true
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if preparing {
                VStack(spacing: 12) {
                    ProgressView().controlSize(.large)
                    Text("Préparation de la lecture…")
                        .foregroundStyle(.secondary)
                    if let sizeText = entrySizeText {
                        Text(sizeText).font(.caption).foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let session {
                MediaPlayerView(url: session.url, title: entry.name, sizeHint: entry.size)
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
        .onDisappear {
            if let session {
                Task { await RcloneStreamingService.shared.stop(session) }
            }
        }
    }

    private var entrySizeText: String? {
        guard entry.size > 0 else { return nil }
        return ByteCountFormatter.string(fromByteCount: entry.size, countStyle: .file)
    }

    private func prepare() async {
        preparing = true
        do {
            let session = try await RcloneStreamingService.shared.session(
                remote: remote,
                path: entry.pathInRemote,
                sizeHint: entry.size
            )
            self.session = session
        } catch {
            self.error = error.localizedDescription
        }
        preparing = false
    }
}
