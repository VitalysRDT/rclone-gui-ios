//
//  EntryActionsMenu.swift
//  Rclone GUI — Views/Folders
//
//  Context menu (long-press / right-click) for a file or folder row.
//  Phase C scope: download, rename, delete, copy/move (limited).
//  Phase D will add: play, share via presigned URL, open with…
//

import SwiftUI

struct EntryActionsMenu: View {
    let entry: RemoteEntryDTO
    let remote: String
    let onRequestRename: () -> Void
    let onRequestMove: () -> Void

    var body: some View {
        Group {
            Button {
                Task { await downloadAction() }
            } label: {
                Label(entry.isDirectory ? "Télécharger le dossier" : "Télécharger",
                      systemImage: "arrow.down.circle")
            }

            Button(action: onRequestRename) {
                Label("Renommer", systemImage: "pencil")
            }

            Button(action: onRequestMove) {
                Label("Déplacer…", systemImage: "arrow.left.arrow.right")
            }

            Divider()

            Button(role: .destructive) {
                Task { await deleteAction() }
            } label: {
                Label("Supprimer", systemImage: "trash")
            }
        }
    }

    // MARK: - Actions

    @MainActor
    private func downloadAction() async {
        let documents = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dst = documents
            .appending(path: "Downloads", directoryHint: .isDirectory)
            .appending(path: remote, directoryHint: .isDirectory)
            .appending(path: entry.pathInRemote)
        do {
            try await TransferQueue.shared.enqueueDownload(
                remote: remote,
                path: entry.pathInRemote,
                to: dst
            )
        } catch {
            // Surfaced in Transfer.lastError once enqueued; if the enqueue
            // itself throws (e.g. RPC unreachable), we currently swallow it.
            // Phase E adds an error toast surface.
            print("Download enqueue failed: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func deleteAction() async {
        do {
            try await TransferQueue.shared.enqueueDelete(
                remote: remote,
                path: entry.pathInRemote,
                isDirectory: entry.isDirectory
            )
        } catch {
            print("Delete enqueue failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - Rename sheet helper

struct RenameSheet: View {
    let entry: RemoteEntryDTO
    let remote: String
    @Binding var isPresented: Bool

    @State private var newName: String

    init(entry: RemoteEntryDTO, remote: String, isPresented: Binding<Bool>) {
        self.entry = entry
        self.remote = remote
        self._isPresented = isPresented
        self._newName = State(initialValue: entry.name)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Nouveau nom") {
                    TextField("Nom", text: $newName)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                Section {
                    Button("Renommer") {
                        Task { await rename() }
                    }
                    .disabled(newName.isEmpty || newName == entry.name)
                }
            }
            .navigationTitle("Renommer")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { isPresented = false }
                }
            }
        }
    }

    private func rename() async {
        let parent = (entry.pathInRemote as NSString).deletingLastPathComponent
        let newPath = parent.isEmpty ? newName : "\(parent)/\(newName)"
        do {
            try await TransferQueue.shared.enqueueRename(
                remote: remote,
                oldPath: entry.pathInRemote,
                newPath: newPath
            )
            isPresented = false
        } catch {
            print("Rename failed: \(error.localizedDescription)")
        }
    }
}
