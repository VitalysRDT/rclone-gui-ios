//
//  SettingsView.swift
//  Rclone GUI — Views/Settings
//
//  Phase C placeholder. The full settings (cache, biometrics, OAuth,
//  bandwidth, log export) lands in Phase E.
//

import SwiftUI

struct SettingsView: View {
    @State private var rcloneVersion: String = "—"
    @State private var versionLoadState: VersionLoadState = .idle

    enum VersionLoadState: Equatable {
        case idle
        case loaded(String)
        case failed(String)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Configuration") {
                    NavigationLink {
                        Text("Import du rclone.conf — Phase E")
                            .foregroundStyle(.secondary)
                    } label: {
                        Label("Importer rclone.conf", systemImage: "square.and.arrow.down")
                    }

                    NavigationLink {
                        Text("Sécurité — Phase E")
                            .foregroundStyle(.secondary)
                    } label: {
                        Label("Sécurité & biométrie", systemImage: "lock.shield")
                    }
                }

                Section("À propos") {
                    HStack {
                        Label("Version rclone", systemImage: "shippingbox")
                        Spacer()
                        Text(rcloneVersion).foregroundStyle(.secondary)
                    }
                    .task {
                        do {
                            let v = try await RcloneCore.shared.version()
                            rcloneVersion = v
                            versionLoadState = .loaded(v)
                        } catch {
                            rcloneVersion = "ERR"
                            versionLoadState = .failed(error.localizedDescription)
                        }
                    }

                    if case .failed(let msg) = versionLoadState {
                        Text(msg).font(.caption).foregroundStyle(.red)
                    }
                }

                Section {
                    Text("Réglages complets disponibles en Phase E.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Réglages")
        }
    }
}

#Preview {
    SettingsView()
}
