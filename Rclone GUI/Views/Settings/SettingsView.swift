//
//  SettingsView.swift
//  Rclone GUI — Views/Settings
//
//  Top-level settings screen. Branches to specialized sub-views.
//

import SwiftUI

struct SettingsView: View {
    @State private var showImport = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SettingsHeaderCard()
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowBackground(Color.clear)
                }

                Section("Configuration") {
                    Button {
                        showImport = true
                    } label: {
                        SettingsNavigationRow(
                            icon: "square.and.arrow.down",
                            title: "Importer un rclone.conf",
                            subtitle: "Depuis Files, iCloud ou AirDrop",
                            tint: .blue,
                            showsChevron: false
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        SecuritySettingsView()
                    } label: {
                        SettingsNavigationRow(
                            icon: "lock.shield",
                            title: "Sécurité & biométrie",
                            subtitle: "Verrouillage, Keychain et effacement local",
                            tint: .green
                        )
                    }
                }

                Section("Stockage") {
                    NavigationLink {
                        CacheSettingsView()
                    } label: {
                        SettingsNavigationRow(
                            icon: "tray.full",
                            title: "Cache média",
                            subtitle: "Taille limite et purge des fichiers temporaires",
                            tint: .orange
                        )
                    }

                    NavigationLink {
                        TrashView()
                    } label: {
                        SettingsNavigationRow(
                            icon: "trash",
                            title: "Corbeille",
                            subtitle: "Restaurer ou purger les fichiers supprimés (30 jours)",
                            tint: .red
                        )
                    }

                    NavigationLink {
                        PhotoSyncSettingsView()
                    } label: {
                        SettingsNavigationRow(
                            icon: "photo.stack",
                            title: "Synchro Photos",
                            subtitle: "Backup opportuniste de la photothèque vers un remote",
                            tint: .pink
                        )
                    }
                }

                Section("Diagnostic") {
                    NavigationLink {
                        LogsView()
                    } label: {
                        SettingsNavigationRow(
                            icon: "doc.text.magnifyingglass",
                            title: "Logs",
                            subtitle: "Événements rclone et erreurs récentes",
                            tint: .indigo
                        )
                    }
                    NavigationLink {
                        AboutView()
                    } label: {
                        SettingsNavigationRow(
                            icon: "info.circle",
                            title: "À propos",
                            subtitle: "Version, licences et détails de l'app",
                            tint: .teal
                        )
                    }
                }
            }
            .navigationTitle("Réglages")
            .sheet(isPresented: $showImport) {
                ImportConfigView(onImported: {
                    showImport = false
                })
            }
        }
    }
}

private struct SettingsHeaderCard: View {
    var body: some View {
        HStack(spacing: 14) {
            AppIconTile(
                systemImage: "externaldrive.connected.to.line.below",
                tint: .blue,
                size: 54,
                iconSize: .title2
            )
            VStack(alignment: .leading, spacing: 4) {
                Text("Rclone GUI")
                    .font(.headline)
                Text("Configuration locale, cache média et diagnostics.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: .rect(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.quaternary)
        }
    }
}

private struct SettingsNavigationRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let tint: Color
    var showsChevron = false

    var body: some View {
        HStack(spacing: 12) {
            AppIconTile(systemImage: icon, tint: tint, size: 38, iconSize: .body)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
