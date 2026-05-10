//
//  RcloneFileProvider.swift
//  Rclone GUI — FileProvider Extension
//
//  Main extension class. Handles enumeration, fetch, create, modify,
//  and delete operations on items exposed in Files.app.
//
//  The extension uses a thin in-process rclone client so Files.app can
//  enumerate, fetch, create, modify, and delete without waiting for the
//  containing app to be foregrounded.
//

import Foundation
import FileProvider
import UniformTypeIdentifiers

public final class RcloneFileProvider: NSObject, NSFileProviderReplicatedExtension {

    private let domain: NSFileProviderDomain

    public required init(domain: NSFileProviderDomain) {
        self.domain = domain
        super.init()
        do {
            try FileProviderBridge.ensureDirectoriesExist()
            FileProviderBridge.appendDiagnostic("extension init domain=\(domain.identifier.rawValue)")
        } catch {
            FileProviderBridge.appendDiagnostic("extension init directory error: \(error.localizedDescription)")
        }
    }

    /// Apple exige que le fichier renvoyé par fetchContents soit dans le
    /// temporaryDirectoryURL géré par NSFileProviderManager (mêmes volume +
    /// permissions que le replica iOS). Un path App Group custom passe le
    /// "ownership transfer" mais produit un fichier qu'Aperçu ne peut pas
    /// ouvrir → "Impossible de communiquer avec une application d'aide".
    private func fetchTemporaryDirectory() -> URL {
        if let manager = NSFileProviderManager(for: domain),
           let tempDir = try? manager.temporaryDirectoryURL() {
            return tempDir
        }
        FileProviderBridge.appendDiagnostic("temporaryDirectoryURL unavailable, fallback NSTemporaryDirectory")
        return URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    }

    public func invalidate() {
        FileProviderBridge.appendDiagnostic("extension invalidate")
    }

    // MARK: - Enumeration

    public func enumerator(for containerItemIdentifier: NSFileProviderItemIdentifier, request: NSFileProviderRequest) throws -> NSFileProviderEnumerator {
        FileProviderBridge.appendDiagnostic("enumerator requested id=\(containerItemIdentifier.rawValue)")
        return RcloneEnumerator(identifier: containerItemIdentifier)
    }

    // MARK: - Item lookup

    public func item(for identifier: NSFileProviderItemIdentifier, request: NSFileProviderRequest, completionHandler: @escaping (NSFileProviderItem?, Error?) -> Void) -> Progress {
        FileProviderBridge.appendDiagnostic("item requested id=\(identifier.rawValue)")
        let progress = Progress(totalUnitCount: 1)

        if identifier == NSFileProviderItemIdentifier.rootContainer {
            let item = RcloneItem(
                id: NSFileProviderItemIdentifier.rootContainer,
                parentID: NSFileProviderItemIdentifier.rootContainer,
                displayName: "Rclone GUI",
                isDirectory: true,
                size: 0,
                modTime: Date.distantPast
            )
            completionHandler(item, nil)
            progress.completedUnitCount = 1
            return progress
        }

        if identifier == .workingSet || identifier == .trashContainer {
            completionHandler(RcloneItem(
                id: identifier,
                parentID: NSFileProviderItemIdentifier.rootContainer,
                displayName: identifier == .workingSet ? "Récents" : "Corbeille",
                isDirectory: true,
                size: 0,
                modTime: Date.distantPast
            ), nil)
            progress.completedUnitCount = 1
            return progress
        }

        guard let decoded = RcloneItem.decode(identifier) else {
            completionHandler(nil, NSError(
                domain: NSFileProviderErrorDomain,
                code: NSFileProviderError.noSuchItem.rawValue
            ))
            progress.completedUnitCount = 1
            return progress
        }

        if decoded.path.isEmpty {
            completionHandler(RcloneItem(
                id: identifier,
                parentID: NSFileProviderItemIdentifier.rootContainer,
                displayName: decoded.remote,
                isDirectory: true,
                size: 0,
                modTime: Date.distantPast
            ), nil)
            progress.completedUnitCount = 1
            return progress
        }

        Task {
            do {
                guard let entry = try await RcloneProviderClient.shared.stat(remote: decoded.remote, path: decoded.path) else {
                    completionHandler(nil, NSError(
                        domain: NSFileProviderErrorDomain,
                        code: NSFileProviderError.noSuchItem.rawValue
                    ))
                    return
                }
                completionHandler(RcloneItem(
                    id: identifier,
                    parentID: parentIdentifier(remote: decoded.remote, path: decoded.path),
                    displayName: entry.name,
                    isDirectory: entry.isDirectory,
                    size: entry.size,
                    modTime: entry.modTime
                ), nil)
                progress.completedUnitCount = 1
            } catch {
                if let manifestItem = manifestItem(remote: decoded.remote, path: decoded.path, identifier: identifier) {
                    completionHandler(manifestItem, nil)
                } else {
                    completionHandler(nil, NSError(
                        domain: NSFileProviderErrorDomain,
                        code: NSFileProviderError.noSuchItem.rawValue,
                        userInfo: [NSLocalizedDescriptionKey: error.localizedDescription]
                    ))
                }
            }
        }
        return progress
    }

    // MARK: - Fetch contents (download on demand)

    public func fetchContents(for itemIdentifier: NSFileProviderItemIdentifier, version requestedVersion: NSFileProviderItemVersion?, request: NSFileProviderRequest, completionHandler: @escaping (URL?, NSFileProviderItem?, Error?) -> Void) -> Progress {
        FileProviderBridge.appendDiagnostic("fetchContents requested id=\(itemIdentifier.rawValue)")
        let progress = Progress(totalUnitCount: 100)

        guard let decoded = RcloneItem.decode(itemIdentifier) else {
            completionHandler(nil, nil, NSError(
                domain: NSFileProviderErrorDomain,
                code: NSFileProviderError.noSuchItem.rawValue
            ))
            return progress
        }

        let tempDir = fetchTemporaryDirectory()
        let ext = (decoded.path as NSString).pathExtension
        var destination = tempDir.appending(path: UUID().uuidString)
        if !ext.isEmpty {
            destination = destination.appendingPathExtension(ext)
        }

        Task {
            do {
                let entry = try await RcloneProviderClient.shared.download(
                    remote: decoded.remote,
                    path: decoded.path,
                    to: destination
                )
                let downloadedSize = (try? FileManager.default
                    .attributesOfItem(atPath: destination.path)[.size] as? Int64) ?? entry?.size ?? 0
                let item = RcloneItem(
                    id: itemIdentifier,
                    parentID: parentIdentifier(remote: decoded.remote, path: decoded.path),
                    displayName: entry?.name ?? (decoded.path as NSString).lastPathComponent,
                    isDirectory: false,
                    size: downloadedSize,
                    modTime: entry?.modTime ?? .now
                )
                FileProviderBridge.appendDiagnostic("fetchContents done id=\(itemIdentifier.rawValue) size=\(downloadedSize) at=\(destination.path)")
                progress.completedUnitCount = 100
                completionHandler(destination, item, nil)
            } catch {
                FileProviderBridge.appendDiagnostic("fetchContents failed id=\(itemIdentifier.rawValue) error=\(error.localizedDescription)")
                completionHandler(nil, nil, error)
            }
        }
        return progress
    }

    // MARK: - Mutations (create / modify / delete)

    public func createItem(basedOn itemTemplate: NSFileProviderItem, fields: NSFileProviderItemFields, contents url: URL?, options: NSFileProviderCreateItemOptions, request: NSFileProviderRequest, completionHandler: @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, Error?) -> Void) -> Progress {
        let progress = Progress(totalUnitCount: 1)
        guard let parent = RcloneItem.decode(itemTemplate.parentItemIdentifier) else {
            completionHandler(nil, [], false, NSError(domain: NSFileProviderErrorDomain, code: NSFileProviderError.noSuchItem.rawValue))
            return progress
        }
        let newPath = join(parent.path, itemTemplate.filename)

        Task {
            do {
                if let url {
                    let didStart = url.startAccessingSecurityScopedResource()
                    defer { if didStart { url.stopAccessingSecurityScopedResource() } }
                    let entry = try await RcloneProviderClient.shared.upload(localURL: url, remote: parent.remote, path: newPath)
                    completionHandler(item(remote: parent.remote, entry: entry, fallbackPath: newPath), [], false, nil)
                } else {
                    try await RcloneProviderClient.shared.mkdir(remote: parent.remote, path: newPath)
                    completionHandler(RcloneItem(
                        id: RcloneItem.identifier(remote: parent.remote, path: newPath),
                        parentID: itemTemplate.parentItemIdentifier,
                        displayName: itemTemplate.filename,
                        isDirectory: true,
                        size: 0,
                        modTime: .now
                    ), [], false, nil)
                }
                progress.completedUnitCount = 1
            } catch {
                completionHandler(nil, [], false, error)
            }
        }
        return progress
    }

    public func modifyItem(_ item: NSFileProviderItem, baseVersion version: NSFileProviderItemVersion, changedFields: NSFileProviderItemFields, contents newContents: URL?, options: NSFileProviderModifyItemOptions, request: NSFileProviderRequest, completionHandler: @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, Error?) -> Void) -> Progress {
        let progress = Progress(totalUnitCount: 1)
        guard let decoded = RcloneItem.decode(item.itemIdentifier) else {
            completionHandler(nil, [], false, NSError(domain: NSFileProviderErrorDomain, code: NSFileProviderError.noSuchItem.rawValue))
            return progress
        }

        Task {
            do {
                if let newContents {
                    let didStart = newContents.startAccessingSecurityScopedResource()
                    defer { if didStart { newContents.stopAccessingSecurityScopedResource() } }
                    let entry = try await RcloneProviderClient.shared.upload(
                        localURL: newContents,
                        remote: decoded.remote,
                        path: decoded.path
                    )
                    completionHandler(self.item(remote: decoded.remote, entry: entry, fallbackPath: decoded.path), [], false, nil)
                } else {
                    let entry = try await RcloneProviderClient.shared.stat(remote: decoded.remote, path: decoded.path)
                    completionHandler(self.item(remote: decoded.remote, entry: entry, fallbackPath: decoded.path), [], false, nil)
                }
                progress.completedUnitCount = 1
            } catch {
                completionHandler(nil, [], false, error)
            }
        }
        return progress
    }

    public func deleteItem(identifier: NSFileProviderItemIdentifier, baseVersion version: NSFileProviderItemVersion, options: NSFileProviderDeleteItemOptions, request: NSFileProviderRequest, completionHandler: @escaping (Error?) -> Void) -> Progress {
        let progress = Progress(totalUnitCount: 1)
        guard let decoded = RcloneItem.decode(identifier), !decoded.path.isEmpty else {
            completionHandler(NSError(domain: NSFileProviderErrorDomain, code: NSFileProviderError.noSuchItem.rawValue))
            return progress
        }

        Task {
            do {
                let entry = try await RcloneProviderClient.shared.stat(remote: decoded.remote, path: decoded.path)
                try await RcloneProviderClient.shared.delete(
                    remote: decoded.remote,
                    path: decoded.path,
                    isDirectory: entry?.isDirectory ?? false
                )
                progress.completedUnitCount = 1
                completionHandler(nil)
            } catch {
                completionHandler(error)
            }
        }
        return progress
    }

    private func item(remote: String, entry: FPRemoteEntry?, fallbackPath: String) -> RcloneItem {
        RcloneItem(
            id: RcloneItem.identifier(remote: remote, path: entry?.path ?? fallbackPath),
            parentID: parentIdentifier(remote: remote, path: entry?.path ?? fallbackPath),
            displayName: entry?.name ?? (fallbackPath as NSString).lastPathComponent,
            isDirectory: entry?.isDirectory ?? false,
            size: entry?.size ?? 0,
            modTime: entry?.modTime ?? .now
        )
    }

    private func parentIdentifier(remote: String, path: String) -> NSFileProviderItemIdentifier {
        let parent = (path as NSString).deletingLastPathComponent
        return parent.isEmpty
            ? RcloneItem.identifier(remote: remote, path: "")
            : RcloneItem.identifier(remote: remote, path: parent)
    }

    private func join(_ parent: String, _ child: String) -> String {
        parent.isEmpty ? child : "\(parent)/\(child)"
    }

    private func manifestItem(
        remote: String,
        path: String,
        identifier: NSFileProviderItemIdentifier
    ) -> RcloneItem? {
        let parentPath = (path as NSString).deletingLastPathComponent
        let url = FileProviderBridge.folderManifestURL(remote: remote, path: parentPath)
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([FolderManifestEntry].self, from: data),
              let entry = entries.first(where: { $0.path == path }) else {
            return nil
        }

        return RcloneItem(
            id: identifier,
            parentID: parentIdentifier(remote: remote, path: path),
            displayName: entry.name,
            isDirectory: entry.isDirectory,
            size: entry.size,
            modTime: entry.modTime
        )
    }
}
