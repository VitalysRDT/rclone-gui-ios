//
//  RoadmapView.swift
//  Rclone GUI — Views/Settings
//
//  Compact "what's coming" screen. The full, continuously-evolving roadmap
//  lives on the website (rclone.rougetet.com/#roadmap) so it can change
//  without shipping an App Store update; here we surface the headline items
//  per horizon and link out for the detail. Stays on-brand: privacy-first,
//  open source, no backend.
//

import SwiftUI

struct RoadmapView: View {
    @Environment(\.openURL) private var openURL
    private let fullURL = URL(string: "https://rclone.rougetet.com/#roadmap")!

    var body: some View {
        List {
            Section {
                Text("Ce qui arrive dans Rclone GUI. Tout reste privacy-first, open source et sans serveur.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            horizon(
                label: "Court terme",
                tag: "En préparation",
                tint: .green,
                items: "Transferts Pro · Flows · Ghost Vault · Handoff P2P · Glass Engine"
            )
            horizon(
                label: "Moyen terme",
                tag: "Prévu",
                tint: .blue,
                items: "Remote Lens · Recherche sémantique on-device · Sealed Share · Règles de sync · Mode Voyage"
            )
            horizon(
                label: "Long terme",
                tag: "Vision",
                tint: .purple,
                items: "ChronoDrive · Ghost Sync · Quantum Vault · CipherSpace · Héritage numérique"
            )

            Section {
                Button {
                    openURL(fullURL)
                } label: {
                    Label("Voir la feuille de route complète", systemImage: "safari")
                }
            } footer: {
                Text("Roadmap indicative, sans engagement de date — priorisée avec vos retours.")
            }
        }
        .navigationTitle("Feuille de route")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    @ViewBuilder
    private func horizon(
        label: LocalizedStringKey,
        tag: LocalizedStringKey,
        tint: Color,
        items: LocalizedStringKey
    ) -> some View {
        Section {
            Text(items).font(.callout)
        } header: {
            HStack {
                Text(label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .textCase(nil)
                Spacer()
                Text(tag)
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(tint.opacity(0.18), in: Capsule())
                    .foregroundStyle(tint)
                    .textCase(nil)
            }
        }
    }
}
