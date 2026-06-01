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
                    Label("Ouvrir dans l'app", systemImage: Self.isMediaFile(entry.name) ? "play.circle" : "doc.viewfinder")
                }

                if Self.isVideoFile(entry.name) {
                    Menu {
                        Button {
                            Task { await streamInExternalPlayer(scheme: .infuse) }
                        } label: {
                            Label("Infuse", systemImage: "play.tv")
                        }
                        Button {
                            Task { await streamInExternalPlayer(scheme: .vlc) }
                        } label: {
                            Label("VLC", systemImage: "play.tv.fill")
                        }
                    } label: {
                        Label("Streamer dans…", systemImage: "play.rectangle.on.rectangle")
                    }
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
            await LogService.shared.log(
                .info,
                category: "transfer",
                message: "Téléchargement enqueued : \(remote):\(entry.pathInRemote) → \(dst.path)"
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
        let dst = downloadDestination(remote: remote, entry: entry)
        do {
            try ensureParentExists(dst)
            try await TransferQueue.shared.enqueueDownload(
                remote: remote,
                path: entry.pathInRemote,
                to: dst
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
        if let type = UTType(filenameExtension: ext),
           type.conforms(to: .movie) || type.conforms(to: .audio) {
            return true
        }
        return [
            // Video
            "mp4", "mkv", "mov", "avi", "webm", "m4v", "ts", "mpg", "mpeg",
            // Audio
            "mp3", "m4a", "wav", "flac", "ogg", "aac", "alac", "opus"
        ].contains(ext)
    }

    static func isVideoFile(_ name: String) -> Bool {
        let ext = (name as NSString).pathExtension.lowercased()
        if let type = UTType(filenameExtension: ext), type.conforms(to: .movie) {
            return true
        }
        return ["mp4", "mkv", "mov", "avi", "webm", "m4v", "ts", "mpg", "mpeg"].contains(ext)
    }

    enum ExternalPlayerScheme {
        case infuse
        case vlc

        func callbackURL(for streamURL: URL) -> URL? {
            // Encode l'URL HTTP locale dans le scheme x-callback-url propre à
            // chaque player. Infuse : infuse://x-callback-url/play?url=...
            // VLC : vlc-x-callback://x-callback-url/stream?url=...
            var components = URLComponents()
            switch self {
            case .infuse:
                components.scheme = "infuse"
                components.host = "x-callback-url"
                components.path = "/play"
            case .vlc:
                components.scheme = "vlc-x-callback"
                components.host = "x-callback-url"
                components.path = "/stream"
            }
            components.queryItems = [URLQueryItem(name: "url", value: streamURL.absoluteString)]
            return components.url
        }
    }

    @MainActor
    private func streamInExternalPlayer(scheme: ExternalPlayerScheme) async {
        do {
            let session = try await RcloneStreamingService.shared.session(
                remote: remote,
                path: entry.pathInRemote,
                sizeHint: entry.size
            )
            guard let callbackURL = scheme.callbackURL(for: session.url) else {
                await LogService.shared.log(
                    .error,
                    category: "streaming",
                    message: "Impossible de construire l'URL callback pour \(entry.name)"
                )
                return
            }
            #if canImport(UIKit)
            await UIApplication.shared.open(callbackURL)
            #elseif canImport(AppKit)
            NSWorkspace.shared.open(callbackURL)
            #endif
            await LogService.shared.log(
                .info,
                category: "streaming",
                message: "Stream → \(callbackURL.scheme ?? "?") : \(remote):\(entry.pathInRemote)"
            )
        } catch {
            await LogService.shared.log(
                .error,
                category: "streaming",
                message: "Streaming externe échoué (\(remote):\(entry.pathInRemote)) : \(error.localizedDescription)"
            )
        }
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
