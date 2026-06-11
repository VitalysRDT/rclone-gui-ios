//
//  SettingsView.swift
//  Rclone GUI — Views/Settings
//
//  Top-level settings screen. Branches to specialized sub-views.
//

import SwiftUI

struct SettingsView: View {
    @State private var showAddRemote = false
    @State private var showImport = false
    @State private var showExportShare = false
    @State private var exportURL: URL?
    @State private var exportError: String?

    var body: some View {
        Form {
            Section {
                SettingsHeaderCard()
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
            }

            Section("Abonnement") {
                SubscriptionStatusRow()
            }

            Section("Configuration") {
                Button {
                    showAddRemote = true
                } label: {
                    SettingsNavigationRow(
                        icon: "externaldrive.badge.plus",
                        title: "Ajouter un remote",
                        subtitle: "Créer une entrée rclone manuellement",
                        tint: .blue,
                        showsChevron: false
                    )
                }
                .buttonStyle(.plain)

                Button {
                    showImport = true
                } label: {
                    SettingsNavigationRow(
                        icon: "square.and.arrow.down",
                        title: "Importer un rclone.conf",
                        subtitle: "Depuis Fichiers, iCloud ou AirDrop",
                        tint: .blue,
                        showsChevron: false
                    )
                }
                .buttonStyle(.plain)

                Button {
                    Task { await exportConfig() }
                } label: {
                    SettingsNavigationRow(
                        icon: "square.and.arrow.up",
                        title: "Exporter rclone.conf",
                        subtitle: "Partager ta configuration déchiffrée",
                        tint: .orange,
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
                    PerformanceSettingsView()
                } label: {
                    SettingsNavigationRow(
                        icon: "speedometer",
                        title: "Performance",
                        subtitle: "Limite de bande passante et pause globale des transferts",
                        tint: .indigo
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
                        subtitle: "Version, licences et détails de l’app",
                        tint: .teal
                    )
                }
            }

            Section("Support") {
                NavigationLink {
                    ContactSupportView()
                } label: {
                    SettingsNavigationRow(
                        icon: "envelope.fill",
                        title: "Contacter le développeur",
                        subtitle: "Bug, idée ou question — par e-mail",
                        tint: .blue
                    )
                }
            }

            #if DEBUG
            Section {
                DebugTrialResetRow()
            } header: {
                Text("Développeur (DEBUG)")
            } footer: {
                Text("Efface l'ancre d'essai (Keychain + iCloud) pour rejouer les 7 jours. Absent du build App Store.")
            }
            #endif
        }
        .navigationTitle("Réglages")
        .sheet(isPresented: $showAddRemote) {
            AddRemoteWizard(onSaved: {
                showAddRemote = false
            })
        }
        .sheet(isPresented: $showImport) {
            ImportConfigView(onImported: {
                showImport = false
            })
        }
        #if canImport(UIKit)
        .sheet(isPresented: $showExportShare) {
            if let exportURL {
                ShareLink(item: exportURL) {
                    Label("Partager rclone.conf", systemImage: "square.and.arrow.up")
                        .padding()
                }
            }
        }
        #endif
        .alert(
            "Export impossible",
            isPresented: Binding(
                get: { exportError != nil },
                set: { if !$0 { exportError = nil } }
            ),
            presenting: exportError
        ) { _ in
            Button("OK", role: .cancel) { exportError = nil }
        } message: { message in
            Text(message)
        }
    }

    private func exportConfig() async {
        do {
            exportURL = try await ConfigStore.shared.exportPlaintextCopy()
            showExportShare = true
        } catch {
            exportError = error.localizedDescription
        }
    }
}

private struct SettingsHeaderCard: View {
    /// Mirrors the design's "Vitalys ROUGETET" account card with a
    /// purple-gradient initials avatar — surfaces who's logged in plus
    /// a single subtitle that describes the current rclone.conf state.
    @State private var remoteCount: Int = 0
    @State private var hasConfig = false

    var body: some View {
        HStack(spacing: 12) {
            RGGradientAvatar(name: ownerName, size: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(ownerName)
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.rgGroupedRowBackground,
                    in: RoundedRectangle(cornerRadius: RG.Radius.card, style: .continuous))
        .task { await refresh() }
        .accessibilityElement(children: .combine)
    }

    private var ownerName: String {
        // Best-effort from Apple ID iCloud account; falls back to a
        // generic label when iCloud isn't reachable. We don't ship a
        // user store, so this stays a UI-only signal.
        #if os(macOS)
        return String(localized: "Mon Mac")
        #else
        return String(localized: "Mon iPhone")
        #endif
    }

    private var subtitle: String {
        if !hasConfig {
            return String(localized: "Aucun rclone.conf — importer pour démarrer")
        }
        let suffix = remoteCount == 1 ? "remote" : "remotes"
        return String(localized: "rclone.conf · \(remoteCount) \(suffix) · iCloud sync")
    }

    private func refresh() async {
        hasConfig = await ConfigStore.shared.hasStoredConf()
        if hasConfig, let summaries = try? await RemoteService.shared.listRemoteSummaries() {
            remoteCount = summaries.count
        }
    }
}

private struct SubscriptionStatusRow: View {
    @ObservedObject private var subs = SubscriptionService.shared
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(RG.accent)
                    .frame(width: 30, height: 30)
                    .overlay {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                VStack(alignment: .leading, spacing: 2) {
                    Text(statusTitle)
                        .font(.body.weight(.medium))
                    Text(statusSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
            }
            .padding(.vertical, 4)

            HStack(spacing: 8) {
                Button {
                    if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
                        openURL(url)
                    }
                } label: {
                    Text("Gérer mon abonnement")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(RG.accentSoft, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .foregroundStyle(RG.accent)
                }
                .buttonStyle(.plain)

                Button {
                    Task { await subs.restorePurchases() }
                } label: {
                    HStack(spacing: 5) {
                        if subs.isRestoring {
                            ProgressView()
                                .progressViewStyle(.circular)
                        }
                        Text("Restaurer")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(RG.accentSoft, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .foregroundStyle(RG.accent)
                }
                .buttonStyle(.plain)
                .disabled(subs.isRestoring)
            }
        }
    }

    private var statusTitle: String {
        switch subs.snapshot.entitlement {
        case .trial:   return String(localized: "Essai gratuit en cours")
        case .active:  return String(localized: "Abonnement actif")
        case .expired: return String(localized: "Abonnement expiré")
        case .none:    return String(localized: "Aucun abonnement")
        }
    }

    private var statusSubtitle: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none

        switch subs.snapshot.entitlement {
        case .trial:
            if let expiration = subs.snapshot.expirationDate {
                return String(localized: "Fin de l'essai : \(formatter.string(from: expiration))")
            }
            return String(localized: "7 jours offerts")
        case .active:
            let plan = planLabel(for: subs.snapshot.productID)
            if let expiration = subs.snapshot.expirationDate {
                return String(localized: "\(plan) · renouvellement : \(formatter.string(from: expiration))")
            }
            return plan
        case .expired:
            return String(localized: "Souscris à nouveau pour réutiliser l'app")
        case .none:
            return String(localized: "Souscris pour débloquer l'app")
        }
    }

    private func planLabel(for productID: String?) -> String {
        switch productID {
        case SubscriptionProductID.monthly: return String(localized: "Mensuel — 1,99 €")
        case SubscriptionProductID.yearly:  return String(localized: "Annuel — 19,99 €")
        default: return String(localized: "Premium")
        }
    }
}

#if DEBUG
/// Bouton de test (DEBUG only) : réinitialise l'essai gratuit en ré-ancrant
/// une date fraîche (essai 7 jours immédiatement actif, donc PAS de paywall),
/// puis ferme l'app pour forcer un cold start propre. À la réouverture, l'essai
/// est tout neuf — comme un utilisateur installant l'app pour la première fois.
private struct DebugTrialResetRow: View {
    @ObservedObject private var subs = SubscriptionService.shared
    @State private var didReset = false

    var body: some View {
        Button(role: .destructive) {
            // Efface les deux stores PUIS ré-ancre Date() fraîche : l'essai 7j
            // redevient actif tout de suite, sinon refreshEntitlements verrait
            // « aucun essai » et afficherait le paywall.
            TrialStore.resetForTesting()
            TrialStore.startTrialIfNeeded()
            didReset = true
            Task {
                await subs.refreshEntitlements()
                // Laisse l'iCloud KVS pousser la nouvelle date, puis ferme
                // l'app : iOS ne sait pas se relancer seul, donc rouvre-la à la
                // main pour un démarrage propre avec l'essai tout neuf.
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                exit(0)
            }
        } label: {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.red)
                    .frame(width: 30, height: 30)
                    .overlay {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Réinitialiser l'essai")
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(didReset ? "Essai à 7 jours · fermeture…" : "Repart à 7 jours puis ferme l'app")
                        .font(.caption)
                        .foregroundStyle(didReset ? Color.green : Color.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}
#endif

private struct SettingsNavigationRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let tint: Color
    var showsChevron = false

    var body: some View {
        HStack(spacing: 12) {
            // Filled tile — mirrors the design's iOS-Settings style
            // colorful 30×30 squares with white glyphs.
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(tint)
                .frame(width: 30, height: 30)
                .overlay {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                }
            VStack(alignment: .leading, spacing: 2) {
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
