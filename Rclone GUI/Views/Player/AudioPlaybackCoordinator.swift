//
//  AudioPlaybackCoordinator.swift
//  Rclone GUI — Views/Player
//
//  Coordinateur de lecture AUDIO au niveau de l'app. Contrairement à la vidéo
//  (qui reste dans un AVPlayerViewController plein écran pour le PiP), l'audio
//  a besoin de *survivre à la navigation* : on le pilote donc depuis un
//  ObservableObject injecté à la racine, qui possède son propre AVPlayer.
//
//  Pas de PiP côté audio → aucun des pièges de cycle de vie du lecteur vidéo.
//  Réutilise RcloneStreamingService (bridge loopback seekable), NowPlayingService
//  (écran verrouillé + pochette) et PlaybackProgressStore (reprise).
//

import SwiftUI
import Combine
import AVFoundation
import CoreGraphics
import ImageIO

@MainActor
final class AudioPlaybackCoordinator: ObservableObject {
    @Published private(set) var remote: String = ""
    @Published private(set) var queue: [RemoteEntryDTO] = []
    @Published private(set) var index: Int = 0
    @Published private(set) var isPlaying = false
    @Published private(set) var isLoading = false
    @Published private(set) var elapsed: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var artwork: CGImage?
    @Published private(set) var errorMessage: String?

    var current: RemoteEntryDTO? { queue.indices.contains(index) ? queue[index] : nil }
    var title: String { current?.name ?? "" }
    var hasNext: Bool { index < queue.count - 1 }
    var hasPrevious: Bool { index > 0 }
    var isActive: Bool { current != nil }

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var session: StreamingSession?
    /// Jeton anti-course : invalide une extraction de pochette si on a changé de
    /// piste entretemps.
    private var loadToken = 0

    // MARK: - API publique

    /// Démarre la lecture d'une piste audio dans le contexte de sa file (toutes
    /// les pistes audio AVFoundation du dossier, dans l'ordre affiché).
    func play(remote: String, entry: RemoteEntryDTO, queue: [RemoteEntryDTO]) async {
        self.remote = remote
        let resolved = queue.isEmpty ? [entry] : queue
        self.queue = resolved
        self.index = resolved.firstIndex(of: entry) ?? 0
        await loadCurrent()
    }

    func togglePlayPause() {
        guard let player else { return }
        if isPlaying {
            player.pause(); isPlaying = false
        } else {
            player.play(); isPlaying = true
        }
        updateNowPlaying()
    }

    func resume() { player?.play(); isPlaying = true; updateNowPlaying() }
    func pause() { player?.pause(); isPlaying = false; updateNowPlaying() }

    func next() async {
        guard hasNext else { return }
        index += 1
        await loadCurrent()
    }

    func previous() async {
        // > 3 s écoulées → on revient au début de la piste courante.
        if elapsed > 3, let player {
            await player.seek(to: .zero)
            elapsed = 0
            updateNowPlaying()
            return
        }
        guard hasPrevious else { return }
        index -= 1
        await loadCurrent()
    }

    func seek(to seconds: Double) {
        guard let player else { return }
        let clamped = max(0, min(seconds, duration > 0 ? duration : seconds))
        player.seek(to: CMTime(seconds: clamped, preferredTimescale: 600))
        elapsed = clamped
        updateNowPlaying()
    }

    func stop() {
        saveProgress()
        teardownPlayer()
        if let s = session {
            session = nil
            Task { await RcloneStreamingService.shared.stop(s) }
        }
        NowPlayingService.shared.endPlaybackSession()
        queue = []; index = 0
        isPlaying = false; isLoading = false
        elapsed = 0; duration = 0
        artwork = nil; remote = ""; errorMessage = nil
    }

    // MARK: - Chargement

    private func loadCurrent() async {
        guard let entry = current else { return }
        teardownPlayer()
        if let s = session {
            session = nil
            await RcloneStreamingService.shared.stop(s)
        }
        loadToken &+= 1
        let token = loadToken

        isLoading = true
        errorMessage = nil
        elapsed = 0
        duration = 0
        artwork = nil
        NowPlayingService.shared.setNowPlayingArtwork(nil)
        NowPlayingService.shared.resetRemoteCommands()
        NowPlayingService.shared.beginPlaybackSession(isVideo: false)

        do {
            let s = try await RcloneStreamingService.shared.session(
                remote: remote, path: entry.pathInRemote, sizeHint: entry.size
            )
            guard token == loadToken else {
                await RcloneStreamingService.shared.stop(s)
                return
            }
            self.session = s

            let p = AVPlayer(url: s.url)
            p.automaticallyWaitsToMinimizeStalling = true
            self.player = p
            attachObservers(to: p)
            configureRemoteCommands()
            p.play()
            isPlaying = true
            isLoading = false

            if let resume = PlaybackProgressStore.resumePosition(remote: remote, path: entry.pathInRemote),
               resume > 1 {
                await p.seek(to: CMTime(seconds: resume, preferredTimescale: 600))
            }
            updateNowPlaying()
            await loadArtwork(from: s.url, token: token)
        } catch {
            guard token == loadToken else { return }
            isLoading = false
            errorMessage = error.localizedDescription
        }
    }

    private func attachObservers(to player: AVPlayer) {
        let interval = CMTime(seconds: 1, preferredTimescale: 1)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                self?.tick(time)
            }
        }
        if let item = player.currentItem {
            endObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: item,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    Task { await self.handleTrackEnd() }
                }
            }
        }
    }

    private func tick(_ time: CMTime) {
        guard let player, let item = player.currentItem else { return }
        let e = time.seconds
        let d = item.duration.seconds
        if e.isFinite { elapsed = e }
        if d.isFinite, d > 0 { duration = d }
        isPlaying = player.rate != 0
        saveProgress()
        updateNowPlaying()
    }

    private func handleTrackEnd() async {
        if let entry = current {
            PlaybackProgressStore.clear(remote: remote, path: entry.pathInRemote)
        }
        if hasNext {
            index += 1
            await loadCurrent()
        } else {
            stop()
        }
    }

    private func saveProgress() {
        guard let entry = current, elapsed.isFinite, duration.isFinite, duration > 0 else { return }
        PlaybackProgressStore.save(remote: remote, path: entry.pathInRemote, position: elapsed, duration: duration)
    }

    private func teardownPlayer() {
        if let player, let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = nil
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
    }

    private func configureRemoteCommands() {
        NowPlayingService.shared.configureRemoteCommands(
            onPlay: { [weak self] in self?.resume() },
            onPause: { [weak self] in self?.pause() },
            onNext: hasNext ? { [weak self] in Task { await self?.next() } } : nil,
            onPrevious: { [weak self] in Task { await self?.previous() } },
            onSeek: { [weak self] t in self?.seek(to: t) }
        )
    }

    private func updateNowPlaying() {
        NowPlayingService.shared.updateNowPlaying(
            title: title,
            durationSeconds: duration,
            elapsedSeconds: elapsed,
            rate: isPlaying ? 1 : 0
        )
    }

    /// Extrait la pochette embarquée (ID3 / atom m4a) via les métadonnées AVAsset.
    private func loadArtwork(from url: URL, token: Int) async {
        let asset = AVURLAsset(url: url)
        guard let items = try? await asset.load(.commonMetadata) else { return }
        let artItems = AVMetadataItem.metadataItems(
            from: items,
            filteredByIdentifier: .commonIdentifierArtwork
        )
        for item in artItems {
            if let data = try? await item.load(.dataValue),
               let source = CGImageSourceCreateWithData(data as CFData, nil),
               let cg = CGImageSourceCreateImageAtIndex(source, 0, nil) {
                guard token == loadToken else { return }
                artwork = cg
                NowPlayingService.shared.setNowPlayingArtwork(cg)
                return
            }
        }
    }
}
