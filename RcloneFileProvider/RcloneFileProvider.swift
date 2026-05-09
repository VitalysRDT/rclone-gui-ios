//
//  RcloneFileProvider.swift
//  Rclone GUI — FileProvider Extension
//
//  Main extension class. Handles enumeration, fetch, create, modify,
//  and delete operations on items exposed in Files.app.
//
//  Architecture (PRD FR-045) : THIS EXTENSION HAS NO Go RUNTIME.
//  All heavy work is delegated to the main app via App Group files +
//  Darwin Notifications. See AppGroupBridge.swift for the contract.
//

import Foundation
import FileProvider
import UniformTypeIdentifiers

public final class RcloneFileProvider: NSObject, NSFileProviderReplicatedExtension {

    public required init(domain: NSFileProviderDomain) {
        super.init()
        try? FileProviderBridge.ensureDirectoriesExist()
    }

    public func invalidate() {}

    // MARK: - Enumeration

    public func enumerator(for containerItemIdentifier: NSFileProviderItemIdentifier, request: NSFileProviderRequest) throws -> NSFileProviderEnumerator {
        return RcloneEnumerator(identifier: containerItemIdentifier)
    }

    // MARK: - Item lookup

    public func item(for identifier: NSFileProviderItemIdentifier, request: NSFileProviderRequest, completionHandler: @escaping (NSFileProviderItem?, Error?) -> Void) -> Progress {
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

        // For non-root items, defer to manifest / cache. Phase D2 wires the IPC.
        // For now, return a generic "directory" placeholder so Files.app doesn't crash.
        if let decoded = RcloneItem.decode(identifier) {
            let item = RcloneItem(
                id: identifier,
                parentID: NSFileProviderItemIdentifier.rootContainer,
                displayName: decoded.path.isEmpty ? decoded.remote : (decoded.path as NSString).lastPathComponent,
                isDirectory: true,
                size: 0,
                modTime: Date.distantPast
            )
            completionHandler(item, nil)
        } else {
            completionHandler(nil, NSError(
                domain: NSFileProviderErrorDomain,
                code: NSFileProviderError.noSuchItem.rawValue
            ))
        }
        progress.completedUnitCount = 1
        return progress
    }

    // MARK: - Fetch contents (download on demand)

    public func fetchContents(for itemIdentifier: NSFileProviderItemIdentifier, version requestedVersion: NSFileProviderItemVersion?, request: NSFileProviderRequest, completionHandler: @escaping (URL?, NSFileProviderItem?, Error?) -> Void) -> Progress {
        let progress = Progress(totalUnitCount: 100)

        guard let decoded = RcloneItem.decode(itemIdentifier) else {
            completionHandler(nil, nil, NSError(
                domain: NSFileProviderErrorDomain,
                code: NSFileProviderError.noSuchItem.rawValue
            ))
            return progress
        }

        // TODO Phase D2 : write a PendingFetch JSON to FileProviderBridge.pendingFetchesDir,
        //                 post Darwin Notification "fetch-request", await main app to write
        //                 the fetched file in fetched-files/, then call completionHandler.
        //
        // For Phase D v1, we return an error indicating the IPC is not yet implemented.
        // This is enough for the extension to be visible and selectable in Files.app
        // without crashing — fetching real bytes is the Phase D2 follow-up.

        let error = NSError(
            domain: NSFileProviderErrorDomain,
            code: NSFileProviderError.serverUnreachable.rawValue,
            userInfo: [
                NSLocalizedDescriptionKey: "Fetch IPC pas encore implémenté (Phase D2). Remote=\(decoded.remote), path=\(decoded.path)"
            ]
        )
        completionHandler(nil, nil, error)
        return progress
    }

    // MARK: - Mutations (create / modify / delete)

    public func createItem(basedOn itemTemplate: NSFileProviderItem, fields: NSFileProviderItemFields, contents url: URL?, options: NSFileProviderCreateItemOptions, request: NSFileProviderRequest, completionHandler: @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, Error?) -> Void) -> Progress {
        let progress = Progress(totalUnitCount: 1)
        completionHandler(nil, [], false, NSError(
            domain: NSFileProviderErrorDomain,
            code: NSFileProviderError.serverUnreachable.rawValue,
            userInfo: [NSLocalizedDescriptionKey: "Création depuis Files.app à venir en Phase D2"]
        ))
        return progress
    }

    public func modifyItem(_ item: NSFileProviderItem, baseVersion version: NSFileProviderItemVersion, changedFields: NSFileProviderItemFields, contents newContents: URL?, options: NSFileProviderModifyItemOptions, request: NSFileProviderRequest, completionHandler: @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, Error?) -> Void) -> Progress {
        let progress = Progress(totalUnitCount: 1)
        completionHandler(nil, [], false, NSError(
            domain: NSFileProviderErrorDomain,
            code: NSFileProviderError.serverUnreachable.rawValue,
            userInfo: [NSLocalizedDescriptionKey: "Modification depuis Files.app à venir en Phase D2"]
        ))
        return progress
    }

    public func deleteItem(identifier: NSFileProviderItemIdentifier, baseVersion version: NSFileProviderItemVersion, options: NSFileProviderDeleteItemOptions, request: NSFileProviderRequest, completionHandler: @escaping (Error?) -> Void) -> Progress {
        let progress = Progress(totalUnitCount: 1)
        completionHandler(NSError(
            domain: NSFileProviderErrorDomain,
            code: NSFileProviderError.serverUnreachable.rawValue,
            userInfo: [NSLocalizedDescriptionKey: "Suppression depuis Files.app à venir en Phase D2"]
        ))
        return progress
    }
}
