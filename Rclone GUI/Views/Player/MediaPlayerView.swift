//
//  MediaPlayerView.swift
//  Rclone GUI — Views/Player
//
//  Routeur de lecture in-app. `MediaPlayerHost` :
//    1. prépare une session de streaming (RcloneStreamingService — bridge
//       loopback HTTP seekable, fallback download).
//    2. choisit le moteur via MediaFormat.engine(for:) :
//         - .avFoundation → AVPlayerViewController (PiP, déco HW, AirPlay,
//           sélecteur de sous-titres natif) pour MP4/MOV/M4V + audio.
//         - .vlc → EmbeddedVLCPlayerView (libVLC) pour MKV/AVI/WebM/TS…
//    3. gère la playlist du dossier (suivant/précédent + auto-enchaînement),
//       la reprise de position, et propose l'ouverture dans une app externe.
//

import SwiftUI
import AVKit
import AVFoundation

// MARK: - AVPlayer surface (formats nativement compatibles)

#if canImport(UIKit)
import UIKit

struct MediaPlayerView: UIViewControllerRepresentable {
    let url: URL
    let title: String?
    let remote: String
    let path: String
    var sizeHint: Int64 = 0
    /// Appelé en fin de lecture (enchaînement playlist).
    var onEnded: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(remote: remote, path: path, title: title, onEnded: onEnded)
    }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let player = AVPlayer(url: url)
        player.automaticallyWaitsToMinimizeStalling = true
        let controller = AVPlayerViewController()
        controller.player = player

        let isPiPEligible = sizeHint == 0 || sizeHint >= 5_000_000
        controller.allowsPictureInPicturePlayback = isPiPEligible
        controller.canStartPictureInPictureAutomaticallyFromInline = isPiPEligible
        controller.entersFullScreenWhenPlaybackBegins = true
        controller.exitsFullScreenWhenPlaybackEnds = false
        controller.modalPresentationStyle = .fullScreen
        if let title {
            let item = AVMutableMetadataItem()
            item.identifier = .commonIdentifierTitle
            item.value = title as NSString
            item.extendedLanguageTag = "und"
            player.currentItem?.externalMetadata = [item]
        }
        player.currentItem?.preferredForwardBufferDuration = 2.0

        context.coordinator.attach(to: player)
        player.play()
        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {}

    static func dismantleUIViewController(_ uiViewController: AVPlayerViewController, coordinator: Coordinator) {
        coordinator.teardown()
        if let player = uiViewController.player {
            player.pause()
            player.replaceCurrentItem(with: nil)
        }
        uiViewController.player = nil
    }

    /// Gère reprise, sauvegarde de position, Now Playing et fin de lecture
    /// pour le chemin AVPlayer.
    final class Coordinator {
        private let remote: String
        private let path: String
        private let title: String?
        private let onEnded: (() -> Void)?

        private weak var player: AVPlayer?
        private var timeObserver: Any?
        private var endObserver: NSObjectProtocol?
        private var didResume = false
        private var lastSavedSecond = -1

        init(remote: String, path: String, title: String?, onEnded: (() -> Void)?) {
            self.remote = remote
            self.path = path
            self.title = title
            self.onEnded = onEnded
        }

        func attach(to player: AVPlayer) {
            self.player = player

            let interval = CMTime(seconds: 1, preferredTimescale: 1)
            timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
                self?.tick(time)
            }

            endObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: player.currentItem,
                queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                PlaybackProgressStore.clear(remote: self.remote, path: self.path)
                self.onEnded?()
            }
        }

        private func tick(_ time: CMTime) {
            guard let player, let item = player.currentItem else { return }
            let elapsed = time.seconds
            let duration = item.duration.seconds
            guard elapsed.isFinite else { return }

            // Reprise : une seule fois, quand la durée est connue.
            if !didResume, duration.isFinite, duration > 0 {
                didResume = true
                if let resume = PlaybackProgressStore.resumePosition(remote: remote, path: path),
                   resume > 1, resume < duration - 15 {
                    player.seek(to: CMTime(seconds: resume, preferredTimescale: 600))
                }
            }

            let second = Int(elapsed)
            if second != lastSavedSecond {
                lastSavedSecond = second
                if duration.isFinite, duration > 0 {
                    PlaybackProgressStore.save(remote: remote, path: path, position: elapsed, duration: duration)
                }
                NowPlayingService.shared.updateNowPlaying(
                    title: title ?? path,
                    durationSeconds: duration.isFinite ? duration : 0,
                    elapsedSeconds: elapsed,
                    rate: player.rate
                )
            }
        }

        func teardown() {
            if let player, let timeObserver {
                player.removeTimeObserver(timeObserver)
            }
            timeObserver = nil
            if let endObserver {
                NotificationCenter.default.removeObserver(endObserver)
            }
            endObserver = nil
            // Sauvegarde finale.
            if let player, let item = player.currentItem {
                let elapsed = player.currentTime().seconds
                let duration = item.duration.seconds
                if elapsed.isFinite, duration.isFinite {
                    PlaybackProgressStore.save(remote: remote, path: path, position: elapsed, duration: duration)
                }
            }
        }
    }
}
#else
// macOS : VideoPlayer SwiftUI (AVKit) avec reprise + fin de lecture.
struct MediaPlayerView: View {
    let url: URL
    let title: String?
    let remote: String
    let path: String
    var sizeHint: Int64 = 0
    var onEnded: (() -> Void)?

    @State private var player: AVPlayer?
    @State private var endObserver: NSObjectProtocol?

    var body: some View {
        VideoPlayer(player: player)
            .onAppear {
                let p = AVPlayer(url: url)
                p.automaticallyWaitsToMinimizeStalling = true
                p.currentItem?.preferredForwardBufferDuration = 2.0
                player = p
                if let resume = PlaybackProgressStore.resumePosition(remote: remote, path: path), resume > 1 {
                    // Attendre que l'item soit prêt avant de seek, sinon
                    // AVFoundation ignore le seek et repart du début.
                    Task { @MainActor in
                        for _ in 0..<40 {
                            if p.currentItem?.status == .readyToPlay { break }
                            try? await Task.sleep(for: .milliseconds(100))
                        }
                        p.seek(to: CMTime(seconds: resume, preferredTimescale: 600))
                    }
                }
                endObserver = NotificationCenter.default.addObserver(
                    forName: .AVPlayerItemDidPlayToEndTime,
                    object: p.currentItem,
                    queue: .main
                ) { _ in
                    PlaybackProgressStore.clear(remote: remote, path: path)
                    onEnded?()
                }
                p.play()
            }
            .onDisappear {
                if let p = player, let item = p.currentItem {
                    let elapsed = p.currentTime().seconds
                    let duration = item.duration.seconds
                    if elapsed.isFinite, duration.isFinite {
                        PlaybackProgressStore.save(remote: remote, path: path, position: elapsed, duration: duration)
                    }
                }
                if let endObserver {
                    NotificationCenter.default.removeObserver(endObserver)
                }
                endObserver = nil
                player?.pause()
                player?.replaceCurrentItem(with: nil)
                player = nil
            }
    }
}
#endif

// MARK: - Host / routeur

struct MediaPlayerHost: View {
    let remote: String
    let playlist: [RemoteEntryDTO]

    @State private var index: Int
    @State private var session: StreamingSession?
    @State private var subtitles: [SidecarSubtitle] = []
    @State private var preparing = true
    @State private var error: String?
    @State private var engine: PlaybackEngine = .avFoundation
    @Environment(\.dismiss) private var dismiss

    init(remote: String, entry: RemoteEntryDTO, playlist: [RemoteEntryDTO]? = nil) {
        self.remote = remote
        let resolved = (playlist?.isEmpty == false) ? playlist! : [entry]
        self.playlist = resolved
        _index = State(initialValue: resolved.firstIndex(of: entry) ?? 0)
    }

    private var entry: RemoteEntryDTO {
        playlist[min(max(index, 0), playlist.count - 1)]
    }
    private var hasNext: Bool { index < playlist.count - 1 }
    private var hasPrevious: Bool { index > 0 }

    var body: some View {
        Group {
            if let error {
                errorState(error)
            } else if preparing {
                preparingState
            } else if let session {
                player(for: session)
            }
        }
        .task(id: index) { await prepare() }
        .onDisappear {
            stopCurrentSession()
            NowPlayingService.shared.endPlaybackSession()
        }
    }

    @ViewBuilder
    private func player(for session: StreamingSession) -> some View {
        switch engine {
        case .vlc:
            EmbeddedVLCPlayerView(
                streamURL: session.url,
                title: entry.name,
                remote: remote,
                path: entry.pathInRemote,
                subtitles: subtitles,
                hasNext: hasNext,
                hasPrevious: hasPrevious,
                onNext: hasNext ? { advance(by: 1) } : nil,
                onPrevious: hasPrevious ? { advance(by: -1) } : nil,
                onOpenExternal: { openExternal(session) },
                onClose: { dismiss() }
            )
            .ignoresSafeArea()
            .id(index)
        case .avFoundation:
            MediaPlayerView(
                url: session.url,
                title: entry.name,
                remote: remote,
                path: entry.pathInRemote,
                sizeHint: entry.size,
                onEnded: { advanceOrClose() }
            )
            .ignoresSafeArea()
            .id(index)
        }
    }

    // MARK: Playlist

    private func advance(by delta: Int) {
        let next = index + delta
        guard next >= 0, next < playlist.count else { return }
        stopCurrentSession()
        index = next
    }

    private func advanceOrClose() {
        if hasNext { advance(by: 1) } else { dismiss() }
    }

    // MARK: Préparation

    private func prepare() async {
        preparing = true
        error = nil
        engine = MediaFormat.engine(for: entry.name)
        NowPlayingService.shared.beginPlaybackSession()
        do {
            let s = try await RcloneStreamingService.shared.session(
                remote: remote,
                path: entry.pathInRemote,
                sizeHint: entry.size
            )
            self.session = s
            // Sous-titres sidecar (best-effort, n'échoue pas la lecture).
            if MediaFormat.isVideo(entry.name) {
                self.subtitles = await SubtitleService.shared.discover(remote: remote, videoPath: entry.pathInRemote)
            } else {
                self.subtitles = []
            }
        } catch {
            self.error = error.localizedDescription
        }
        preparing = false
    }

    private func stopCurrentSession() {
        if let session {
            let s = session
            Task { await RcloneStreamingService.shared.stop(s) }
            self.session = nil
        }
    }

    private func openExternal(_ session: StreamingSession) {
        guard let callbackURL = EntryActionsMenu.ExternalPlayerScheme.vlc.callbackURL(for: session.url) else { return }
        #if canImport(UIKit)
        UIApplication.shared.open(callbackURL)
        #elseif canImport(AppKit)
        NSWorkspace.shared.open(callbackURL)
        #endif
    }

    // MARK: États de chargement / erreur

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
                    Text(engine == .vlc ? "VLC · STREAM" : "STREAM")
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
}
