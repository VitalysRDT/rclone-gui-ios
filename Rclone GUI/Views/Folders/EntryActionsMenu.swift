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
import UniformTypeIdentifiers
#if canImport(AppKit)
import AppKit
#endif

struct EntryActionsMenu: View {
    let entry: RemoteEntryDTO
    let remote: String

    /// Bindings to the parent's sheet/dialog state. The parent owns the
    /// actual UI (sheet / fullScreenCover / confirmationDialog) so the
    /// menu is fire-and-forget.
    @Binding var renameTarget: RemoteEntryDTO?
    @Binding var deleteTarget: RemoteEntryDTO?
    @Binding var playTarget: RemoteEntryDTO?
    @Binding var previewTarget: RemoteEntryDTO?
    @Binding var moveTarget: RemoteEntryDTO?
    @Binding var downloadTarget: RemoteEntryDTO?
    @Binding var externalOpenTarget: RemoteEntryDTO?

    var body: some View {
        Group {
            if !entry.isDirectory {
                Button {
                    if Self.isMediaFile(entry.name) {
                        playTarget = entry
                    } else {
                        previewTarget = entry
                    }
                } label: {
                    Label(Self.isMediaFile(entry.name) ? "Lire dans l'app" : "Ouvrir dans l'app",
                          systemImage: Self.isMediaFile(entry.name) ? "play.circle" : "doc.viewfinder")
                }

                Button {
                    externalOpenTarget = entry
                } label: {
                    Label("Ouvrir dans une autre app", systemImage: "square.and.arrow.up")
                }
                Divider()
            }

            Button {
                downloadTarget = entry
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
                moveTarget = entry
            } label: {
                Label("Déplacer", systemImage: "arrow.left.arrow.right")
            }

            Divider()

            Button {
                FilesClipboard.shared.stage(entries: [entry], remote: remote, operation: .cut)
            } label: {
                Label("Couper", systemImage: "scissors")
            }

            Button {
                FilesClipboard.shared.stage(entries: [entry], remote: remote, operation: .copy)
            } label: {
                Label("Copier", systemImage: "doc.on.doc")
            }

            Button {
                #if canImport(UIKit)
                UIPasteboard.general.string = entry.pathInRemote
                #elseif canImport(AppKit)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(entry.pathInRemote, forType: .string)
                #endif
            } label: {
                Label("Copier le chemin (texte)", systemImage: "text.quote")
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
        let dir = Self.downloadParentDirectory(remote: remote)
        do {
            // Route via la surcharge dossier-aware : un dossier passe par
            // sync/copy (copyDirAsync), un fichier par copyfile. Le récursif
            // est ainsi géré nativement (fini la limitation mono-fichier).
            try await TransferQueue.shared.enqueueDownload(
                remote: remote,
                entry: entry,
                to: dir
            )
            await LogService.shared.log(
                .info,
                category: "transfer",
                message: "Téléchargement enqueued : \(remote):\(entry.pathInRemote)\(entry.isDirectory ? " (dossier)" : "")"
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

    /// Public entrypoint used by single-tap on a row when the file is not
    /// a media file. Triggers the same enqueue flow as the menu button.
    @MainActor
    static func tapDownload(remote: String, entry: RemoteEntryDTO) async {
        let dir = downloadParentDirectory(remote: remote)
        do {
            try await TransferQueue.shared.enqueueDownload(
                remote: remote,
                entry: entry,
                to: dir
            )
            await LogService.shared.log(
                .info,
                category: "transfer",
                message: "Téléchargement (tap) : \(remote):\(entry.pathInRemote)"
            )
        } catch {
            await LogService.shared.log(
                .error,
                category: "transfer",
                message: "Échec téléchargement tap (\(remote):\(entry.pathInRemote)) : \(error.localizedDescription)"
            )
        }
    }

    // MARK: - Helpers

    /// Dossier local parent des téléchargements pour ce remote
    /// (`Documents/Downloads/<remote>/`). La surcharge dossier-aware de
    /// `enqueueDownload(entry:to:)` y crée le fichier ou le sous-dossier.
    private static func downloadParentDirectory(remote: String) -> URL {
        let docs = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return docs
            .appending(path: "Downloads", directoryHint: .isDirectory)
            .appending(path: remote, directoryHint: .isDirectory)
    }

    // Détection centralisée dans MediaFormat (source unique de vérité, voir
    // aussi le routage AVPlayer ↔ VLC du lecteur embarqué).
    static func isMediaFile(_ name: String) -> Bool { MediaFormat.isMedia(name) }
    static func isVideoFile(_ name: String) -> Bool { MediaFormat.isVideo(name) }
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
                    field.rgNoAutocap()
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
            .rgInlineNavTitle()
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
