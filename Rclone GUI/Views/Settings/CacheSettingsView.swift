//
//  CacheSettingsView.swift
//  Rclone GUI — Views/Settings
//

import SwiftUI

struct CacheSettingsView: View {
    @AppStorage("cache.maxSizeGB") private var maxSizeGB: Double = 5.0
    @State private var currentBytes: Int64 = 0
    @State private var purging = false
    @State private var error: String?
    @State private var success: String?

    var body: some View {
        Form {
            Section {
                HStack {
                    Label("Cache média", systemImage: "tray.full")
                    Spacer()
                    Text(humanSize(currentBytes))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            } footer: {
                Text("Fichiers téléchargés temporairement pour la lecture. Effacés au démontage.")
            }

            Section {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Taille max")
                        Spacer()
                        Text("\(Int(maxSizeGB)) Go")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $maxSizeGB, in: 1...50, step: 1) {
                        Text("Cache max")
                    }
                }
            } footer: {
                Text("Quand le cache atteint cette taille, les fichiers les plus anciens sont effacés en premier (LRU — Phase E2).")
            }

            Section {
                Button(role: .destructive) {
                    Task { await purge() }
                } label: {
                    if purging {
                        HStack { ProgressView(); Text("Effacement…") }
                    } else {
                        Label("Effacer le cache maintenant", systemImage: "trash")
                    }
                }
                .disabled(purging || currentBytes == 0)
            } footer: {
                if let error {
                    Text(error).foregroundStyle(.red)
                } else if let success {
                    Text(success).foregroundStyle(.green)
                }
            }
        }
        .navigationTitle("Cache")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await refreshSize() }
    }

    private func refreshSize() async {
        currentBytes = (try? await MediaCacheService.shared.currentSize()) ?? 0
    }

    private func purge() async {
        purging = true
        defer { purging = false }
        do {
            try await MediaCacheService.shared.purge()
            success = "Cache effacé."
            error = nil
        } catch {
            self.error = error.localizedDescription
            success = nil
        }
        await refreshSize()
    }

    private func humanSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
