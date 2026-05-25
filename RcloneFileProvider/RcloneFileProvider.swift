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
        try FileProviderBridge.ensureSubscriptionActive()
        return RcloneEnumerator(identifier: containerItemIdentifier)
    }

    // MARK: - Item lookup

    public func item(for identifier: NSFileProviderItemIdentifier, request: NSFileProviderRequest, completionHandler: @escaping (NSFileProviderItem?, Error?) -> Void) -> Progress {
        FileProviderBridge.appendDiagnostic("item requested id=\(identifier.rawValue)")
        let progress = Progress(totalUnitCount: 1)

        do {
            try FileProviderBridge.ensureSubscriptionActive()
        } catch {
            completionHandler(nil, error)
            progress.completedUnitCount = 1
            return progress
        }

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

        do {
            try FileProviderBridge.ensureSubscriptionActive()
        } catch {
            completionHandler(nil, nil, error)
            return progress
        }

        guard let decoded = RcloneItem.decode(itemIdentifier) else {
            completionHandler(nil, nil, NSError(
                domain: NSFileProviderErrorDomain,
                code: NSFileProviderError.noSuchItem.rawValue
            ))
            return progress
        }

        let ext = (decoded.path as NSString).pathExtension
        let requestID = UUID().uuidString

        // Destination partagée : l'app principale ecrit dans l'App Group, qui est
        // lisible/ecrivable depuis les deux sandboxes. temporaryDirectoryURL() de
        // l'extension n'est PAS accessible a l'app principale (sandbox different).
        var sharedDestination = FileProviderBridge.fetchedFilesDir.appending(path: requestID)
        if !ext.isEmpty {
            sharedDestination = sharedDestination.appendingPathExtension(ext)
        }

        // Destination finale Apple-managed : ce path-la est ce qu'on retourne a
        // iOS. Apple bouge ensuite le fichier dans son replica.
        var appleDestination = fetchTemporaryDirectory().appending(path: requestID)
        if !ext.isEmpty {
            appleDestination = appleDestination.appendingPathExtension(ext)
        }

        Task {
            do {
                // Délégation IPC vers l'app principale (Go runtime + crypt jetsam-able
                // dans une .appex iOS limitée à ~256 Mo).
                try await FileProviderBridge.requestFetchViaMainApp(
                    requestID: requestID,
                    remote: decoded.remote,
                    path: decoded.path,
                    destination: sharedDestination,
                    progress: progress
                )

                // App principale a ecrit dans sharedDestination. On bouge le fichier
                // vers Apple-managed tempDir avant de rendre la main a iOS.
                try FileManager.default.createDirectory(
                    at: appleDestination.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try? FileManager.default.removeItem(at: appleDestination)
                do {
                    try FileManager.default.moveItem(at: sharedDestination, to: appleDestination)
                } catch {
                    // Volumes potentiellement differents : fallback copy + remove.
                    try FileManager.default.copyItem(at: sharedDestination, to: appleDestination)
                    try? FileManager.default.removeItem(at: sharedDestination)
                }

                let downloadedSize = (try? FileManager.default
                    .attributesOfItem(atPath: appleDestination.path)[.size] as? Int64) ?? 0
                let item = RcloneItem(
                    id: itemIdentifier,
                    parentID: parentIdentifier(remote: decoded.remote, path: decoded.path),
                    displayName: (decoded.path as NSString).lastPathComponent,
                    isDirectory: false,
                    size: downloadedSize,
                    modTime: .now
                )
                FileProviderBridge.appendDiagnostic("fetchContents done id=\(itemIdentifier.rawValue) size=\(downloadedSize) at=\(appleDestination.path)")
                progress.completedUnitCount = progress.totalUnitCount
                completionHandler(appleDestination, item, nil)
            } catch {
                try? FileManager.default.removeItem(at: sharedDestination)
                FileProviderBridge.appendDiagnostic("fetchContents failed id=\(itemIdentifier.rawValue) error=\(error.localizedDescription)")
                completionHandler(nil, nil, error)
            }
        }
        return progress
    }

    // MARK: - Partial fetch (streaming) — UNAVAILABLE ON iOS

    // NOTE Apple : NSFileProviderFetchContentsOptions et
    // NSFileProviderMaterializationFlags sont macOS-only. iOS n'expose pas
    // fetchPartialContents — le streaming via FileProvider iOS n'est pas
    // supporté par Apple. Pour streamer, l'utilisateur doit configurer Infuse/VLC
    // sur le serveur HTTP local exposé par l'app principale (RcloneStreamingService),
    // hors Files.app.
    #if false
    public func fetchPartialContents(
        for itemIdentifier: NSFileProviderItemIdentifier,
        version requestedVersion: NSFileProviderItemVersion,
        request: NSFileProviderRequest,
        minimalRange requestedRange: NSRange,
        aligningTo alignment: Int,
        options: NSFileProviderFetchContentsOptions = [],
        completionHandler: @escaping (URL?, NSFileProviderItem?, NSRange, NSFileProviderMaterializationFlags, Error?) -> Void
    ) -> Progress {
        FileProviderBridge.appendDiagnostic("fetchPartialContents requested id=\(itemIdentifier.rawValue) range=\(requestedRange.location)+\(requestedRange.length) align=\(alignment)")
        let progress = Progress(totalUnitCount: 100)

        guard let decoded = RcloneItem.decode(itemIdentifier) else {
            completionHandler(nil, nil, NSRange(), [], NSError(
                domain: NSFileProviderErrorDomain,
                code: NSFileProviderError.noSuchItem.rawValue
            ))
            return progress
        }

        let ext = (decoded.path as NSString).pathExtension
        // Fichier sparse persistant pour ce (remote, path) : iOS appelle plusieurs
        // fetchPartialContents pour différents ranges du même fichier ; on évite
        // de re-créer un sparse à chaque fois.
        let safeKey = ("\(decoded.remote):\(decoded.path)")
            .addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? UUID().uuidString
        var appleDestination = fetchTemporaryDirectory()
            .appending(path: "stream-\(safeKey)")
        if !ext.isEmpty {
            appleDestination = appleDestination.appendingPathExtension(ext)
        }

        Task {
            do {
                let session = try await FileProviderBridge.requestStreamURLViaMainApp(
                    remote: decoded.remote,
                    path: decoded.path,
                    timeout: 30
                )

                guard let baseURL = URL(string: session.url) else {
                    throw NSError(
                        domain: NSFileProviderErrorDomain,
                        code: NSFileProviderError.serverUnreachable.rawValue,
                        userInfo: [NSLocalizedDescriptionKey: "URL streaming invalide"]
                    )
                }

                // HEAD pour récupérer la taille totale (alloue le sparse à la
                // bonne taille pour qu'iOS sache que c'est le fichier complet).
                var headRequest = URLRequest(url: baseURL)
                headRequest.httpMethod = "HEAD"
                let (_, headResponse) = try await URLSession.shared.data(for: headRequest)
                guard let httpHead = headResponse as? HTTPURLResponse else {
                    throw NSError(
                        domain: NSFileProviderErrorDomain,
                        code: NSFileProviderError.serverUnreachable.rawValue,
                        userInfo: [NSLocalizedDescriptionKey: "Réponse HEAD invalide"]
                    )
                }
                let totalSize = Int64(httpHead.value(forHTTPHeaderField: "Content-Length") ?? "-1") ?? -1

                // Range étendu : on télécharge un chunk un peu plus grand que
                // demandé (alignement) pour éviter trop d'aller-retours iOS.
                let blockSize = max(alignment, 1 << 20) // 1 Mo min
                let alignedStart = (requestedRange.location / blockSize) * blockSize
                var alignedEnd = ((requestedRange.location + requestedRange.length + blockSize - 1) / blockSize) * blockSize
                if totalSize > 0, alignedEnd > Int(totalSize) {
                    alignedEnd = Int(totalSize)
                }
                let chunkLength = alignedEnd - alignedStart

                try FileManager.default.createDirectory(
                    at: appleDestination.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )

                // Pre-allocate le fichier sparse à la taille totale si nouveau.
                if !FileManager.default.fileExists(atPath: appleDestination.path) {
                    FileManager.default.createFile(atPath: appleDestination.path, contents: nil)
                }
                let writeHandle = try FileHandle(forWritingTo: appleDestination)
                if totalSize > 0 {
                    try writeHandle.truncate(toOffset: UInt64(totalSize))
                }

                // GET avec Range header.
                var rangeRequest = URLRequest(url: baseURL)
                rangeRequest.httpMethod = "GET"
                rangeRequest.setValue("bytes=\(alignedStart)-\(alignedEnd - 1)", forHTTPHeaderField: "Range")
                let (rangeData, _) = try await URLSession.shared.data(for: rangeRequest)

                try writeHandle.seek(toOffset: UInt64(alignedStart))
                try writeHandle.write(contentsOf: rangeData)
                try writeHandle.close()

                let item = RcloneItem(
                    id: itemIdentifier,
                    parentID: parentIdentifier(remote: decoded.remote, path: decoded.path),
                    displayName: (decoded.path as NSString).lastPathComponent,
                    isDirectory: false,
                    size: totalSize > 0 ? totalSize : Int64(rangeData.count),
                    modTime: .now
                )
                let materialized = NSRange(location: alignedStart, length: rangeData.count)
                FileProviderBridge.appendDiagnostic("fetchPartialContents done id=\(itemIdentifier.rawValue) range=\(alignedStart)+\(rangeData.count) at=\(appleDestination.path)")
                progress.completedUnitCount = 100
                completionHandler(appleDestination, item, materialized, [], nil)
            } catch {
                FileProviderBridge.appendDiagnostic("fetchPartialContents failed id=\(itemIdentifier.rawValue) error=\(error.localizedDescription)")
                completionHandler(nil, nil, NSRange(), [], error)
            }
        }
        return progress
    }
    #endif

    // MARK: - Mutations (create / modify / delete)

    public func createItem(basedOn itemTemplate: NSFileProviderItem, fields: NSFileProviderItemFields, contents url: URL?, options: NSFileProviderCreateItemOptions, request: NSFileProviderRequest, completionHandler: @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, Error?) -> Void) -> Progress {
        let progress = Progress(totalUnitCount: 1)
        do {
            try FileProviderBridge.ensureSubscriptionActive()
        } catch {
            completionHandler(nil, [], false, error)
            return progress
        }
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
        do {
            try FileProviderBridge.ensureSubscriptionActive()
        } catch {
            completionHandler(nil, [], false, error)
            return progress
        }
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
        do {
            try FileProviderBridge.ensureSubscriptionActive()
        } catch {
            completionHandler(error)
            return progress
        }
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
