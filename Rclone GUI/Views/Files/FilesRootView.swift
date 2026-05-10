//
//  FilesRootView.swift
//  Rclone GUI — Views/Files
//
//  Root file-manager surface. Remotes, pinned folders, and recents live here.
//

import SwiftData
import SwiftUI

struct FilesRootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    @Query(sort: \SavedLocation.lastOpenedAt, order: .reverse)
    private var savedLocations: [SavedLocation]

    @State private var remotes: [RemoteSummaryDTO] = []
    @State private var remoteSpaces: [String: String] = [:]
    @State private var loadState: LoadState = .idle
    @State private var isMockEngine = false
    @State private var showImport = false
    @State private var showAddRemote = false

    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

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
            .prefix(5)
            .map { $0 }
    }

    var body: some View {
        content
            .navigationTitle("Fichiers")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        showAddRemote = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Ajouter un remote")

                    Button {
                        Task { await load(force: true) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Rafraîchir les fichiers")
                }
            }
            .task {
                if remotes.isEmpty { await load() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .rcloneConfigurationDidChange)) { _ in
                Task { await load(force: true) }
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                Task { await refreshIfNeeded() }
            }
            .refreshable { await load(force: true) }
            .sheet(isPresented: $showImport) {
                ImportConfigView(onImported: {
                    showImport = false
                    Task { await load(force: true) }
                })
            }
            .sheet(isPresented: $showAddRemote) {
                AddRemoteWizard(onSaved: {
                    showAddRemote = false
                    Task { await load(force: true) }
                })
            }
    }

    @ViewBuilder
    private var content: some View {
        switch loadState {
        case .idle:
            loadingList

        case .loading where remotes.isEmpty:
            loadingList

        case .failed(let message):
            ContentUnavailableView {
                Label("Erreur de chargement", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Réessayer") { Task { await load(force: true) } }
                    .buttonStyle(.borderedProminent)
            }

        case .loaded where remotes.isEmpty:
            VStack(spacing: 16) {
                AppEmptyStateView(
                    title: "Aucune configuration",
                    message: "Importe ton rclone.conf pour afficher tes remotes et parcourir tes fichiers.",
                    systemImage: "externaldrive.badge.plus",
                    tint: .blue
                )
                Button {
                    showImport = true
                } label: {
                    Label("Importer rclone.conf", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button {
                    showAddRemote = true
                } label: {
                    Label("Ajouter un remote", systemImage: "externaldrive.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            .padding()

        case .loading, .loaded:
            filesList
        }
    }

    private var loadingList: some View {
            List {
                Section {
                    FileManagerOverviewCard(remoteCount: max(remotes.count, 0), cryptCount: 0)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowBackground(Color.clear)
                }
                Section {
                    SkeletonLoaderView(rowCount: 6, style: .fileRow)
                        .listRowInsets(EdgeInsets())
                }
            }
            .listStyle(.insetGrouped)
    }

    private var filesList: some View {
        List {
            Section {
                FileManagerOverviewCard(
                    remoteCount: remotes.count,
                    cryptCount: remotes.filter(\.isCrypt).count
                )
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
            }

            if isMockEngine {
                Section {
                    AppInlineMessage(
                        title: "Mode mock actif",
                        message: "La navigation et les transferts réels nécessitent RcloneKit.",
                        systemImage: "exclamationmark.triangle.fill",
                        tint: .orange
                    )
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
                }
            }

            if !pinnedLocations.isEmpty {
                Section {
                    ForEach(pinnedLocations.prefix(8)) { location in
                        NavigationLink(value: location.destination) {
                            AppLocationRow(
                                title: location.displayName,
                                subtitle: location.subtitle,
                                systemImage: "pin.fill",
                                tint: .orange
                            )
                        }
                    }
                } header: {
                    AppSectionHeader(title: "Favoris", subtitle: "Dossiers épinglés", systemImage: "pin.fill")
                }
            }

            if !recentLocations.isEmpty {
                Section {
                    ForEach(recentLocations) { location in
                        NavigationLink(value: location.destination) {
                            AppLocationRow(
                                title: location.displayName,
                                subtitle: location.subtitle,
                                systemImage: location.path.isEmpty ? "externaldrive.fill" : "folder.fill",
                                tint: .blue,
                                trailing: relativeDate(location.lastOpenedAt)
                            )
                        }
                    }
                } header: {
                    AppSectionHeader(title: "Récents", subtitle: "Dernières ouvertures", systemImage: "clock")
                }
            }

            Section {
                ForEach(remotes) { remote in
                    NavigationLink(value: NavigationDestination.folder(remote: remote.name, path: "")) {
                        FilesRemoteRow(remote: remote, spaceText: remoteSpaces[remote.name])
                    }
                    .contextMenu {
                        Button {
                            Task { await pin(remote: remote) }
                        } label: {
                            Label("Épingler", systemImage: "pin")
                        }
                    }
                }
            } header: {
                AppSectionHeader(title: "Remotes", subtitle: "Racines disponibles", systemImage: "externaldrive")
            } footer: {
                Text("Touche un remote pour ouvrir sa racine. Les favoris et récents restent locaux à cet appareil.")
            }
        }
        .listStyle(.insetGrouped)
    }

    private func refreshIfNeeded() async {
        let hasConfig = await ConfigStore.shared.hasStoredConf()
        guard hasConfig else { return }
        if remotes.isEmpty || loadState != .loaded {
            await load(force: true)
        }
    }

    private func load(force: Bool = false) async {
        if !force, loadState == .loading {
            return
        }

        loadState = .loading
        isMockEngine = await RcloneCore.shared.isMockEngine

        guard await ConfigStore.shared.hasStoredConf() else {
            remotes = []
            remoteSpaces = [:]
            loadState = .loaded
            return
        }

        do {
            remotes = try await RemoteService.shared.listRemoteSummaries()
            try? SavedLocationStore.removeUnavailableRemotes(Set(remotes.map(\.name)), in: modelContext)
            loadState = .loaded
            await FileProviderManager.shared.writeRemotesManifest(remotes)
            await loadRemoteSpaces(for: remotes)
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    private func loadRemoteSpaces(for remotes: [RemoteSummaryDTO]) async {
        for remote in remotes {
            guard remoteSpaces[remote.name] == nil else { continue }
            do {
                let space = try await RemoteService.shared.space(remote: remote.name)
                await MainActor.run {
                    remoteSpaces[remote.name] = spaceLabel(space)
                }
            } catch {
                await MainActor.run {
                    remoteSpaces[remote.name] = "Espace indisponible"
                }
            }
        }
    }

    private func pin(remote: RemoteSummaryDTO) async {
        do {
            _ = try SavedLocationStore.togglePinned(
                remote: remote.name,
                path: "",
                displayName: remote.name,
                in: modelContext
            )
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    private func spaceLabel(_ space: RemoteSpaceDTO) -> String {
        guard let used = space.used else {
            if let free = space.free {
                return "\(formattedBytes(free)) libres"
            }
            return "Espace indisponible"
        }
        if let total = space.total {
            return "\(formattedBytes(used)) / \(formattedBytes(total))"
        }
        return "\(formattedBytes(used)) utilisés"
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

private struct FileManagerOverviewCard: View {
    let remoteCount: Int
    let cryptCount: Int

    var body: some View {
        AppHeroCard(
            title: "Bibliothèque fichiers",
            subtitle: "\(remoteCount) remote\(remoteCount > 1 ? "s" : "") configuré\(remoteCount > 1 ? "s" : "")",
            systemImage: "folder.fill.badge.gearshape",
            tint: .blue
        ) {
            HStack(spacing: 10) {
                AppMetricPill(value: "\(remoteCount)", label: "remotes", systemImage: "externaldrive", tint: .blue)
                AppMetricPill(value: "\(cryptCount)", label: "crypt", systemImage: "lock.shield", tint: .green)
            }
        }
    }
}

private struct FilesRemoteRow: View {
    let remote: RemoteSummaryDTO
    let spaceText: String?

    var body: some View {
        HStack(spacing: 14) {
            AppIconTile(systemImage: iconName, tint: iconColor, size: 46)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text(remote.name)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                    if remote.isCrypt {
                        AppStatusBadge(title: "Crypt", systemImage: "lock.fill", tint: .green)
                    }
                }
                Text(spaceText ?? humanType)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if spaceText == nil {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    private var iconName: String {
        switch remote.type {
        case "s3": return "externaldrive.fill"
        case "b2": return "externaldrive.fill.badge.checkmark"
        case "sftp", "ftp": return "server.rack"
        case "webdav": return "network"
        case "drive", "onedrive": return "icloud.fill"
        case "dropbox", "box": return "shippingbox.fill"
        case "crypt": return "lock.shield"
        case "alias", "union", "combine": return "link.circle.fill"
        case "local": return "internaldrive.fill"
        default: return "questionmark.circle"
        }
    }

    private var iconColor: Color {
        switch remote.type {
        case "crypt": return .green
        case "s3", "b2": return .orange
        case "sftp", "ftp": return .indigo
        case "webdav": return .teal
        case "drive", "onedrive": return .blue
        case "dropbox", "box": return .cyan
        case "local": return .gray
        default: return .accentColor
        }
    }

    private var humanType: String {
        switch remote.type {
        case "s3": return "S3 / R2 / Bunny / Wasabi"
        case "b2": return "Backblaze B2"
        case "sftp": return "SFTP"
        case "ftp": return "FTP"
        case "webdav": return "WebDAV"
        case "drive": return "Google Drive"
        case "dropbox": return "Dropbox"
        case "onedrive": return "OneDrive"
        case "box": return "Box"
        case "crypt": return "Crypt chiffré"
        case "alias": return "Alias"
        case "union": return "Union de remotes"
        case "combine": return "Combine"
        case "local": return "Local"
        default: return remote.type
        }
    }
}

#Preview {
    NavigationStack {
        FilesRootView()
    }
    .modelContainer(
        for: [Remote.self, RemoteEntry.self, Transfer.self, TransferBatch.self, PhotoSyncAsset.self, TrashEntry.self, SavedLocation.self],
        inMemory: true
    )
}
