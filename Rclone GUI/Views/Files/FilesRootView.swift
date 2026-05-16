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

    /// Active transfers — surfaces the "3 transferts en cours" banner from
    /// the design at the top of the remotes dashboard.
    @Query(filter: #Predicate<Transfer> { $0.statusRaw == "running" })
    private var runningTransfers: [Transfer]

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

            if !runningTransfers.isEmpty {
                Section {
                    ActiveTransfersBanner(transfers: runningTransfers)
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))
                        .listRowBackground(Color.clear)
                }
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
            // Les quotas (operations/about) ne sont PLUS chargés au boot —
            // cf. commit précédent : un backend qui ne répond pas pouvait
            // bloquer le pool TCP et freezer toute navigation. Le quota
            // est désormais chargé à la demande quand l'utilisateur ouvre
            // un remote (loadSpaceIfNeeded), avec un timeout 8s qui ne
            // bloque jamais le reste de l'UI.
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    /// Charge le quota d'un remote spécifique en background. Appelé
    /// lazily quand l'utilisateur tap sur un remote — sans bloquer la
    /// navigation. Échec silencieux : on n'affiche juste pas le quota.
    fileprivate func loadSpaceIfNeeded(for remoteName: String) {
        guard remoteSpaces[remoteName] == nil else { return }
        remoteSpaces[remoteName] = "Chargement…"
        Task {
            do {
                let space = try await RemoteService.shared.space(remote: remoteName)
                await MainActor.run {
                    remoteSpaces[remoteName] = Self.spaceLabel(space)
                }
            } catch {
                await MainActor.run {
                    remoteSpaces[remoteName] = "Espace indisponible"
                }
            }
        }
    }

    private func loadRemoteSpaces(for remotes: [RemoteSummaryDTO]) async {
        // Test isolement : on enchaîne les abouts STRICTEMENT
        // séquentiellement avec timeout 10s chacun et logs explicites
        // de start/done/timeout. But : identifier précisément quel
        // backend pend, vs si c'est librclone qui sérialise tout.
        let pending = remotes.filter { remoteSpaces[$0.name] == nil }
        for remote in pending {
            await LogService.shared.log(
                .info,
                category: "about",
                message: "[seq] start remote=\(remote.name)"
            )
            let started = Date()
            do {
                let space = try await Self.withTimeout(seconds: 10) {
                    try await RemoteService.shared.space(remote: remote.name)
                }
                let ms = Int(Date().timeIntervalSince(started) * 1000)
                await LogService.shared.log(
                    .info,
                    category: "about",
                    message: "[seq] done remote=\(remote.name) in \(ms)ms"
                )
                await MainActor.run {
                    remoteSpaces[remote.name] = Self.spaceLabel(space)
                }
            } catch is TimeoutError {
                let ms = Int(Date().timeIntervalSince(started) * 1000)
                await LogService.shared.log(
                    .error,
                    category: "about",
                    message: "[seq] TIMEOUT remote=\(remote.name) after \(ms)ms — passage au suivant"
                )
                await MainActor.run {
                    remoteSpaces[remote.name] = "Espace indisponible (timeout)"
                }
            } catch {
                let ms = Int(Date().timeIntervalSince(started) * 1000)
                await LogService.shared.log(
                    .error,
                    category: "about",
                    message: "[seq] FAIL remote=\(remote.name) in \(ms)ms : \(error.localizedDescription)"
                )
                await MainActor.run {
                    remoteSpaces[remote.name] = "Espace indisponible"
                }
            }
        }
    }

    private struct TimeoutError: Error {}

    /// Exécute `body` avec une limite de temps. Si le timeout expire,
    /// annule la tâche et throw TimeoutError. Note : le RPC sous-jacent
    /// continue côté Go le temps que le moteur le laisse tomber, mais
    /// côté Swift on libère immédiatement l'appelant.
    private static func withTimeout<T: Sendable>(
        seconds: TimeInterval,
        _ body: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await body() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw TimeoutError()
            }
            let first = try await group.next()!
            group.cancelAll()
            return first
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

    fileprivate static func spaceLabel(_ space: RemoteSpaceDTO) -> String {
        guard let used = space.used else {
            if let free = space.free {
                return "\(Self.formattedBytes(free)) libres"
            }
            return "Espace indisponible"
        }
        if let total = space.total {
            return "\(Self.formattedBytes(used)) / \(Self.formattedBytes(total))"
        }
        return "\(Self.formattedBytes(used)) utilisés"
    }

    fileprivate static func formattedBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func formattedBytes(_ bytes: Int64) -> String { Self.formattedBytes(bytes) }

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
            BackendChip(
                backend: RGBackend.from(rcloneType: remote.type),
                cryptOverlay: remote.isCrypt && remote.type != "crypt",
                size: 36
            )
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(remote.name)
                        .font(.system(size: 16, weight: .medium))
                        .lineLimit(1)
                    if remote.type == "crypt" {
                        CryptBadge()
                    }
                }
                Text(spaceText ?? humanType)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if spaceText == nil {
                ProgressView()
                    .controlSize(.small)
            } else {
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
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

/// Inline banner above the remotes list — surfaces the global progress
/// of currently-running transfers, mirroring the design's "3 transferts
/// en cours · 12.4 MB/s · ~1m45" card.
private struct ActiveTransfersBanner: View {
    let transfers: [Transfer]

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(RG.accentSoft)
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(RG.accent)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 5) {
                Text(headlineText)
                    .font(.system(size: 14, weight: .semibold))
                ProgressView(value: progress)
                    .tint(RG.accent)
                    .frame(height: 3)
                Text(subtitleText)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.rgGroupedRowBackground,
                    in: RoundedRectangle(cornerRadius: RG.Radius.group, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var headlineText: String {
        let n = transfers.count
        return n == 1 ? "1 transfert en cours" : "\(n) transferts en cours"
    }

    private var subtitleText: String {
        let totalDone = transfers.reduce(Int64(0)) { $0 + max($1.bytesTransferred, 0) }
        let totalAll = transfers.reduce(Int64(0)) { $0 + max($1.bytesTotal, 0) }
        if totalAll > 0 {
            return "\(formatted(totalDone)) / \(formatted(totalAll))"
        }
        return "Préparation…"
    }

    private var progress: Double {
        let totalDone = transfers.reduce(Int64(0)) { $0 + max($1.bytesTransferred, 0) }
        let totalAll = transfers.reduce(Int64(0)) { $0 + max($1.bytesTotal, 0) }
        guard totalAll > 0 else { return 0 }
        return Double(totalDone) / Double(totalAll)
    }

    private func formatted(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
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
