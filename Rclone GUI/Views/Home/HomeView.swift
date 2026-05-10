//
//  HomeView.swift
//  Rclone GUI — Views/Home
//
//  Premium command center for the app: health, shortcuts, pinned folders,
//  recents, and current transfer activity.
//

import SwiftData
import SwiftUI

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \SavedLocation.lastOpenedAt, order: .reverse)
    private var savedLocations: [SavedLocation]
    @Query(sort: \Transfer.startedAt, order: .reverse)
    private var transfers: [Transfer]
    @Query(sort: \TrashEntry.trashedAt, order: .reverse)
    private var trashEntries: [TrashEntry]
    @Query(sort: \PhotoSyncAsset.discoveredAt, order: .reverse)
    private var photoAssets: [PhotoSyncAsset]

    @State private var remotes: [RemoteSummaryDTO] = []
    @State private var hasConfig = false
    @State private var isMockEngine = false
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var cacheBytes: Int64 = 0
    @State private var showImport = false
    @State private var showAddRemote = false

    private var pinnedLocations: [SavedLocation] {
        savedLocations
            .filter { $0.kind == .pinned }
            .sorted {
                if $0.sortIndex == $1.sortIndex {
                    return $0.createdAt < $1.createdAt
                }
                return $0.sortIndex < $1.sortIndex
            }
    }

    private var recentLocations: [SavedLocation] {
        savedLocations
            .filter { $0.kind == .recent }
            .prefix(6)
            .map { $0 }
    }

    private var activeTransfers: [Transfer] {
        transfers.filter {
            $0.status == .running || $0.status == .pending || $0.status == .paused || $0.status == .enqueued
        }
    }

    private var failedTransfers: [Transfer] {
        transfers.filter { $0.status == .failed }
    }

    private var completedTransfers: [Transfer] {
        transfers.filter { $0.status == .completed }
    }

    private var photoSyncPendingCount: Int {
        photoAssets.filter { $0.status == .pending || $0.status == .exporting || $0.status == .enqueued }.count
    }

    private var heroTitle: String {
        if !hasConfig { return "Configure Rclone GUI" }
        if isMockEngine { return "Mode démo actif" }
        if !activeTransfers.isEmpty { return "Transferts en cours" }
        return "Tout est prêt"
    }

    private var heroSubtitle: String {
        if !hasConfig {
            return "Importe ton rclone.conf pour parcourir tes remotes, synchroniser tes fichiers et exposer tes dossiers dans Fichiers."
        }
        if isMockEngine {
            return "La configuration est chargée, mais le moteur RcloneKit réel n’est pas disponible dans cette session."
        }
        if !activeTransfers.isEmpty {
            return "\(activeTransfers.count) opération\(activeTransfers.count > 1 ? "s" : "") active\(activeTransfers.count > 1 ? "s" : "") sur tes remotes."
        }
        return "\(remotes.count) remote\(remotes.count > 1 ? "s" : "") disponible\(remotes.count > 1 ? "s" : "")."
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                statusHero
                quickActions
                if !pinnedLocations.isEmpty {
                    locationsSection(
                        title: "Favoris",
                        subtitle: "Tes dossiers épinglés",
                        locations: Array(pinnedLocations.prefix(6)),
                        empty: nil
                    )
                }
                locationsSection(
                    title: "Récents",
                    subtitle: "Derniers dossiers ouverts",
                    locations: recentLocations,
                    empty: AppEmptyStateView(
                        title: "Aucun dossier récent",
                        message: "Ouvre un remote depuis Fichiers pour retrouver tes chemins ici.",
                        systemImage: "clock",
                        tint: .blue
                    )
                )
                activitySection
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Accueil")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await load() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("Rafraîchir l’accueil")
            }
        }
        .refreshable {
            await load()
        }
        .task {
            await load()
        }
        .onReceive(NotificationCenter.default.publisher(for: .rcloneConfigurationDidChange)) { _ in
            Task { await load() }
        }
        .sheet(isPresented: $showImport) {
            ImportConfigView(onImported: {
                showImport = false
                Task { await load() }
            })
        }
        .sheet(isPresented: $showAddRemote) {
            AddRemoteWizard(onSaved: {
                showAddRemote = false
                Task { await load() }
            })
        }
    }

    private var statusHero: some View {
        AppHeroCard(
            title: heroTitle,
            subtitle: heroSubtitle,
            systemImage: hasConfig ? "externaldrive.connected.to.line.below" : "doc.badge.gearshape",
            tint: hasConfig ? .blue : .orange
        ) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 10)], spacing: 10) {
                AppMetricTile(value: "\(remotes.count)", label: "remotes", systemImage: "externaldrive", tint: .blue)
                AppMetricTile(value: "\(activeTransfers.count)", label: "actifs", systemImage: "bolt.fill", tint: .indigo)
                AppMetricTile(value: "\(trashEntries.count)", label: "corbeille", systemImage: "trash", tint: .red)
                AppMetricTile(value: formattedBytes(cacheBytes), label: "cache média", systemImage: "tray.full", tint: .orange)
            }

            if let loadError {
                AppInlineMessage(
                    title: "Lecture partielle",
                    message: loadError,
                    systemImage: "exclamationmark.triangle.fill",
                    tint: .orange
                )
            }
        }
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            AppSectionHeader(title: "Actions rapides", subtitle: "Les chemins les plus courts", systemImage: "sparkles")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 10)], spacing: 10) {
                Button {
                    showAddRemote = true
                } label: {
                    AppActionTile(
                        title: "Nouveau",
                        subtitle: "Ajouter un remote",
                        systemImage: "externaldrive.badge.plus",
                        tint: .blue
                    )
                }
                .buttonStyle(.plain)

                Button {
                    showImport = true
                } label: {
                    AppActionTile(
                        title: "Importer",
                        subtitle: "Charger rclone.conf",
                        systemImage: "square.and.arrow.down",
                        tint: .blue
                    )
                }
                .buttonStyle(.plain)

                if let firstRemoteDestination {
                    NavigationLink(value: firstRemoteDestination) {
                        AppActionTile(
                            title: "Parcourir",
                            subtitle: firstRemoteSubtitle,
                            systemImage: "folder",
                            tint: .green
                        )
                    }
                    .buttonStyle(.plain)
                } else {
                    AppActionTile(
                        title: "Parcourir",
                        subtitle: "Aucun remote",
                        systemImage: "folder",
                        tint: .gray
                    )
                    .opacity(0.55)
                }

                NavigationLink {
                    PhotoSyncSettingsView()
                } label: {
                    AppActionTile(
                        title: "Photos",
                        subtitle: photoSyncPendingCount == 0 ? "Backup configuré" : "\(photoSyncPendingCount) en attente",
                        systemImage: "photo.stack",
                        tint: .pink
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    PerformanceSettingsView()
                } label: {
                    AppActionTile(
                        title: "Performance",
                        subtitle: "Pause et débit",
                        systemImage: "speedometer",
                        tint: .indigo
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func locationsSection(
        title: String,
        subtitle: String,
        locations: [SavedLocation],
        empty: AppEmptyStateView?
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            AppSectionHeader(title: title, subtitle: subtitle, systemImage: title == "Favoris" ? "pin.fill" : "clock")
            if locations.isEmpty {
                if let empty {
                    empty
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(locations) { location in
                        NavigationLink(value: location.destination) {
                            AppLocationRow(
                                title: location.displayName,
                                subtitle: location.subtitle,
                                systemImage: location.path.isEmpty ? "externaldrive.fill" : "folder.fill",
                                tint: location.kind == .pinned ? .orange : .blue,
                                trailing: location.kind == .recent ? relativeDate(location.lastOpenedAt) : nil
                            )
                        }
                        .buttonStyle(.plain)
                        if location.id != locations.last?.id {
                            Divider()
                                .padding(.leading, 52)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .appGlassSurface(cornerRadius: AppSurface.cornerRadius)
            }
        }
    }

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            AppSectionHeader(title: "Activité", subtitle: "Transferts et hygiène locale", systemImage: "waveform.path.ecg")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 10)], spacing: 10) {
                AppMetricTile(value: "\(completedTransfers.count)", label: "terminés", systemImage: "checkmark.circle", tint: .green)
                AppMetricTile(value: "\(failedTransfers.count)", label: "échecs", systemImage: "exclamationmark.triangle", tint: .red)
                AppMetricTile(value: "\(photoAssets.count)", label: "photos indexées", systemImage: "photo.on.rectangle", tint: .pink)
            }

            if activeTransfers.isEmpty {
                AppInlineMessage(
                    title: "File calme",
                    message: "Les prochains uploads, téléchargements ou syncs apparaîtront ici.",
                    systemImage: "checkmark.circle.fill",
                    tint: .green
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(activeTransfers.prefix(3)) { transfer in
                        TransferRowView(transfer: transfer)
                        if transfer.id != activeTransfers.prefix(3).last?.id {
                            Divider()
                                .padding(.leading, 58)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .appGlassSurface(cornerRadius: AppSurface.cornerRadius)
            }
        }
    }

    private var firstRemoteDestination: NavigationDestination? {
        remotes.first.map { .folder(remote: $0.name, path: "") }
    }

    private var firstRemoteSubtitle: String {
        remotes.first.map { "\($0.name):/" } ?? "Aucun remote"
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        hasConfig = await ConfigStore.shared.hasStoredConf()
        isMockEngine = await RcloneCore.shared.isMockEngine
        cacheBytes = (try? await MediaCacheService.shared.currentSize()) ?? 0

        guard hasConfig else {
            remotes = []
            loadError = nil
            return
        }

        do {
            remotes = try await RemoteService.shared.listRemoteSummaries()
            try? SavedLocationStore.removeUnavailableRemotes(Set(remotes.map(\.name)), in: modelContext)
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func formattedBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        formatter.dateTimeStyle = .named
        return formatter.localizedString(for: date, relativeTo: .now)
    }
}

#Preview {
    NavigationStack {
        HomeView()
    }
    .modelContainer(
        for: [Remote.self, RemoteEntry.self, Transfer.self, TransferBatch.self, PhotoSyncAsset.self, TrashEntry.self, SavedLocation.self],
        inMemory: true
    )
}
