//
//  RcloneEnumerator.swift
//  Rclone GUI — FileProvider Extension
//
//  Lists items for the requested container (root → list of remotes ;
//  remote → top-level folders ; folder → sub-items).
//
//  Phase D v1 scope: enumerate from the manifest written by the main
//  app at FileProviderBridge.manifestURL. For sub-folders, the
//  extension defers to the main app via Darwin Notification + a
//  pending-fetch JSON file (not implemented end-to-end here — the
//  enumerator returns an empty list with a TODO comment).
//

import Foundation
import FileProvider

public final class RcloneEnumerator: NSObject, NSFileProviderEnumerator {

    let identifier: NSFileProviderItemIdentifier

    init(identifier: NSFileProviderItemIdentifier) {
        self.identifier = identifier
        super.init()
    }

    public func invalidate() {}

    public func enumerateItems(for observer: NSFileProviderEnumerationObserver, startingAt page: NSFileProviderPage) {
        if identifier == NSFileProviderItemIdentifier.rootContainer {
            // Root → list of remotes
            let remotes = loadRemotesManifest()
            let items: [RcloneItem] = remotes.map { remote in
                RcloneItem(
                    id: RcloneItem.identifier(remote: remote.name, path: ""),
                    parentID: NSFileProviderItemIdentifier.rootContainer,
                    displayName: remote.name,
                    isDirectory: true,
                    size: 0,
                    modTime: Date.distantPast
                )
            }
            observer.didEnumerate(items)
            observer.finishEnumerating(upTo: nil)
            return
        }

        // Sub-folder → defer to main app
        // TODO Phase D2 : write a "list-request" JSON in the App Group + post Darwin Notification,
        //                 wait for the main app to drop a "list-response" JSON, then return items.
        observer.didEnumerate([])
        observer.finishEnumerating(upTo: nil)
    }

    public func enumerateChanges(for observer: NSFileProviderChangeObserver, from anchor: NSFileProviderSyncAnchor) {
        // No incremental updates yet — main app calls signalEnumerator(for:) which makes
        // iOS retry enumerateItems instead.
        observer.finishEnumeratingChanges(upTo: anchor, moreComing: false)
    }

    public func currentSyncAnchor(completionHandler: @escaping (NSFileProviderSyncAnchor?) -> Void) {
        completionHandler(nil)
    }

    // MARK: - Manifest loading

    private func loadRemotesManifest() -> [RemoteManifestEntry] {
        let url = FileProviderBridge.manifestURL
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode([RemoteManifestEntry].self, from: data)
        } catch {
            return []
        }
    }
}
