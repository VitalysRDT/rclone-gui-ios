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
                CacheHeaderCard(currentBytes: currentBytes, maxSizeGB: maxSizeGB)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
            } footer: {
                Text("Fichiers téléchargés temporairement pour la lecture. Tu peux les purger à tout moment.")
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
        .rgInlineNavTitle()
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

private struct CacheHeaderCard: View {
    let currentBytes: Int64
    let maxSizeGB: Double

    var body: some View {
        AppHeroCard(
            title: "Cache média",
            subtitle: "Lecture plus fluide, purge locale et limite LRU.",
            systemImage: "tray.full",
            tint: .orange
        ) {
            HStack(spacing: 10) {
                AppMetricPill(value: humanSize(currentBytes), label: "utilisé", systemImage: "internaldrive", tint: .orange)
                AppMetricPill(value: "\(Int(maxSizeGB)) Go", label: "limite", systemImage: "gauge.with.dots.needle.67percent", tint: .blue)
            }
        }
    }

    private func humanSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
