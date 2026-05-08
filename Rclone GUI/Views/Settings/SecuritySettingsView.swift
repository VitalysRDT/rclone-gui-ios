//
//  SecuritySettingsView.swift
//  Rclone GUI — Views/Settings
//
//  Biometric gate + auto-wipe inactivity. Phase E v1 wires the toggles
//  to @AppStorage ; the actual enforcement (re-prompt after timeout)
//  is integrated later in Phase E2.
//

import SwiftUI

struct SecuritySettingsView: View {
    @AppStorage("security.requireBiometricsAtLaunch") private var requireBiometrics = true
    @AppStorage("security.inactivityWipeMinutes") private var inactivityWipeMinutes: Int = 30
    @State private var biometricsAvailable: Bool = true
    @State private var wipeError: String?
    @State private var wipeSuccess: String?
    @State private var showWipeConfirm = false

    var body: some View {
        Form {
            Section {
                Toggle("Face ID / Touch ID au lancement", isOn: $requireBiometrics)
                    .disabled(!biometricsAvailable)
            } footer: {
                if biometricsAvailable {
                    Text("Demande une authentification biométrique à chaque ouverture de l'app.")
                } else {
                    Text("La biométrie n'est pas configurée sur cet appareil.")
                        .foregroundStyle(.orange)
                }
            }

            Section {
                Picker("Inactivité avant verrouillage", selection: $inactivityWipeMinutes) {
                    Text("Jamais").tag(0)
                    Text("5 min").tag(5)
                    Text("15 min").tag(15)
                    Text("30 min").tag(30)
                    Text("1 h").tag(60)
                    Text("4 h").tag(240)
                    Text("24 h").tag(1440)
                }
            } footer: {
                Text("Au-delà de cette durée sans utilisation, l'app re-demande la biométrie. Phase E2 ajoutera le wipe automatique du cache.")
            }

            Section("Configuration") {
                Button(role: .destructive) {
                    showWipeConfirm = true
                } label: {
                    Label("Effacer la configuration rclone", systemImage: "trash.slash")
                }
            } footer: {
                Text("Supprime le rclone.conf chiffré localement et la clé maître Keychain. Tu pourras ré-importer ensuite.")
            }

            if let wipeError {
                Section {
                    Text(wipeError).foregroundStyle(.red)
                }
            } else if let wipeSuccess {
                Section {
                    Text(wipeSuccess).foregroundStyle(.green)
                }
            }
        }
        .navigationTitle("Sécurité")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            biometricsAvailable = await BiometricGate.shared.isAvailable()
        }
        .confirmationDialog(
            "Effacer la configuration ?",
            isPresented: $showWipeConfirm,
            titleVisibility: .visible
        ) {
            Button("Effacer", role: .destructive) {
                Task { await wipeConfig() }
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Cette action est irréversible. Tu pourras ré-importer ton rclone.conf après.")
        }
    }

    private func wipeConfig() async {
        do {
            try await ConfigStore.shared.wipe()
            wipeSuccess = "Configuration effacée."
            wipeError = nil
        } catch {
            wipeError = error.localizedDescription
            wipeSuccess = nil
        }
    }
}
