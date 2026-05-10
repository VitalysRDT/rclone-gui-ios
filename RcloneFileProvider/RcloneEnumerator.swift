//
//  RcloneEnumerator.swift
//  Rclone GUI — FileProvider Extension
//
//  Lists items for the requested container (root → list of remotes ;
//  remote → top-level folders ; folder → sub-items).
//
//  iOS 16+ requires NSFileProviderReplicatedExtension to:
//   - return an itemVersion on every NSFileProviderItem
//   - return a sync anchor that changes when the catalog changes
//   - implement enumerateChanges so that didUpdate(items) is fired when
//     the anchor moves forward.
//  Without these three, iOS Files never re-fetches the root and shows
//  "Contenu indisponible".
//

import Foundation
import FileProvider
import OSLog

private let fileProviderLog = Logger(
    subsystem: "com.rougetet.rclone-gui",
    category: "fileprovider"
)

public final class RcloneEnumerator: NSObject, NSFileProviderEnumerator {

    let identifier: NSFileProviderItemIdentifier

    init(identifier: NSFileProviderItemIdentifier) {
        self.identifier = identifier
        super.init()
    }

    public func invalidate() {}

    // MARK: - Items enumeration

    public func enumerateItems(for observer: NSFileProviderEnumerationObserver, startingAt page: NSFileProviderPage) {
        let itemIdentifier = identifier

        do {
            try FileProviderBridge.ensureDirectoriesExist()
        } catch {
            fileProviderLog.error("prepare directories failed: \(error.localizedDescription, privacy: .public)")
            FileProviderBridge.appendDiagnostic("prepare directories failed: \(error.localizedDescription)")
        }

        if identifier == .trashContainer {
            observer.didEnumerate([])
            observer.finishEnumerating(upTo: nil)
            return
        }

        if identifier == .workingSet {
            // iOS Files se sert du working set pour décider d'afficher quelque chose
            // à la racine. Renvoyer [] revient à dire "rien à montrer". On y met
            // donc la liste des remotes (= les "documents récents" virtuels).
            let manifestRemotes = loadRemotesManifest()
            let items = manifestRemotes.map { remoteItem(name: $0.name) }
            FileProviderBridge.appendDiagnostic("enumerate workingSet count=\(items.count)")
            observer.didEnumerate(items)
            observer.finishEnumerating(upTo: nil)
            return
        }

        if identifier == NSFileProviderItemIdentifier.rootContainer {
            Task {
                let manifestRemotes = loadRemotesManifest()
                if !manifestRemotes.isEmpty {
                    fileProviderLog.debug("enumerating root from manifest: \(manifestRemotes.count, privacy: .public) remotes")
                    FileProviderBridge.appendDiagnostic("enumerate root from manifest count=\(manifestRemotes.count)")
                    observer.didEnumerate(items(for: manifestRemotes))
                    observer.finishEnumerating(upTo: nil)
                    return
                }

                do {
                    let names = try await RcloneProviderClient.shared.listRemoteNames()
                    fileProviderLog.debug("enumerating root from rclone: \(names.count, privacy: .public) remotes")
                    FileProviderBridge.appendDiagnostic("enumerate root from rclone count=\(names.count)")
                    let items = names.map { remoteItem(name: $0) }
                    observer.didEnumerate(items)
                    observer.finishEnumerating(upTo: nil)
                } catch {
                    fileProviderLog.error("enumerating root failed: \(error.localizedDescription, privacy: .public)")
                    FileProviderBridge.appendDiagnostic("enumerate root failed: \(error.localizedDescription)")
                    observer.didEnumerate([])
                    observer.finishEnumerating(upTo: nil)
                }
            }
            return
        }

        guard let decoded = RcloneItem.decode(itemIdentifier) else {
            fileProviderLog.error("invalid item identifier: \(itemIdentifier.rawValue, privacy: .public)")
            FileProviderBridge.appendDiagnostic("invalid item identifier: \(itemIdentifier.rawValue)")
            observer.finishEnumeratingWithError(NSError(
                domain: NSFileProviderErrorDomain,
                code: NSFileProviderError.noSuchItem.rawValue
            ))
            return
        }

        Task {
            if let manifestEntries = loadFolderManifestIfAvailable(remote: decoded.remote, path: decoded.path) {
                fileProviderLog.debug("enumerating \(decoded.remote, privacy: .public):\(decoded.path, privacy: .public) from manifest: \(manifestEntries.count, privacy: .public) items")
                FileProviderBridge.appendDiagnostic("enumerate \(decoded.remote):\(decoded.path) from manifest count=\(manifestEntries.count)")
                observer.didEnumerate(items(for: manifestEntries, parentIdentifier: itemIdentifier, remote: decoded.remote))
                observer.finishEnumerating(upTo: nil)
                return
            }

            // Manifest absent : déléguer à l'app principale (Go runtime + crypt
            // dans la .appex jetsam-able sur les gros dossiers crypt). Une fois
            // le manifest écrit, on le relit ici et on l'enumere.
            do {
                try await FileProviderBridge.requestFolderManifestViaMainApp(
                    remote: decoded.remote,
                    path: decoded.path,
                    timeout: 60
                )
                if let manifestEntries = loadFolderManifestIfAvailable(remote: decoded.remote, path: decoded.path) {
                    FileProviderBridge.appendDiagnostic("enumerate \(decoded.remote):\(decoded.path) from manifest (via IPC) count=\(manifestEntries.count)")
                    observer.didEnumerate(items(for: manifestEntries, parentIdentifier: itemIdentifier, remote: decoded.remote))
                    observer.finishEnumerating(upTo: nil)
                    return
                }
                FileProviderBridge.appendDiagnostic("enumerate \(decoded.remote):\(decoded.path) IPC done but manifest missing")
                observer.didEnumerate([])
                observer.finishEnumerating(upTo: nil)
            } catch {
                fileProviderLog.error("enumerating \(decoded.remote, privacy: .public):\(decoded.path, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                FileProviderBridge.appendDiagnostic("enumerate \(decoded.remote):\(decoded.path) failed: \(error.localizedDescription)")
                observer.finishEnumeratingWithError(error)
            }
        }
    }

    // MARK: - Changes enumeration

    public func enumerateChanges(for observer: NSFileProviderChangeObserver, from anchor: NSFileProviderSyncAnchor) {
        let current = computeAnchor()
        let received = anchor.rawValue
        FileProviderBridge.appendDiagnostic("enumerateChanges id=\(identifier.rawValue) sameAnchor=\(current == received)")

        // Anchor inchangé → rien à signaler.
        if current == received {
            observer.finishEnumeratingChanges(upTo: NSFileProviderSyncAnchor(current), moreComing: false)
            return
        }

        // Anchor différent → recharger les items pour ce conteneur et les
        // notifier comme mises à jour. C'est ce qui sort iOS de l'état
        // "rien n'a changé, j'affiche le cache vide".
        let updates = currentItems()
        FileProviderBridge.appendDiagnostic("enumerateChanges didUpdate count=\(updates.count) for id=\(identifier.rawValue)")
        if !updates.isEmpty {
            observer.didUpdate(updates)
        }
        observer.finishEnumeratingChanges(upTo: NSFileProviderSyncAnchor(current), moreComing: false)
    }

    public func currentSyncAnchor(completionHandler: @escaping (NSFileProviderSyncAnchor?) -> Void) {
        let anchor = computeAnchor()
        FileProviderBridge.appendDiagnostic("currentSyncAnchor id=\(identifier.rawValue) anchor=\(String(data: anchor, encoding: .utf8) ?? "?")")
        completionHandler(NSFileProviderSyncAnchor(anchor))
    }

    // MARK: - Sync anchor

    /// Anchor qui évolue dès que le manifest est réécrit. Combine la mtime
    /// du remotes.json et celle du folder manifest concerné (si applicable).
    private func computeAnchor() -> Data {
        var components: [String] = ["v2"]

        if let mtime = fileMTime(at: FileProviderBridge.manifestURL) {
            components.append("rm:\(Int(mtime.timeIntervalSinceReferenceDate * 1000))")
        }

        if identifier != NSFileProviderItemIdentifier.rootContainer,
           identifier != .workingSet,
           identifier != .trashContainer,
           let decoded = RcloneItem.decode(identifier) {
            let folderURL = FileProviderBridge.folderManifestURL(remote: decoded.remote, path: decoded.path)
            if let mtime = fileMTime(at: folderURL) {
                components.append("fm:\(Int(mtime.timeIntervalSinceReferenceDate * 1000))")
            }
        }

        return Data(components.joined(separator: "|").utf8)
    }

    private func fileMTime(at url: URL) -> Date? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let date = attrs[.modificationDate] as? Date else {
            return nil
        }
        return date
    }

    /// Items courants pour ce conteneur, depuis le manifest disque.
    private func currentItems() -> [RcloneItem] {
        if identifier == NSFileProviderItemIdentifier.rootContainer || identifier == .workingSet {
            return loadRemotesManifest().map { remoteItem(name: $0.name) }
        }
        if identifier == .trashContainer { return [] }
        guard let decoded = RcloneItem.decode(identifier) else { return [] }
        guard let entries = loadFolderManifestIfAvailable(remote: decoded.remote, path: decoded.path) else {
            return []
        }
        return items(for: entries, parentIdentifier: identifier, remote: decoded.remote)
    }

    // MARK: - Manifest loading

    private func loadRemotesManifest() -> [RemoteManifestEntry] {
        let url = FileProviderBridge.manifestURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            fileProviderLog.debug("remotes manifest missing at \(url.path, privacy: .public)")
            FileProviderBridge.appendDiagnostic("remotes manifest missing path=\(url.path)")
            return []
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode([RemoteManifestEntry].self, from: data)
        } catch {
            fileProviderLog.error("remotes manifest decode failed: \(error.localizedDescription, privacy: .public)")
            FileProviderBridge.appendDiagnostic("remotes manifest decode failed: \(error.localizedDescription)")
            return []
        }
    }

    private func loadFolderManifestIfAvailable(remote: String, path: String) -> [FolderManifestEntry]? {
        let url = FileProviderBridge.folderManifestURL(remote: remote, path: path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            fileProviderLog.debug("folder manifest missing for \(remote, privacy: .public):\(path, privacy: .public) at \(url.path, privacy: .public)")
            FileProviderBridge.appendDiagnostic("folder manifest missing remote=\(remote) path=\(path)")
            return nil
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode([FolderManifestEntry].self, from: data)
        } catch {
            fileProviderLog.error("folder manifest decode failed for \(remote, privacy: .public):\(path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            FileProviderBridge.appendDiagnostic("folder manifest decode failed remote=\(remote) path=\(path) error=\(error.localizedDescription)")
            return nil
        }
    }

    private func items(for remotes: [RemoteManifestEntry]) -> [RcloneItem] {
        remotes.map { remoteItem(name: $0.name) }
    }

    private func remoteItem(name: String) -> RcloneItem {
        RcloneItem(
            id: RcloneItem.identifier(remote: name, path: ""),
            parentID: NSFileProviderItemIdentifier.rootContainer,
            displayName: name,
            isDirectory: true,
            size: 0,
            modTime: Date.distantPast
        )
    }

    private func items(
        for entries: [FPRemoteEntry],
        parentIdentifier: NSFileProviderItemIdentifier,
        remote: String
    ) -> [RcloneItem] {
        entries.map { entry in
            RcloneItem(
                id: RcloneItem.identifier(remote: remote, path: entry.path),
                parentID: parentIdentifier,
                displayName: entry.name,
                isDirectory: entry.isDirectory,
                size: entry.size,
                modTime: entry.modTime
            )
        }
    }

    private func items(
        for entries: [FolderManifestEntry],
        parentIdentifier: NSFileProviderItemIdentifier,
        remote: String
    ) -> [RcloneItem] {
        entries.map { entry in
            RcloneItem(
                id: RcloneItem.identifier(remote: remote, path: entry.path),
                parentID: parentIdentifier,
                displayName: entry.name,
                isDirectory: entry.isDirectory,
                size: entry.size,
                modTime: entry.modTime
            )
        }
    }
}
