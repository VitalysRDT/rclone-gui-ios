//
//  PlaybackSettingsView.swift
//  Rclone GUI — Views/Settings
//
//  Réglages de lecture : Picture-in-Picture automatique, audio en arrière-plan,
//  vitesse de lecture par défaut. Stockés en UserDefaults et lus par
//  MediaPlayerView (auto-PiP), MainTabView (audio en fond) et
//  AudioPlaybackCoordinator (vitesse).
//

import SwiftUI

enum PlaybackDefaults {
    static let autoPiPKey = "playback.autoPiP"
    static let backgroundAudioKey = "playback.backgroundAudio"
    static let defaultRateKey = "playback.defaultRate"

    /// Clé absente → activé par défaut (UserDefaults.bool renverrait false).
    static var autoPiP: Bool {
        UserDefaults.standard.object(forKey: autoPiPKey) as? Bool ?? true
    }
    static var backgroundAudio: Bool {
        UserDefaults.standard.object(forKey: backgroundAudioKey) as? Bool ?? true
    }
    /// Clé absente / 0 → 1.0× (vitesse normale).
    static var rate: Double {
        let r = UserDefaults.standard.double(forKey: defaultRateKey)
        return r > 0 ? r : 1.0
    }
}

struct PlaybackSettingsView: View {
    @AppStorage(PlaybackDefaults.autoPiPKey) private var autoPiP = true
    @AppStorage(PlaybackDefaults.backgroundAudioKey) private var backgroundAudio = true
    @AppStorage(PlaybackDefaults.defaultRateKey) private var defaultRate = 1.0

    private let rates: [Double] = [0.75, 1.0, 1.25, 1.5, 1.75, 2.0]

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $backgroundAudio) {
                    Label("Audio en arrière-plan", systemImage: "speaker.wave.2")
                }
            } footer: {
                Text("Continuer la lecture audio quand l'app passe en arrière-plan ou que l'écran se verrouille. Désactivé, la lecture se met en pause.")
            }

            Section {
                Toggle(isOn: $autoPiP) {
                    Label("PiP automatique", systemImage: "pip.enter")
                }
            } footer: {
                Text("Basculer la vidéo en Picture-in-Picture (fenêtre flottante) quand tu quittes l'app pendant la lecture.")
            }

            Section {
                Picker(selection: $defaultRate) {
                    ForEach(rates, id: \.self) { r in
                        Text(rateLabel(r)).tag(r)
                    }
                } label: {
                    Label("Vitesse par défaut", systemImage: "gauge.with.dots.needle.67percent")
                }
                #if os(iOS)
                .pickerStyle(.menu)
                #endif
            } footer: {
                Text("Vitesse appliquée au démarrage d'une piste audio (pratique pour les podcasts et livres audio).")
            }
        }
        .navigationTitle("Lecture")
        .rgInlineNavTitle()
    }

    private func rateLabel(_ r: Double) -> String {
        if r == 1.0 { return "Normale (1×)" }
        return String(format: "%g×", r)
    }
}
