//
//  ThumbnailSettingsView.swift
//  Rclone GUI — Views/Settings
//
//  Politique de génération des vignettes de la galerie (impact données) +
//  gestion du cache disque. Voir ThumbnailService.
//

import SwiftUI

struct ThumbnailSettingsView: View {
    @AppStorage(ThumbnailPolicy.defaultsKey) private var policyRaw = ThumbnailPolicy.wifiOnly.rawValue
    @State private var cacheBytes: Int64 = 0
    @State private var isClearing = false

    var body: some View {
        Form {
            Section {
                headerCard
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
            }

            Section {
                Picker("Génération", selection: $policyRaw) {
                    ForEach(ThumbnailPolicy.allCases, id: \.rawValue) { policy in
                        Text(policy.label).tag(policy.rawValue)
                    }
                }
                #if os(iOS)
                .pickerStyle(.menu)
                #endif
            } header: {
                Text("Vignettes")
            } footer: {
                Text("Générer une vignette télécharge des octets depuis le remote (rclone n'a pas de vignettes côté serveur). « Wi-Fi seulement » évite la consommation de données cellulaires ; les vignettes déjà en cache restent affichées dans tous les cas. Les vidéos n'extraient qu'une image (pas de téléchargement complet).")
            }

            Section("Cache des vignettes") {
                LabeledContent("Taille") {
                    Text(ByteCountFormatter.string(fromByteCount: cacheBytes, countStyle: .file))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Button(role: .destructive) {
                    Task { await clearCache() }
                } label: {
                    HStack {
                        Label("Vider le cache des vignettes", systemImage: "trash")
                        if isClearing {
                            Spacer()
                            ProgressView().controlSize(.small)
                        }
                    }
                }
                .disabled(isClearing || cacheBytes == 0)
            }
        }
        .navigationTitle("Vignettes")
        #if os(iOS)
        .rgInlineNavTitle()
        #endif
        .task { refreshSize() }
    }

    @ViewBuilder
    private var headerCard: some View {
        HStack(spacing: 14) {
            AppIconTile(systemImage: "rectangle.grid.3x2.fill", tint: .teal, size: 54, iconSize: .title2)
            VStack(alignment: .leading, spacing: 4) {
                Text("Vignettes de la galerie")
                    .font(.headline)
                Text("Contrôle quand les miniatures images/vidéos sont générées et la taille du cache.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
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

    private func refreshSize() {
        cacheBytes = ThumbnailService.cacheSizeBytes()
    }

    private func clearCache() async {
        isClearing = true
        defer { isClearing = false }
        await ThumbnailService.shared.clearCache()
        refreshSize()
    }
}
