//
//  SecuritySettingsView.swift
//  Rclone GUI — Views/Settings
//
//  Biometric gate + auto-wipe inactivity. Phase E v1 wires the toggles
//  to @AppStorage ; the actual enforcement (re-prompt after timeout)
//  is integrated later in Phase E2.
//

import SwiftUI
import SwiftData

struct SecuritySettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("security.requireBiometricsAtLaunch") private var requireBiometrics = true
    @AppStorage("security.inactivityWipeMinutes") private var inactivityWipeMinutes: Int = 30
    @AppStorage("security.wipeCacheOnLock") private var wipeCacheOnLock = true
    @AppStorage(VaultManager.unlockMinutesKey) private var vaultUnlockMinutes: Int = 15
    @State private var biometricsAvailable: Bool = true
    @State private var wipeError: String?
    @State private var wipeSuccess: String?
    @State private var showWipeConfirm = false

    var body: some View {
        Form {
            Section {
                AppHeroCard(
                    title: "Sécurité locale",
                    subtitle: "Protège la configuration rclone, le cache et l’accès à l’app.",
                    systemImage: "lock.shield",
                    tint: .green
                ) {
                    HStack(spacing: 10) {
                        AppMetricPill(value: requireBiometrics ? "Actif" : "Off", label: "biométrie", systemImage: "faceid", tint: .green)
                        AppMetricPill(value: inactivityLabel, label: "verrouillage", systemImage: "timer", tint: .blue)
                    }
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
            }

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
                Toggle("Effacer le cache au verrouillage", isOn: $wipeCacheOnLock)
                    .disabled(!requireBiometrics || inactivityWipeMinutes == 0)
            } footer: {
                Text("Au-delà de cette durée d'inactivité, l'app redemande Face ID / Touch ID. Avec « Effacer le cache au verrouillage », le cache média local (fichiers déchiffrés pour la lecture) est purgé à ce moment-là — rien en clair ne survit à l'inactivité.")
            }

            Section {
                Picker("Durée de déverrouillage du coffre-fort", selection: $vaultUnlockMinutes) {
                    Text("À chaque accès").tag(0)
                    Text("5 min").tag(5)
                    Text("15 min").tag(15)
                    Text("30 min").tag(30)
                    Text("1 h").tag(60)
                }
            } header: {
                Text("Coffre-fort")
            } footer: {
                Text("Mets un remote au coffre-fort depuis l'onglet Fichiers (appui long). Il disparaît alors de l'app Fichiers d'iOS et ne s'ouvre qu'après Face ID / Touch ID. Cette durée définit combien de temps il reste déverrouillé après authentification.")
            }

            Section {
                Button(role: .destructive) {
                    showWipeConfirm = true
                } label: {
                    Label("Effacer la configuration rclone", systemImage: "trash.slash")
                }
            } header: {
                Text("Configuration")
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
        .rgInlineNavTitle()
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
            // Oublie les remotes encore chargés en mémoire par librclone
            // (sinon ils restent navigables après effacement).
            await RcloneCore.shared.resetToEmptyConfig()
            await FileProviderManager.shared.writeRemotesManifest([])
            FileProviderManager.shared.purgeAllFolderManifests()
            // Purge les favoris/récents locaux et l'état du coffre-fort.
            try? SavedLocationStore.removeAll(in: modelContext)
            VaultManager.shared.clearAll()
            await MainActor.run {
                NotificationCenter.default.post(name: .rcloneConfigurationDidChange, object: nil)
            }
            wipeSuccess = "Configuration effacée."
            wipeError = nil
        } catch {
            wipeError = error.localizedDescription
            wipeSuccess = nil
        }
    }

    private var inactivityLabel: String {
        switch inactivityWipeMinutes {
        case 0: return "Jamais"
        case 60: return "1 h"
        case 240: return "4 h"
        case 1440: return "24 h"
        default: return "\(inactivityWipeMinutes) min"
        }
    }
}
