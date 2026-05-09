//
//  FolderView.swift
//  Rclone GUI — Views/Folders
//
//  Lists files and sub-folders under <remote>:<path>.
//  Phase B scope: read-only navigation + sort + filter (search).
//  Phase C will add: download, upload, move, rename, delete.
//

import SwiftUI

struct FolderView: View {
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
    @State private var deleteIsRecursive = false

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
                ToolbarItem(placement: .primaryAction) {
                    sortMenu
                }
            }
            .task(id: TaskKey(remote: remote, path: path)) {
                await load()
            }
            .refreshable {
                await load()
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
            .fullScreenCover(item: $playTarget) { entry in
                MediaPlayerHost(remote: remote, entry: entry)
            }
            .confirmationDialog(
                deleteDialogTitle,
                isPresented: Binding(
                    get: { deleteTarget != nil },
                    set: { if !$0 { deleteTarget = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Supprimer", role: .destructive) {
                    Task { await performDelete() }
                }
                Button("Annuler", role: .cancel) { deleteTarget = nil }
            } message: {
                if let target = deleteTarget {
                    Text(target.isDirectory
                         ? "Le dossier et tout son contenu seront supprimés."
                         : "Ce fichier sera supprimé du remote.")
                }
            }

        #if os(iOS)
        main.navigationBarTitleDisplayMode(.inline)
        #else
        main
        #endif
    }

    private var deleteDialogTitle: String {
        deleteTarget.map { "Supprimer « \($0.name) » ?" } ?? "Supprimer ?"
    }

    private func performDelete() async {
        guard let target = deleteTarget else { return }
        deleteTarget = nil
        do {
            try await TransferQueue.shared.enqueueDelete(
                remote: remote,
                path: target.pathInRemote,
                isDirectory: target.isDirectory
            )
            await load()
        } catch {
            await LogService.shared.log(
                .error,
                category: "transfer",
                message: "Échec suppression \(remote):\(target.pathInRemote) : \(error.localizedDescription)"
            )
            loadState = .failed("Échec de la suppression : \(error.localizedDescription)")
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
            ProgressView("Chargement…")
                .controlSize(.large)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loading where entries.isEmpty:
            ProgressView("Chargement…")
                .controlSize(.large)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

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
                ForEach(displayedEntries) { entry in
                    rowView(for: entry)
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
    private func rowView(for entry: RemoteEntryDTO) -> some View {
        if entry.isDirectory {
            NavigationLink(value: NavigationDestination.folder(
                remote: remote,
                path: entry.pathInRemote
            )) {
                EntryRowView(entry: entry)
            }
            .contextMenu {
                EntryActionsMenu(
                    entry: entry,
                    remote: remote,
                    renameTarget: $renameTarget,
                    deleteTarget: $deleteTarget,
                    playTarget: $playTarget
                )
            }
        } else {
            EntryRowView(entry: entry)
                .contextMenu {
                    EntryActionsMenu(
                        entry: entry,
                        remote: remote,
                        renameTarget: $renameTarget,
                        deleteTarget: $deleteTarget,
                        playTarget: $playTarget
                    )
                }
        }
    }

    private var sortMenu: some View {
        Menu {
            Picker("Trier par", selection: $sortMode) {
                ForEach(SortMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            Toggle("Ordre décroissant", isOn: $sortDescending)
        } label: {
            Image(systemName: "arrow.up.arrow.down.circle")
        }
        .accessibilityLabel("Options de tri")
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
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }
}
