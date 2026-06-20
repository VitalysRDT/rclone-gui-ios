//
//  NowPlayingService.swift
//  Rclone GUI — Services
//
//  Audio en arrière-plan + contrôles sur l'écran verrouillé / centre de
//  contrôle. Configure l'AVAudioSession en `.playback` (continue à jouer
//  quand l'app passe en arrière-plan, requiert UIBackgroundModes=audio) et
//  publie les métadonnées + commandes distantes via MediaPlayer.
//
//  iOS uniquement : sur macOS la lecture en arrière-plan est implicite et
//  l'API AVAudioSession n'existe pas. Les appels deviennent des no-op.
//

import Foundation
import CoreGraphics

#if os(iOS)
import MediaPlayer
import AVFoundation
import UIKit

@MainActor
final class NowPlayingService {
    static let shared = NowPlayingService()
    private init() {}

    private var commandsConfigured = false

    // Pochette courante (réappliquée à chaque updateNowPlaying pour survivre au
    // remplacement complet de la fiche). Remise à zéro à chaque nouvelle session.
    private var artwork: MPMediaItemArtwork?

    // Callbacks fournis par le lecteur actif.
    private var onPlay: (() -> Void)?
    private var onPause: (() -> Void)?
    private var onNext: (() -> Void)?
    private var onPrevious: (() -> Void)?
    private var onSeek: ((Double) -> Void)?

    /// Active la session audio en lecture (autorise l'arrière-plan + ignore
    /// le switch silencieux). La catégorie `.playback` continue à jouer écran
    /// verrouillé / app en fond (requiert UIBackgroundModes=audio) et ignore le
    /// mute switch. Le `mode` s'adapte au contenu : `.moviePlayback` pour la
    /// vidéo (traitement adapté au film), `.default` pour l'audio pur (musique).
    func beginPlaybackSession(isVideo: Bool = true) {
        artwork = nil
        let session = AVAudioSession.sharedInstance()
        let mode: AVAudioSession.Mode = isVideo ? .moviePlayback : .default
        // setCategory est rapide et doit être posé AVANT play() (détermine le
        // comportement du switch silencieux) → on le garde synchrone.
        try? session.setCategory(.playback, mode: mode, options: [])
        // setActive fait un IPC bloquant avec mediaserverd → hors du main thread
        // pour ne pas figer l'UI (cf. avertissement AVAudioSession_iOS.mm:975).
        Task.detached {
            try? AVAudioSession.sharedInstance().setActive(true, options: [])
        }
    }

    func endPlaybackSession() {
        removeRemoteCommands()
        clearNowPlaying()
        // Désactivation hors du main thread (IPC bloquant — même raison que begin).
        Task.detached {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    /// Comme `removeRemoteCommands` mais sans désactiver la session audio :
    /// à appeler au changement de lecteur/moteur (ex. piste VLC → piste
    /// AVPlayer dans une playlist) pour purger les handlers VLC périmés avant
    /// que le nouveau moteur ne s'installe.
    func resetRemoteCommands() {
        removeRemoteCommands()
    }

    /// Retire nos cibles de commandes distantes. Indispensable entre deux
    /// lecteurs : sinon un handler VLC périmé resterait branché et entrerait
    /// en conflit avec le lecteur système (AVPlayerViewController) qui gère
    /// lui-même l'écran verrouillé.
    private func removeRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.removeTarget(nil)
        center.pauseCommand.removeTarget(nil)
        center.togglePlayPauseCommand.removeTarget(nil)
        center.nextTrackCommand.removeTarget(nil)
        center.previousTrackCommand.removeTarget(nil)
        center.changePlaybackPositionCommand.removeTarget(nil)
        commandsConfigured = false
        onPlay = nil
        onPause = nil
        onNext = nil
        onPrevious = nil
        onSeek = nil
    }

    /// Branche les commandes distantes (play/pause/skip/scrub) sur le lecteur.
    func configureRemoteCommands(
        onPlay: @escaping () -> Void,
        onPause: @escaping () -> Void,
        onNext: (() -> Void)?,
        onPrevious: (() -> Void)?,
        onSeek: @escaping (Double) -> Void
    ) {
        self.onPlay = onPlay
        self.onPause = onPause
        self.onNext = onNext
        self.onPrevious = onPrevious
        self.onSeek = onSeek

        let center = MPRemoteCommandCenter.shared()

        if !commandsConfigured {
            center.playCommand.addTarget { [weak self] _ in
                self?.onPlay?(); return .success
            }
            center.pauseCommand.addTarget { [weak self] _ in
                self?.onPause?(); return .success
            }
            center.togglePlayPauseCommand.addTarget { [weak self] _ in
                self?.onPlay?(); return .success
            }
            center.nextTrackCommand.addTarget { [weak self] _ in
                guard let next = self?.onNext else { return .commandFailed }
                next(); return .success
            }
            center.previousTrackCommand.addTarget { [weak self] _ in
                guard let prev = self?.onPrevious else { return .commandFailed }
                prev(); return .success
            }
            center.changePlaybackPositionCommand.addTarget { [weak self] event in
                guard let e = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
                self?.onSeek?(e.positionTime); return .success
            }
            commandsConfigured = true
        }

        center.nextTrackCommand.isEnabled = (onNext != nil)
        center.previousTrackCommand.isEnabled = (onPrevious != nil)
        center.changePlaybackPositionCommand.isEnabled = true
    }

    /// Met à jour la fiche Now Playing (titre, durée, position, état). Réapplique
    /// la pochette stockée pour qu'elle survive au remplacement de la fiche.
    func updateNowPlaying(title: String, durationSeconds: Double, elapsedSeconds: Double, rate: Float) {
        var info: [String: Any] = [:]
        info[MPMediaItemPropertyTitle] = title
        if durationSeconds > 0, durationSeconds.isFinite {
            info[MPMediaItemPropertyPlaybackDuration] = durationSeconds
        }
        if elapsedSeconds.isFinite {
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = max(0, elapsedSeconds)
        }
        info[MPNowPlayingInfoPropertyPlaybackRate] = rate
        if let artwork {
            info[MPMediaItemPropertyArtwork] = artwork
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    /// Définit la pochette affichée sur l'écran verrouillé / centre de contrôle.
    func setNowPlayingArtwork(_ image: CGImage?) {
        if let image {
            let ui = UIImage(cgImage: image)
            artwork = MPMediaItemArtwork(boundsSize: ui.size) { _ in ui }
        } else {
            artwork = nil
        }
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPMediaItemPropertyArtwork] = artwork
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    func clearNowPlaying() {
        artwork = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }
}

#else

/// Stub no-op (macOS / autres) : la lecture en arrière-plan y est implicite.
@MainActor
final class NowPlayingService {
    static let shared = NowPlayingService()
    private init() {}

    func beginPlaybackSession(isVideo: Bool = true) {}
    func endPlaybackSession() {}
    func resetRemoteCommands() {}
    func configureRemoteCommands(
        onPlay: @escaping () -> Void,
        onPause: @escaping () -> Void,
        onNext: (() -> Void)?,
        onPrevious: (() -> Void)?,
        onSeek: @escaping (Double) -> Void
    ) {}
    func updateNowPlaying(title: String, durationSeconds: Double, elapsedSeconds: Double, rate: Float) {}
    func setNowPlayingArtwork(_ image: CGImage?) {}
    func clearNowPlaying() {}
}

#endif
