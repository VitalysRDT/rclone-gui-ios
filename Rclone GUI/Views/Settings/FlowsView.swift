//
//  FlowsView.swift
//  Rclone GUI — Views/Settings
//
//  Écran « Flows » (RG-2) : présente les automatisations 100 % locales
//  exposées via App Intents, et invite à les composer dans l'app Raccourcis.
//  Aucun serveur, aucun tracking — tout s'exécute sur l'appareil.
//
//  Contenu bilingue FR/EN rendu en `verbatim` (localisé à la main) → n'alimente
//  pas le String Catalog.
//

import SwiftUI

struct FlowsView: View {
    @Environment(\.openURL) private var openURL

    private var useFrench: Bool {
        Locale.current.language.languageCode?.identifier == "fr"
    }

    private struct Flow: Identifiable {
        let id = UUID()
        let icon: String
        let tint: Color
        let titleFR: String
        let titleEN: String
        let descFR: String
        let descEN: String
    }

    private var flows: [Flow] {
        [
            Flow(icon: "photo.on.rectangle.angled", tint: .pink,
                 titleFR: "Sauvegarder mes photos", titleEN: "Back up my photos",
                 descFR: "Lance PhotoSync. Parfait en automatisation : chaque nuit, sur secteur et en Wi-Fi.",
                 descEN: "Runs PhotoSync. Great as an automation: every night, while charging and on Wi-Fi."),
            Flow(icon: "arrow.triangle.2.circlepath", tint: .purple,
                 titleFR: "Sauvegarder un dossier", titleEN: "Back up a folder",
                 descFR: "Synchronise un dossier d'un remote vers un autre (sauvegarde rclone).",
                 descEN: "Syncs a folder from one remote to another (rclone backup)."),
            Flow(icon: "pause.circle.fill", tint: .orange,
                 titleFR: "Mettre les transferts en pause", titleEN: "Pause transfers",
                 descFR: "Suspend tous les transferts — utile pour économiser données ou batterie.",
                 descEN: "Pauses all transfers — handy to save data or battery."),
            Flow(icon: "play.circle.fill", tint: .green,
                 titleFR: "Reprendre les transferts", titleEN: "Resume transfers",
                 descFR: "Relance tous les transferts mis en pause.",
                 descEN: "Resumes all paused transfers."),
            Flow(icon: "externaldrive.fill", tint: .blue,
                 titleFR: "Ouvrir un remote", titleEN: "Open a remote",
                 descFR: "Ouvre directement un remote dans l'app.",
                 descEN: "Opens a remote directly in the app."),
            Flow(icon: "arrow.up.doc", tint: .indigo,
                 titleFR: "Téléverser un fichier", titleEN: "Upload a file",
                 descFR: "Envoie un fichier vers un remote depuis Raccourcis ou la feuille de partage.",
                 descEN: "Sends a file to a remote from Shortcuts or the Share sheet."),
        ]
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label {
                        Text(verbatim: useFrench ? "Automatisations 100 % locales" : "100% local automations")
                            .font(.headline)
                    } icon: {
                        Image(systemName: "wand.and.stars")
                            .foregroundStyle(.purple)
                    }
                    Text(verbatim: useFrench
                         ? "Composez vos propres automatisations dans l'app Raccourcis avec les actions de Rclone GUI. Tout s'exécute sur votre appareil — aucun serveur, aucun tracking."
                         : "Build your own automations in the Shortcuts app using Rclone GUI actions. Everything runs on your device — no server, no tracking.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }

            Section {
                ForEach(flows) { flow in
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: useFrench ? flow.titleFR : flow.titleEN)
                                .font(.body.weight(.medium))
                            Text(verbatim: useFrench ? flow.descFR : flow.descEN)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } icon: {
                        Image(systemName: flow.icon)
                            .foregroundStyle(flow.tint)
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Text(verbatim: useFrench ? "Actions disponibles dans Raccourcis" : "Actions available in Shortcuts")
            }

            Section {
                Button {
                    if let url = URL(string: "shortcuts://") { openURL(url) }
                } label: {
                    Label {
                        Text(verbatim: useFrench ? "Ouvrir l'app Raccourcis" : "Open the Shortcuts app")
                    } icon: {
                        Image(systemName: "square.stack.3d.up")
                    }
                }
            } footer: {
                Text(verbatim: useFrench
                     ? "Astuce : dans Raccourcis → onglet Automatisation, déclenchez « Sauvegarder mes photos » chaque nuit, quand l'appareil est en charge. Vous pouvez aussi demander à Siri : « Sauvegarder mes photos avec Rclone GUI »."
                     : "Tip: in Shortcuts → Automation tab, trigger \"Back up my photos\" every night while charging. You can also ask Siri: \"Back up my photos with Rclone GUI\".")
            }
        }
        .navigationTitle(useFrench ? "Flows" : "Flows")
        #if os(iOS)
        .rgInlineNavTitle()
        #endif
    }
}
