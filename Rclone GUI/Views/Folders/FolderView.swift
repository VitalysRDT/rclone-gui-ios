//
//  FolderView.swift
//  Rclone GUI — Views/Folders
//
//  Lists files and sub-folders under <remote>:<path>.
//  Phase B scope: read-only navigation + sort + filter (search).
//  Phase C will add: download, upload, move, rename, delete.
//

import SwiftData
import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct FolderView: View {
    @Environment(\.modelContext) private var modelContext

    let remote: String
    let path: String

    @State private var entries: [RemoteEntryDTO] = []
    @State private var loadState: LoadState = .idle
    @State private var sortMode: SortMode = .name
    @State private var sortDescending = false
    @State private var query = ""
    @State private var renameTarget: RemoteEntryDTO?
    @State private var deleteTarget: RemoteEntryDTO?
    @State private var playTarget: RemoteEntryDTO?
    @State private var previewTarget: RemoteEntryDTO?
    @State private var externalOpenTarget: RemoteEntryDTO?
    @State private var moveTarget: RemoteEntryDTO?
    @State private var downloadTarget: RemoteEntryDTO?
    @State private var remoteTransferRequest: RemoteBatchTransferRequest?
    @State private var availableRemotes: [String] = []
    @State private var deleteIsRecursive = false
    @State private var selectionMode = false
    @State private var selectedEntryIDs: Set<String> = []
    @State private var pendingDownloadEntries: [RemoteEntryDTO] = []
    @State private var showingDestinationPicker = false
    @State private var showingFileImporter = false
    @State private var showingPhotoPicker = false
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var transientMessage: String?
    @State private var openingEntryID: String?
    @State private var currentFolderIsPinned = false
    /// Whether the remote at the top of the navigation stack is a `crypt`
    /// remote — drives the small purple lock indicator on each row.
    @State private var currentRemoteIsCrypt = false

    // Conflict resolution for paste — surfaced when FilesClipboardError.destinationConflict
    // is thrown by the pre-flight stat check. Holds the list of conflicting
    // basenames so the dialog can list them, plus a flag to retry with force.
    @State private var pasteConflictNames: [String]?

    // Haptic triggers — bumped each time an action of the matching kind fires.
    // We use Int counters because SwiftUI's .sensoryFeedback(_:trigger:) needs
    // an Equatable trigger that *changes* to fire; toggling Bool would clamp
    // back-to-back actions.
    @State private var hapticSuccessTrigger = 0
    @State private var hapticWarningTrigger = 0
    @State private var hapticImpactTrigger = 0

    /// All transfers currently running. SwiftData refreshes this view
    /// whenever a status flips, so the inline row progress is live without
    /// a manual timer.
    @Query(filter: #Predicate<Transfer> { $0.statusRaw == "running" })
    private var runningTransfers: [Transfer]

    /// Map of "<remote>:<path>" → Transfer pour lookup O(1) par row.
    /// Mémoisée en @State : sans ça, le dict était recalculé à chaque
    /// re-render du body (plusieurs fois par seconde pendant un transfert)
    /// alors qu'il ne change que quand `runningTransfers` muet. Mise à jour
    /// via .onChange(of: runningTransfers).
    @State private var activeTransferByPath: [String: Transfer] = [:]

    private func computeActiveTransferByPath() -> [String: Transfer] {
        var dict: [String: Transfer] = [:]
        for t in runningTransfers {
            // Match download (sourceRemote:sourcePath), upload (destinationRemote:destinationPath),
            // delete/rename/move (sourceRemote:sourcePath).
            if let r = t.sourceRemote, r == remote, !t.sourcePath.isEmpty {
                dict[t.sourcePath] = t
            }
            if let r = t.destinationRemote, r == remote, !t.destinationPath.isEmpty {
                dict[t.destinationPath] = t
            }
        }
        return dict
    }

    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    enum SortMode: String, CaseIterable, Identifiable, Sendable {
        case name, size, date, type
        public var id: String { rawValue }
        var label: String {
            switch self {
            case .name: return "Nom"
            case .size: return "Taille"
            case .date: return "Date"
            case .type: return "Type"
            }
        }
    }

    private var displayedEntries: [RemoteEntryDTO] {
        let filtered: [RemoteEntryDTO]
        if query.isEmpty {
            filtered = entries
        } else {
            filtered = entries.filter {
                $0.name.localizedCaseInsensitiveContains(query)
            }
        }

        // Always show directories before files, then sort within each group.
        let dirs = filtered.filter { $0.isDirectory }
        let files = filtered.filter { !$0.isDirectory }
        return sort(dirs) + sort(files)
    }

    private var folderCount: Int {
        entries.filter { $0.isDirectory }.count
    }

    private var fileCount: Int {
        entries.count - folderCount
    }

    private var displayedSectionTitle: String {
        if query.isEmpty {
            return "\(displayedEntries.count) élément\(displayedEntries.count > 1 ? "s" : "")"
        }
        return "\(displayedEntries.count) résultat\(displayedEntries.count > 1 ? "s" : "")"
    }

    private var selectedEntries: [RemoteEntryDTO] {
        displayedRows
            .filter { selectedEntryIDs.contains($0.id) }
            .map(\.entry)
    }

    private var displayedRows: [DisplayedEntry] {
        var countsByID: [String: Int] = [:]
        return displayedEntries.enumerated().map { offset, entry in
            let baseID = entry.id
            let duplicateIndex = countsByID[baseID, default: 0]
            countsByID[baseID] = duplicateIndex + 1
            let rowID = duplicateIndex == 0 ? baseID : "\(baseID)#duplicate-\(duplicateIndex)-\(offset)"
            return DisplayedEntry(id: rowID, entry: entry)
        }
    }

    private func sort(_ entries: [RemoteEntryDTO]) -> [RemoteEntryDTO] {
        let asc = !sortDescending
        return entries.sorted { a, b in
            switch sortMode {
            case .name:
                return asc
                    ? a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
                    : a.name.localizedCaseInsensitiveCompare(b.name) == .orderedDescending
            case .size:
                return asc ? a.size < b.size : a.size > b.size
            case .date:
                return asc ? a.modTime < b.modTime : a.modTime > b.modTime
            case .type:
                let extA = (a.name as NSString).pathExtension
                let extB = (b.name as NSString).pathExtension
                let cmp = extA.localizedCaseInsensitiveCompare(extB)
                return asc ? cmp == .orderedAscending : cmp == .orderedDescending
            }
        }
    }

    var body: some View {
        let main = content
            .navigationTitle(displayTitle)
            .searchable(text: $query)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !displayedEntries.isEmpty {
                        Button(selectionMode ? "OK" : "Sélectionner") {
                            selectionMode.toggle()
                            if !selectionMode { selectedEntryIDs.removeAll() }
                            hapticImpactTrigger &+= 1
                        }
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await togglePinCurrentFolder() }
                    } label: {
                        Image(systemName: currentFolderIsPinned ? "pin.fill" : "pin")
                    }
                    .accessibilityLabel(currentFolderIsPinned ? "Retirer ce dossier des favoris" : "Épingler ce dossier")
                }
                ToolbarItem(placement: .primaryAction) {
                    actionsMenu
                }
            }
            .task(id: TaskKey(remote: remote, path: path)) {
                await load()
                activeTransferByPath = computeActiveTransferByPath()
            }
            .refreshable {
                await load()
            }
            .safeAreaInset(edge: .bottom) {
                if selectionMode {
                    selectionActionBar
                }
            }
            // Recompute le mapping path → Transfer uniquement quand
            // l'ensemble des running transfers change réellement (arrival,
            // departure). Sans ça, le dict était reconstruit à chaque
            // re-render du body — coûteux pour de gros dossiers.
            .onChange(of: runningTransfers.count) { _, _ in
                activeTransferByPath = computeActiveTransferByPath()
            }
            .sheet(item: $renameTarget) { entry in
                RenameSheetView(
                    entry: entry,
                    remote: remote,
                    isPresented: Binding(
                        get: { renameTarget != nil },
                        set: { if !$0 { renameTarget = nil } }
                    )
                )
                .onDisappear { Task { await load() } }
            }
            .fullScreenCover(item: $playTarget, onDismiss: {
                openingEntryID = nil
            }) { entry in
                MediaPlayerHost(remote: remote, entry: entry)
            }
            .sheet(item: $previewTarget, onDismiss: {
                openingEntryID = nil
            }) { entry in
                RemotePreviewHost(remote: remote, entry: entry)
            }
            .sheet(item: $externalOpenTarget, onDismiss: {
                openingEntryID = nil
            }) { entry in
                RemoteExternalOpenHost(remote: remote, entry: entry)
            }
            .sheet(item: $moveTarget) { entry in
                MoveSheetView(
                    entry: entry,
                    sourceRemote: remote,
                    availableRemotes: availableRemotes.isEmpty ? [remote] : availableRemotes,
                    isPresented: Binding(
                        get: { moveTarget != nil },
                        set: { if !$0 { moveTarget = nil } }
                    )
                )
                .onDisappear { Task { await load() } }
            }
            .sheet(item: $remoteTransferRequest) { request in
                RemoteBatchTransferSheet(
                    sourceRemote: remote,
                    sourcePath: path,
                    entries: request.entries,
                    initialKind: request.kind,
                    availableRemotes: availableRemotes.isEmpty ? [remote] : availableRemotes,
                    isPresented: Binding(
                        get: { remoteTransferRequest != nil },
                        set: { if !$0 { remoteTransferRequest = nil } }
                    )
                )
                .onDisappear { Task { await load() } }
            }
            .sheet(isPresented: $showingDestinationPicker) {
                LocalDirectoryPicker(
                    onPicked: { url in
                        let _ = url.startAccessingSecurityScopedResource()
                        showingDestinationPicker = false
                        let entries = pendingDownloadEntries
                        pendingDownloadEntries = []
                        Task { await download(entries, to: url) }
                    },
                    onCancelled: {
                        showingDestinationPicker = false
                        pendingDownloadEntries = []
                    }
                )
            }
            .fileImporter(
                isPresented: $showingFileImporter,
                allowedContentTypes: [.item, .folder],
                allowsMultipleSelection: true
            ) { result in
                Task { await handleFileImport(result) }
            }
            .photosPicker(
                isPresented: $showingPhotoPicker,
                selection: $selectedPhotoItems,
                matching: .any(of: [.images, .videos])
            )
            .onChange(of: selectedPhotoItems) { _, items in
                guard !items.isEmpty else { return }
                Task { await uploadPhotos(items) }
            }
            .onChange(of: downloadTarget) { _, entry in
                guard let entry else { return }
                pendingDownloadEntries = [entry]
                downloadTarget = nil
                showingDestinationPicker = true
            }
            .confirmationDialog(
                deleteDialogTitle,
                isPresented: Binding(
                    get: { deleteTarget != nil },
                    set: { if !$0 { deleteTarget = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Mettre à la corbeille") {
                    Task { await performDelete(permanent: false) }
                }
                Button("Supprimer définitivement", role: .destructive) {
                    Task { await performDelete(permanent: true) }
                }
                Button("Annuler", role: .cancel) { deleteTarget = nil }
            } message: {
                if let target = deleteTarget {
                    Text(target.isDirectory
                         ? "Le dossier et tout son contenu peuvent être restaurés depuis la corbeille pendant 30 jours, ou supprimés définitivement."
                         : "Le fichier peut être restauré depuis la corbeille pendant 30 jours, ou supprimé définitivement.")
                }
            }
            .alert("Info", isPresented: Binding(
                get: { transientMessage != nil },
                set: { if !$0 { transientMessage = nil } }
            )) {
                Button("OK", role: .cancel) { transientMessage = nil }
            } message: {
                Text(transientMessage ?? "")
            }
            .confirmationDialog(
                pasteConflictTitle,
                isPresented: Binding(
                    get: { pasteConflictNames != nil },
                    set: { if !$0 { pasteConflictNames = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Remplacer", role: .destructive) {
                    pasteConflictNames = nil
                    Task { await pasteFromClipboard(force: true) }
                }
                Button("Annuler", role: .cancel) { pasteConflictNames = nil }
            } message: {
                Text(pasteConflictMessage)
            }
            .sensoryFeedback(.success, trigger: hapticSuccessTrigger)
            .sensoryFeedback(.warning, trigger: hapticWarningTrigger)
            .sensoryFeedback(.selection, trigger: hapticImpactTrigger)

        #if os(iOS)
        main.navigationBarTitleDisplayMode(.inline)
        #else
        main
        #endif
    }

    private var deleteDialogTitle: String {
        deleteTarget.map { "Supprimer « \($0.name) » ?" } ?? "Supprimer ?"
    }

    private func performDelete(permanent: Bool) async {
        guard let target = deleteTarget else { return }
        deleteTarget = nil
        do {
            if permanent {
                try await TransferQueue.shared.enqueueDelete(
                    remote: remote,
                    path: target.pathInRemote,
                    isDirectory: target.isDirectory
                )
                hapticWarningTrigger &+= 1
            } else {
                try await TransferQueue.shared.enqueueTrash(
                    remote: remote,
                    path: target.pathInRemote,
                    name: target.name,
                    isDirectory: target.isDirectory,
                    sizeBytes: target.size
                )
                transientMessage = "« \(target.name) » est dans la corbeille (30 jours)."
                hapticSuccessTrigger &+= 1
            }
            await load()
        } catch {
            let action = permanent ? "suppression" : "mise à la corbeille"
            await LogService.shared.log(
                .error,
                category: "transfer",
                message: "Échec \(action) \(remote):\(target.pathInRemote) : \(error.localizedDescription)"
            )
            loadState = .failed("Échec de la \(action) : \(error.localizedDescription)")
        }
    }

    private struct TaskKey: Hashable, Sendable {
        let remote: String
        let path: String
    }

    @ViewBuilder
    private var content: some View {
        switch loadState {
        case .idle:
            SkeletonLoaderView(rowCount: 6, style: .fileRow)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        case .loading where entries.isEmpty:
            SkeletonLoaderView(rowCount: 6, style: .fileRow)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

        case .failed(let msg):
            ContentUnavailableView {
                Label("Erreur", systemImage: "exclamationmark.triangle")
            } description: {
                Text(msg)
            } actions: {
                Button("Réessayer") {
                    Task { await load() }
                }
                .buttonStyle(.borderedProminent)
            }

        case .loaded where entries.isEmpty:
            ContentUnavailableView(
                "Dossier vide",
                systemImage: "folder",
                description: Text("Aucun fichier ni sous-dossier trouvé.")
            )

        case .loaded where displayedEntries.isEmpty:
            ContentUnavailableView.search(text: query)

        case .loading, .loaded:
            let list = List {
                Section {
                    FolderOverviewCard(
                        remote: remote,
                        path: path,
                        folderCount: folderCount,
                        fileCount: fileCount
                    )
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
                }

                Section {
                    ForEach(displayedRows) { row in
                        rowView(for: row)
                    }
                } header: {
                    Text(displayedSectionTitle)
                }
            }
            #if os(iOS)
            list.listStyle(.insetGrouped)
            #else
            list
            #endif
        }
    }

    @ViewBuilder
    private func rowView(for row: DisplayedEntry) -> some View {
        let entry = row.entry
        let activeTransfer = activeTransferByPath[entry.pathInRemote]
        let isCutStaged = FilesClipboard.shared.isStagedCut(remote: remote, path: entry.pathInRemote)

        rowViewBase(row: row, entry: entry, activeTransfer: activeTransfer)
            .opacity(isCutStaged ? 0.45 : 1)
            .accessibilityHint(isCutStaged ? "Coupé, en attente de collage dans un autre dossier" : "")
    }

    @ViewBuilder
    private func rowViewBase(row: DisplayedEntry, entry: RemoteEntryDTO, activeTransfer: Transfer?) -> some View {
        if entry.isDirectory {
            if selectionMode {
                selectableRow(row: row, activeTransfer: activeTransfer)
            } else {
                NavigationLink(value: NavigationDestination.folder(
                    remote: remote,
                    path: entry.pathInRemote
                )) {
                    EntryRowView(entry: entry, activeTransfer: activeTransfer, isInsideCrypt: currentRemoteIsCrypt)
                }
                .contextMenu {
                    Button {
                        Task { await togglePin(entry) }
                    } label: {
                        Label("Épingler", systemImage: "pin")
                    }
                    Divider()
                    EntryActionsMenu(
                        entry: entry,
                        remote: remote,
                        renameTarget: $renameTarget,
                        deleteTarget: $deleteTarget,
                        playTarget: $playTarget,
                        previewTarget: $previewTarget,
                        moveTarget: $moveTarget,
                        downloadTarget: $downloadTarget,
                        externalOpenTarget: $externalOpenTarget
                    )
                }
            }
        } else {
            // Single-tap action: media → play, anything else → enqueue
            // download. Long-press still surfaces the full action menu.
            Button {
                selectionMode ? toggleSelection(row) : handleTap(on: row)
            } label: {
                if selectionMode {
                    HStack(spacing: 10) {
                        selectionIcon(for: row)
                        EntryRowView(entry: entry, activeTransfer: activeTransfer, isInsideCrypt: currentRemoteIsCrypt)
                    }
                    .contentShape(Rectangle())
                } else {
                    HStack(spacing: 0) {
                        EntryRowView(entry: entry, activeTransfer: activeTransfer, isInsideCrypt: currentRemoteIsCrypt)
                    }
                    .contentShape(Rectangle())
                }
            }
            .buttonStyle(.plain)
            .disabled(openingEntryID != nil && openingEntryID != row.id)
            .contextMenu {
                EntryActionsMenu(
                    entry: entry,
                    remote: remote,
                    renameTarget: $renameTarget,
                    deleteTarget: $deleteTarget,
                    playTarget: $playTarget,
                    previewTarget: $previewTarget,
                    moveTarget: $moveTarget,
                    downloadTarget: $downloadTarget,
                    externalOpenTarget: $externalOpenTarget
                )
            }
        }
    }

    private func handleTap(on row: DisplayedEntry) {
        guard openingEntryID == nil else { return }
        openingEntryID = row.id
        playTarget = nil
        previewTarget = nil
        externalOpenTarget = nil

        let entry = row.entry
        if EntryActionsMenu.isMediaFile(entry.name) {
            playTarget = entry
        } else {
            previewTarget = entry
        }
    }

    @ViewBuilder
    private func selectableRow(row: DisplayedEntry, activeTransfer: Transfer?) -> some View {
        let entry = row.entry
        Button {
            toggleSelection(row)
        } label: {
            HStack(spacing: 10) {
                selectionIcon(for: row)
                EntryRowView(entry: entry, activeTransfer: activeTransfer, isInsideCrypt: currentRemoteIsCrypt)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func selectionIcon(for row: DisplayedEntry) -> some View {
        Image(systemName: selectedEntryIDs.contains(row.id) ? "checkmark.circle.fill" : "circle")
            .font(.title3)
            .foregroundStyle(selectedEntryIDs.contains(row.id) ? .blue : .secondary)
            .accessibilityHidden(true)
    }

    private func toggleSelection(_ row: DisplayedEntry) {
        if selectedEntryIDs.contains(row.id) {
            selectedEntryIDs.remove(row.id)
        } else {
            selectedEntryIDs.insert(row.id)
        }
        hapticImpactTrigger &+= 1
    }

    private var selectionActionBar: some View {
        AppFloatingActionBar {
            Button {
                downloadSelected()
            } label: {
                Label("Télécharger", systemImage: "arrow.down.circle")
            }
            .disabled(selectedEntryIDs.isEmpty)

            Button {
                stageSelected(.copy)
            } label: {
                Label("Copier", systemImage: "doc.on.doc")
            }
            .disabled(selectedEntryIDs.isEmpty)

            Button {
                remoteTransferRequest = RemoteBatchTransferRequest(kind: .move, entries: selectedEntries)
            } label: {
                Label("Déplacer", systemImage: "arrow.left.arrow.right")
            }
            .disabled(selectedEntryIDs.isEmpty)

            Button(role: .destructive) {
                Task { await deleteSelected(permanent: false) }
            } label: {
                Label("Corbeille", systemImage: "trash")
            }
            .disabled(selectedEntryIDs.isEmpty)
        }
        .labelStyle(.iconOnly)
        .font(.headline)
    }

    private func downloadSelected() {
        pendingDownloadEntries = selectedEntries
        showingDestinationPicker = !pendingDownloadEntries.isEmpty
    }

    private func stageSelected(_ operation: FilesClipboard.Operation) {
        FilesClipboard.shared.stage(entries: selectedEntries, remote: remote, operation: operation)
        let verb = operation == .copy ? "copié" : "coupé"
        transientMessage = "\(selectedEntries.count) élément(s) \(verb)(s) — colle-les dans un autre dossier."
        selectedEntryIDs.removeAll()
        selectionMode = false
        hapticImpactTrigger &+= 1
    }

    private var sortMenu: some View {
        Menu {
            Picker("Trier par", selection: $sortMode) {
                ForEach(SortMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            Divider()
            Toggle("Ordre décroissant", isOn: $sortDescending)
        } label: {
            Label("Trier", systemImage: sortDescending ? "arrow.down.circle" : "arrow.up.circle")
        }
        .accessibilityLabel("Options de tri")
    }

    private var actionsMenu: some View {
        Menu {
            if selectionMode {
                Button {
                    pendingDownloadEntries = selectedEntries
                    showingDestinationPicker = !pendingDownloadEntries.isEmpty
                } label: {
                    Label("Télécharger la sélection", systemImage: "arrow.down.circle")
                }
                .disabled(selectedEntryIDs.isEmpty)

                Button {
                    FilesClipboard.shared.stage(entries: selectedEntries, remote: remote, operation: .cut)
                    transientMessage = "\(selectedEntries.count) élément(s) coupé(s) — collez-les dans un autre dossier."
                    selectedEntryIDs.removeAll()
                    selectionMode = false
                    hapticImpactTrigger &+= 1
                } label: {
                    Label("Couper la sélection", systemImage: "scissors")
                }
                .disabled(selectedEntryIDs.isEmpty)

                Button {
                    FilesClipboard.shared.stage(entries: selectedEntries, remote: remote, operation: .copy)
                    transientMessage = "\(selectedEntries.count) élément(s) copié(s) — collez-les dans un autre dossier."
                    selectedEntryIDs.removeAll()
                    selectionMode = false
                    hapticImpactTrigger &+= 1
                } label: {
                    Label("Copier la sélection", systemImage: "doc.on.doc")
                }
                .disabled(selectedEntryIDs.isEmpty)

                Button {
                    Task { await deleteSelected(permanent: false) }
                } label: {
                    Label("Mettre la sélection à la corbeille", systemImage: "trash")
                }
                .disabled(selectedEntryIDs.isEmpty)

                Button(role: .destructive) {
                    Task { await deleteSelected(permanent: true) }
                } label: {
                    Label("Supprimer définitivement la sélection", systemImage: "trash.slash")
                }
                .disabled(selectedEntryIDs.isEmpty)

                Divider()

                Button {
                    remoteTransferRequest = RemoteBatchTransferRequest(kind: .copy, entries: selectedEntries)
                } label: {
                    Label("Copier vers… (autre dossier)", systemImage: "square.and.arrow.up.on.square")
                }
                .disabled(selectedEntryIDs.isEmpty)

                Button {
                    remoteTransferRequest = RemoteBatchTransferRequest(kind: .move, entries: selectedEntries)
                } label: {
                    Label("Déplacer vers…", systemImage: "arrow.left.arrow.right")
                }
                .disabled(selectedEntryIDs.isEmpty)

                Button {
                    remoteTransferRequest = RemoteBatchTransferRequest(kind: .sync, entries: selectedEntries)
                } label: {
                    Label("Synchroniser vers…", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(selectedEntryIDs.isEmpty)

                Divider()
            } else if FilesClipboard.shared.canPaste(into: remote, folder: path) {
                Button {
                    Task { await pasteFromClipboard() }
                } label: {
                    Label(pasteMenuLabel, systemImage: "doc.on.clipboard")
                }
                Divider()
            }

            Button {
                showingFileImporter = true
            } label: {
                Label("Uploader fichiers ou dossiers", systemImage: "arrow.up.doc")
            }

            Button {
                showingPhotoPicker = true
            } label: {
                Label("Uploader depuis Photos", systemImage: "photo.on.rectangle")
            }

            Divider()
            sortMenu
        } label: {
            Label("Actions", systemImage: "ellipsis.circle")
        }
        .accessibilityLabel("Actions du dossier")
    }

    private var displayTitle: String {
        if path.isEmpty { return remote }
        return (path as NSString).lastPathComponent
    }

    private func load() async {
        loadState = .loading
        do {
            entries = try await RemoteService.shared.list(remote: remote, path: path)
            loadState = .loaded
            try? SavedLocationStore.recordOpen(
                remote: remote,
                path: path,
                displayName: displayTitle,
                in: modelContext
            )
            currentFolderIsPinned = (try? SavedLocationStore.isPinned(remote: remote, path: path, in: modelContext)) ?? false
            await FileProviderManager.shared.writeFolderManifest(remote: remote, path: path, entries: entries)
            await LogService.shared.log(
                .debug,
                category: "browse",
                message: "Listé \(entries.count) entrée(s) dans \(remote):\(path)"
            )
            // Refresh the available-remotes list used by MoveSheetView.
            // Best effort; failure here is non-blocking.
            if let names = try? await RemoteService.shared.listRemoteNames() {
                availableRemotes = names
            }
            // Detect whether the remote we're inside is a crypt remote.
            // Drives the small purple lock indicator shown next to each
            // entry name on screen (`crypt-forward` design language).
            if let summaries = try? await RemoteService.shared.listRemoteSummaries(),
               let summary = summaries.first(where: { $0.name == remote }) {
                currentRemoteIsCrypt = (summary.type == "crypt")
            }
        } catch {
            loadState = .failed(error.localizedDescription)
            await LogService.shared.log(
                .error,
                category: "browse",
                message: "Échec list \(remote):\(path) : \(error.localizedDescription)"
            )
        }
    }

    private func togglePinCurrentFolder() async {
        await togglePin(remote: remote, path: path, displayName: displayTitle)
        currentFolderIsPinned = (try? SavedLocationStore.isPinned(remote: remote, path: path, in: modelContext)) ?? false
    }

    private func togglePin(_ entry: RemoteEntryDTO) async {
        guard entry.isDirectory else { return }
        await togglePin(remote: remote, path: entry.pathInRemote, displayName: entry.name)
    }

    private func togglePin(remote: String, path: String, displayName: String) async {
        do {
            let isPinned = try SavedLocationStore.togglePinned(
                remote: remote,
                path: path,
                displayName: displayName,
                in: modelContext
            )
            transientMessage = isPinned ? "Ajouté aux favoris." : "Retiré des favoris."
            hapticSuccessTrigger &+= 1
        } catch {
            transientMessage = "Favori impossible : \(error.localizedDescription)"
            hapticWarningTrigger &+= 1
        }
    }

    private func download(_ entries: [RemoteEntryDTO], to directory: URL) async {
        guard !entries.isEmpty else { return }
        do {
            try await TransferQueue.shared.enqueueDownloadBatch(
                remote: remote,
                entries: entries,
                to: directory,
                conflictPolicy: .keepBoth
            )
            transientMessage = "Téléchargement ajouté à la file."
            selectedEntryIDs.removeAll()
            selectionMode = false
        } catch {
            transientMessage = "Échec de téléchargement : \(error.localizedDescription)"
            await LogService.shared.log(.error, category: "transfer", message: "Download batch impossible : \(error.localizedDescription)")
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) async {
        do {
            let urls = try result.get()
            let staged = try stageForUpload(urls)
            try await TransferQueue.shared.enqueueUploadBatch(
                localURLs: staged,
                remote: remote,
                destinationFolder: path,
                sourceKind: .fileProvider
            )
            transientMessage = "Upload ajouté à la file."
        } catch {
            transientMessage = "Échec upload : \(error.localizedDescription)"
        }
    }

    private func stageForUpload(_ urls: [URL]) throws -> [URL] {
        let root = try FileManager.default.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        .appending(path: "UploadStaging", directoryHint: .isDirectory)
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        return try urls.map { url in
            let didStart = url.startAccessingSecurityScopedResource()
            defer { if didStart { url.stopAccessingSecurityScopedResource() } }
            let destination = root.appending(path: url.lastPathComponent)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: url, to: destination)
            return destination
        }
    }

    private func uploadPhotos(_ items: [PhotosPickerItem]) async {
        defer { selectedPhotoItems = [] }
        do {
            let root = try FileManager.default.url(
                for: .cachesDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            .appending(path: "PhotoPickerUpload", directoryHint: .isDirectory)
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

            var urls: [URL] = []
            for item in items {
                guard let data = try await item.loadTransferable(type: Data.self) else { continue }
                let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "dat"
                let url = root.appending(path: "\(UUID().uuidString).\(ext)")
                try data.write(to: url, options: [.atomic])
                urls.append(url)
            }

            guard !urls.isEmpty else { return }
            try await TransferQueue.shared.enqueueUploadBatch(
                localURLs: urls,
                remote: remote,
                destinationFolder: path,
                sourceKind: .photoLibrary
            )
            transientMessage = "Upload Photos ajouté à la file."
        } catch {
            transientMessage = "Échec upload Photos : \(error.localizedDescription)"
        }
    }

    private var pasteConflictTitle: String {
        guard let names = pasteConflictNames else { return "" }
        return names.count == 1
            ? "« \(names[0]) » existe déjà"
            : "\(names.count) éléments existent déjà"
    }

    private var pasteConflictMessage: String {
        guard let names = pasteConflictNames else { return "" }
        if names.count == 1 {
            return "Le fichier de destination sera écrasé sans possibilité d'annulation. La version remplacée n'est pas envoyée à la corbeille."
        }
        let preview = names.prefix(3).joined(separator: ", ")
        let suffix = names.count > 3 ? " et \(names.count - 3) autre\(names.count - 3 > 1 ? "s" : "")" : ""
        return "Les fichiers suivants seront écrasés sans possibilité d'annulation : \(preview)\(suffix)."
    }

    private var pasteMenuLabel: String {
        let clip = FilesClipboard.shared
        let count = clip.count
        let suffix = count > 1 ? "\(count) éléments" : "1 élément"
        return clip.operation == .cut
            ? "Coller (\(suffix), déplacer)"
            : "Coller (\(suffix), copier)"
    }

    private func pasteFromClipboard(force: Bool = false) async {
        do {
            _ = try await FilesClipboard.shared.paste(into: remote, folder: path, force: force)
            transientMessage = force
                ? "Collage avec écrasement en cours dans la file de transferts."
                : "Collage en cours dans la file de transferts."
            hapticSuccessTrigger &+= 1
            await load()
        } catch let error as FilesClipboardError {
            if case .destinationConflict(let names) = error {
                pasteConflictNames = names
            } else {
                transientMessage = "Échec du collage : \(error.localizedDescription)"
                hapticWarningTrigger &+= 1
            }
        } catch {
            transientMessage = "Échec du collage : \(error.localizedDescription)"
            hapticWarningTrigger &+= 1
            await LogService.shared.log(
                .error,
                category: "transfer",
                message: "Paste from clipboard failed: \(error.localizedDescription)"
            )
        }
    }

    private func deleteSelected(permanent: Bool) async {
        let entries = selectedEntries
        guard !entries.isEmpty else { return }
        var trashedCount = 0
        for entry in entries {
            do {
                if permanent {
                    try await TransferQueue.shared.enqueueDelete(
                        remote: remote,
                        path: entry.pathInRemote,
                        isDirectory: entry.isDirectory
                    )
                } else {
                    try await TransferQueue.shared.enqueueTrash(
                        remote: remote,
                        path: entry.pathInRemote,
                        name: entry.name,
                        isDirectory: entry.isDirectory,
                        sizeBytes: entry.size
                    )
                    trashedCount += 1
                }
            } catch {
                let action = permanent ? "suppression" : "mise à la corbeille"
                await LogService.shared.log(
                    .error,
                    category: "transfer",
                    message: "\(action) batch impossible : \(error.localizedDescription)"
                )
            }
        }
        if !permanent && trashedCount > 0 {
            transientMessage = "\(trashedCount) élément\(trashedCount > 1 ? "s" : "") déplacé\(trashedCount > 1 ? "s" : "") à la corbeille."
            hapticSuccessTrigger &+= 1
        } else if permanent {
            hapticWarningTrigger &+= 1
        }
        selectedEntryIDs.removeAll()
        selectionMode = false
        await load()
    }
}

private struct RemoteBatchTransferRequest: Identifiable {
    let id = UUID()
    let kind: TransferKind
    let entries: [RemoteEntryDTO]
}

private struct DisplayedEntry: Identifiable {
    let id: String
    let entry: RemoteEntryDTO
}

private struct FolderOverviewCard: View {
    let remote: String
    let path: String
    let folderCount: Int
    let fileCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                AppIconTile(systemImage: path.isEmpty ? "externaldrive.fill" : "folder.fill", tint: .blue, size: 52)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(remote)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
            }

            HStack(spacing: 10) {
                AppMetricPill(
                    value: "\(folderCount)",
                    label: folderCount == 1 ? "dossier" : "dossiers",
                    systemImage: "folder",
                    tint: .blue
                )
                AppMetricPill(
                    value: "\(fileCount)",
                    label: fileCount == 1 ? "fichier" : "fichiers",
                    systemImage: "doc",
                    tint: .teal
                )
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: .rect(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.quaternary)
        }
    }

    private var title: String {
        path.isEmpty ? "Racine du remote" : path
    }
}
