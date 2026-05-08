//
//  AppGroupBridge.swift
//  Rclone GUI — FileProvider Extension
//
//  Constants and IPC helpers shared between the extension and the main
//  app via the App Group container.
//
//  IPC contract (Phase D v1):
//
//  Manifest of remotes (written by main app):
//      <container>/manifest/remotes.json
//          [
//              { "name": "r2-vitalys", "type": "s3", "isCrypt": false },
//              ...
//          ]
//
//  Pending fetches (written by extension, fulfilled by main app):
//      <container>/pending-fetches/<itemIdentifier>.json
//          { "remote": "r2-vitalys", "path": "Movies/four-lions-2010.mp4",
//            "destPath": "/.../FetchedFiles/<random>.mp4" }
//
//  Fetched files (written by main app, consumed by extension):
//      <container>/fetched-files/<random>.mp4
//
//  Darwin notifications:
//      "com.rougetet.rclone-gui.fp.fetch-request" — extension → main
//      "com.rougetet.rclone-gui.fp.fetch-ready"   — main → extension
//      "com.rougetet.rclone-gui.fp.refresh"       — main → extension (for signalEnumerator)
//

import Foundation

public enum FileProviderBridge {
    public static let appGroupIdentifier = "group.com.rougetet.rclone-gui"

    public static var containerURL: URL {
        guard let url = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else {
            fatalError("App Group container '\(appGroupIdentifier)' not accessible.")
        }
        return url
    }

    public static var manifestURL: URL {
        containerURL.appending(path: "manifest", directoryHint: .isDirectory)
                    .appending(path: "remotes.json")
    }

    public static var pendingFetchesDir: URL {
        containerURL.appending(path: "pending-fetches", directoryHint: .isDirectory)
    }

    public static var fetchedFilesDir: URL {
        containerURL.appending(path: "fetched-files", directoryHint: .isDirectory)
    }

    public static let notificationFetchRequest = "com.rougetet.rclone-gui.fp.fetch-request"
    public static let notificationFetchReady = "com.rougetet.rclone-gui.fp.fetch-ready"
    public static let notificationRefresh = "com.rougetet.rclone-gui.fp.refresh"

    public static func ensureDirectoriesExist() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: containerURL.appending(path: "manifest"), withIntermediateDirectories: true)
        try fm.createDirectory(at: pendingFetchesDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: fetchedFilesDir, withIntermediateDirectories: true)
    }
}

public struct RemoteManifestEntry: Codable, Sendable {
    public let name: String
    public let type: String
    public let isCrypt: Bool
}

public struct PendingFetch: Codable, Sendable {
    public let remote: String
    public let path: String
    public let destPath: String
    public let createdAt: Date
}
