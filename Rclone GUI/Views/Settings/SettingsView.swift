//
//  SettingsView.swift
//  Rclone GUI — Views/Settings
//
//  Top-level settings screen. Branches to specialized sub-views.
//

import SwiftUI
import StoreKit

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

                NavigationLink {
                    RemoteManagementView()
                } label: {
                    SettingsNavigationRow(
                        icon: "slider.horizontal.3",
                        title: "Gérer les remotes",
                        subtitle: "Modifier les paramètres ou réautoriser un token",
                        tint: .indigo
                    )
                }

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

                NavigationLink {
                    FlowsView()
                } label: {
                    SettingsNavigationRow(
                        icon: "wand.and.stars",
                        title: "Flows & automatisations",
                        subtitle: "Raccourcis et actions Siri, 100 % locaux",
                        tint: .purple
                    )
                }

                NavigationLink {
                    PlaybackSettingsView()
                } label: {
                    SettingsNavigationRow(
                        icon: "play.rectangle.on.rectangle",
                        title: "Lecture",
                        subtitle: "Audio en fond, PiP automatique, vitesse",
                        tint: .pink
                    )
                }

                NavigationLink {
                    GhostVaultSettingsView()
                } label: {
                    SettingsNavigationRow(
                        icon: "lock.shield.fill",
                        title: "Ghost Vault",
                        subtitle: "Sauvegarde chiffrée dans un de tes remotes, scellée par biométrie",
                        tint: .indigo
                    )
                }

                NavigationLink {
                    HandoffLandingView()
                } label: {
                    SettingsNavigationRow(
                        icon: "iphone.and.arrow.forward",
                        title: "Handoff P2P",
                        subtitle: "Transfère une config chiffrée entre appareils via QR ou AirDrop",
                        tint: .purple
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
                    ThumbnailSettingsView()
                } label: {
                    SettingsNavigationRow(
                        icon: "rectangle.grid.3x2",
                        title: "Vignettes",
                        subtitle: "Galerie : politique de génération et cache",
                        tint: .teal
                    )
                }

                NavigationLink {
                    BackupSettingsView()
                } label: {
                    SettingsNavigationRow(
                        icon: "icloud.slash",
                        title: "Sauvegarde iCloud",
                        subtitle: "Exclure les données de l'app de la sauvegarde iCloud",
                        tint: .blue
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
                    GlassEngineView()
                } label: {
                    SettingsNavigationRow(
                        icon: "lock.shield",
                        title: "Transparence",
                        subtitle: "Glass Engine — prouver le « 0 appel maison »",
                        tint: .green
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
                NavigationLink {
                    ChangelogView()
                } label: {
                    SettingsNavigationRow(
                        icon: "clock.arrow.circlepath",
                        title: "Historique des versions",
                        subtitle: "Les nouveautés de chaque mise à jour",
                        tint: .orange
                    )
                }
                NavigationLink {
                    RoadmapView()
                } label: {
                    SettingsNavigationRow(
                        icon: "sparkles",
                        title: "Feuille de route",
                        subtitle: "Les fonctionnalités à venir",
                        tint: .purple
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
            // Pas de chevron : la carte est purement informative. Le chevron
            // historique faisait croire à une navigation (« My iPhone does
            // not open » — retour App Store) alors que rien n'était câblé.
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
    @State private var showOffers = false

    /// True quand l'utilisateur a un vrai abonnement Apple en cours. Pendant
    /// l'essai 7 jours app-managé il n'y a RIEN à « gérer » côté Apple : le
    /// bouton « Gérer mon abonnement » ouvrait une page vide (retour App
    /// Store) — on montre « Voir les offres » à la place.
    private var hasAppleSubscription: Bool {
        subs.snapshot.entitlement == .active
    }

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
                if hasAppleSubscription {
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
                } else {
                    Button {
                        showOffers = true
                    } label: {
                        Text("Voir les offres")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(RG.accentSoft, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                            .foregroundStyle(RG.accent)
                    }
                    .buttonStyle(.plain)
                }

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
        .task { await subs.loadProducts() }
        .sheet(isPresented: $showOffers) {
            PaywallView(isDismissable: true)
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
            // Affiche aussi ce qui suit l'essai : sans ça, l'utilisateur en
            // période d'essai ne voyait nulle part les plans ni les prix.
            let monthly = subs.product(for: SubscriptionProductID.monthly)?.displayPrice ?? "2,99 €"
            let yearly = subs.product(for: SubscriptionProductID.yearly)?.displayPrice ?? "11,99 €"
            if let expiration = subs.snapshot.expirationDate {
                return String(localized: "Fin de l'essai : \(formatter.string(from: expiration)) · ensuite \(monthly)/mois ou \(yearly)/an")
            }
            return String(localized: "7 jours offerts · ensuite \(monthly)/mois ou \(yearly)/an")
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
        case SubscriptionProductID.lifetime:
            return String(localized: "À vie")
        case SubscriptionProductID.monthly:
            // Le prix réel vient de StoreKit (varie par storefront) ; on ne le
            // code pas dans la clé de traduction pour éviter de tout retraduire
            // à chaque changement de prix.
            let price = subs.product(for: SubscriptionProductID.monthly)?.displayPrice ?? "2,99 €"
            return String(localized: "Mensuel — \(price)")
        case SubscriptionProductID.yearly:
            let price = subs.product(for: SubscriptionProductID.yearly)?.displayPrice ?? "11,99 €"
            return String(localized: "Annuel — \(price)")
        default:
            return String(localized: "Premium")
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
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
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
