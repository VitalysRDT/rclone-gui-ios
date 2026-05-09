//
//  EntryActionsMenu.swift
//  Rclone GUI — Views/Folders
//
//  Context-menu actions attached to each row in FolderView. Surfaces:
//    - Lire        (file ; only if isMediaFile)
//    - Télécharger (file or folder, recursive)
//    - Renommer
//    - Copier le chemin
//    - Supprimer   (with confirmation)
//
//  Move + Share will land in Phase E.
//

import SwiftUI

struct EntryActionsMenu: View {
    let entry: RemoteEntryDTO
    let remote: String

    /// Bindings to the parent's sheet/dialog state. The parent owns the
    /// actual UI (sheet / fullScreenCover / confirmationDialog) so the
    /// menu is fire-and-forget.
    @Binding var renameTarget: RemoteEntryDTO?
    @Binding var deleteTarget: RemoteEntryDTO?
    @Binding var playTarget: RemoteEntryDTO?

    var body: some View {
        Group {
            if !entry.isDirectory, Self.isMediaFile(entry.name) {
                Button {
                    playTarget = entry
                } label: {
                    Label("Lire", systemImage: "play.circle")
                }
                Divider()
            }

            Button {
                Task { await download() }
            } label: {
                Label(entry.isDirectory ? "Télécharger le dossier" : "Télécharger",
                      systemImage: "arrow.down.circle")
            }

            Button {
                renameTarget = entry
            } label: {
                Label("Renommer", systemImage: "pencil")
            }

            Button {
                #if canImport(UIKit)
                UIPasteboard.general.string = entry.pathInRemote
                #endif
            } label: {
                Label("Copier le chemin", systemImage: "doc.on.doc")
            }

            Divider()

            Button(role: .destructive) {
                deleteTarget = entry
            } label: {
                Label("Supprimer", systemImage: "trash")
            }
        }
    }

    @MainActor
    private func download() async {
        let dst = Self.downloadDestination(remote: remote, entry: entry)
        do {
            try Self.ensureParentExists(dst)
            // Phase D v1 : single-file download via copyfile. Folder recursive
            // download will be added in Phase E2 via sync/copy + manifest walking.
            try await TransferQueue.shared.enqueueDownload(
                remote: remote,
                path: entry.pathInRemote,
                to: dst
            )
        } catch {
            // The queue persists Transfer.lastError when a job fails mid-run,
            // but enqueue itself failing (e.g. local FS error before the job
            // is even submitted) wouldn't show up there. Log it so it surfaces
            // in Settings → Logs at minimum.
            await LogService.shared.log(
                .error,
                category: "transfer",
                message: "Échec de mise en file de téléchargement (\(remote):\(entry.pathInRemote)) : \(error.localizedDescription)"
            )
        }
    }

    // MARK: - Helpers

    private static func downloadDestination(remote: String, entry: RemoteEntryDTO) -> URL {
        let docs = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return docs
            .appending(path: "Downloads", directoryHint: .isDirectory)
            .appending(path: remote, directoryHint: .isDirectory)
            .appending(path: entry.name)
    }

    private static func ensureParentExists(_ url: URL) throws {
        let parent = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
    }

    static func isMediaFile(_ name: String) -> Bool {
        let ext = (name as NSString).pathExtension.lowercased()
        return [
            // Video
            "mp4", "mkv", "mov", "avi", "webm", "m4v", "ts", "mpg", "mpeg",
            // Audio
            "mp3", "m4a", "wav", "flac", "ogg", "aac", "alac", "opus"
        ].contains(ext)
    }
}

// MARK: - Rename Sheet

struct RenameSheetView: View {
    let entry: RemoteEntryDTO
    let remote: String
    @Binding var isPresented: Bool

    @State private var newName: String = ""
    @State private var isWorking = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Nouveau nom") {
                    let field = TextField("Nom de fichier", text: $newName)
                        .autocorrectionDisabled(true)
                    #if os(iOS)
                    field.textInputAutocapitalization(.never)
                    #else
                    field
                    #endif
                }

                if let error {
                    Section {
                        Text(error).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Renommer")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { isPresented = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await rename() }
                    } label: {
                        if isWorking { ProgressView() } else { Text("Renommer") }
                    }
                    .disabled(newName.isEmpty || newName == entry.name || isWorking)
                }
            }
            .onAppear { newName = entry.name }
        }
    }

    @MainActor
    private func rename() async {
        isWorking = true
        defer { isWorking = false }

        let parent = (entry.pathInRemote as NSString).deletingLastPathComponent
        let dstPath = parent.isEmpty ? newName : "\(parent)/\(newName)"

        do {
            try await TransferQueue.shared.enqueueRename(
                remote: remote,
                oldPath: entry.pathInRemote,
                newPath: dstPath
            )
            isPresented = false
        } catch {
            self.error = error.localizedDescription
        }
    }
}
