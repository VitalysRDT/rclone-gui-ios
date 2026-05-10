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
                preparingState
            } else if let session {
                MediaPlayerView(url: session.url, title: entry.name, sizeHint: entry.size)
                    .ignoresSafeArea()
            } else if let error {
                errorState(error)
            }
        }
        .task { await prepare() }
        .onDisappear {
            if let session {
                Task { await RcloneStreamingService.shared.stop(session) }
            }
        }
    }

    /// Crypt-forward "préparation de la lecture" surface — mirrors the
    /// design's player loading idiom (purple seal + STREAM badge while we
    /// resolve a local URL or set up the streaming session).
    private var preparingState: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.10, green: 0.10, blue: 0.18),
                    Color(red: 0.18, green: 0.11, blue: 0.31),
                    Color(red: 0.36, green: 0.13, blue: 0.71),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 18) {
                RGCryptSeal(size: 88)

                VStack(spacing: 6) {
                    Text("Préparation de la lecture")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(entry.name)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .padding(.horizontal, 24)

                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 6, height: 6)
                    Text("STREAM")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(0.6)
                        .foregroundStyle(.white.opacity(0.85))
                    if let sizeText = entrySizeText {
                        Text("· \(sizeText)")
                            .font(RG.mono)
                            .foregroundStyle(.white.opacity(0.55))
                    }
                }
                .padding(.top, 4)

                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
                    .padding(.top, 8)
            }
        }
    }

    private func errorState(_ message: String) -> some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 14) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle)
                    .foregroundStyle(.red)
                Text("Lecture impossible")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
                Button("Fermer") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .tint(RG.accent)
                    .padding(.top, 4)
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
