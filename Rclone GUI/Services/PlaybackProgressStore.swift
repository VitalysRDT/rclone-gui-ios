//
//  PlaybackProgressStore.swift
//  Rclone GUI — Services
//
//  Mémorise la position de lecture par (remote, chemin) pour reprendre une
//  vidéo là où on l'a laissée. Persisté dans UserDefaults (léger, survit aux
//  relaunchs). Partagé par les deux moteurs (AVPlayer et VLC).
//

import Foundation

struct PlaybackProgress: Codable, Sendable {
    let positionSeconds: Double
    let durationSeconds: Double
    let updatedAt: Date
}

public enum PlaybackProgressStore {
    private static let prefix = "playback.progress."

    // En-deçà : pas la peine de mémoriser (on était au tout début).
    private static let minResumeSeconds: Double = 8
    // Marge de fin : si on est à moins de ça de la fin, on considère « vu »
    // et on efface la reprise (relancer repart du début).
    private static let endMarginSeconds: Double = 15

    private static func key(remote: String, path: String) -> String {
        prefix + remote + ":" + path
    }

    /// Enregistre la position courante. Efface l'entrée si on est trop tôt
    /// ou quasiment à la fin.
    public static func save(remote: String, path: String, position: Double, duration: Double) {
        guard duration > 0, position.isFinite, duration.isFinite else { return }
        if position < minResumeSeconds || position > duration - endMarginSeconds {
            clear(remote: remote, path: path)
            return
        }
        let progress = PlaybackProgress(
            positionSeconds: position,
            durationSeconds: duration,
            updatedAt: Date()
        )
        if let data = try? JSONEncoder().encode(progress) {
            UserDefaults.standard.set(data, forKey: key(remote: remote, path: path))
        }
    }

    /// Position de reprise en secondes, ou nil si rien à reprendre.
    public static func resumePosition(remote: String, path: String) -> Double? {
        guard let data = UserDefaults.standard.data(forKey: key(remote: remote, path: path)),
              let progress = try? JSONDecoder().decode(PlaybackProgress.self, from: data) else {
            return nil
        }
        return progress.positionSeconds
    }

    public static func clear(remote: String, path: String) {
        UserDefaults.standard.removeObject(forKey: key(remote: remote, path: path))
    }
}
