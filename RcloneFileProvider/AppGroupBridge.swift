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
import FileProvider

public enum FileProviderBridge {
    public static let appGroupIdentifier = "group.com.rougetet.rclone-gui"

    public static var containerURL: URL {
        if let url = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) {
            return url
        }

        if let support = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) {
            return support
        }

        return URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "RcloneFileProvider", directoryHint: .isDirectory)
    }

    public static var keychainAccessGroup: String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "RcloneKeychainAccessGroup") as? String,
              !value.isEmpty,
              !value.contains("$(") else {
            return nil
        }
        return value
    }

    public static var manifestURL: URL {
        containerURL.appending(path: "manifest", directoryHint: .isDirectory)
                    .appending(path: "remotes.json")
    }

    public static var folderManifestsDir: URL {
        containerURL
            .appending(path: "manifest", directoryHint: .isDirectory)
            .appending(path: "folders", directoryHint: .isDirectory)
    }

    public static func folderManifestURL(remote: String, path: String) -> URL {
        let key = "\(remote):\(path)"
        let safe = key.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? UUID().uuidString
        return folderManifestsDir.appending(path: safe).appendingPathExtension("json")
    }

    public static var pendingFetchesDir: URL {
        containerURL.appending(path: "pending-fetches", directoryHint: .isDirectory)
    }

    public static func pendingFetchURL(requestID: String) -> URL {
        pendingFetchesDir.appending(path: requestID).appendingPathExtension("json")
    }

    public static var fetchedFilesDir: URL {
        containerURL.appending(path: "fetched-files", directoryHint: .isDirectory)
    }

    public static var streamingURLsDir: URL {
        containerURL.appending(path: "streaming-urls", directoryHint: .isDirectory)
    }

    public static func streamingURLFile(remote: String, path: String) -> URL {
        let key = "\(remote):\(path)"
        let safe = key.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? UUID().uuidString
        return streamingURLsDir.appending(path: safe).appendingPathExtension("json")
    }

    public static var diagnosticsURL: URL {
        containerURL
            .appending(path: "FileProvider", directoryHint: .isDirectory)
            .appending(path: "diagnostics.log")
    }

    public static let notificationFetchRequest = "com.rougetet.rclone-gui.fp.fetch-request"
    public static let notificationFetchReady = "com.rougetet.rclone-gui.fp.fetch-ready"
    public static let notificationRefresh = "com.rougetet.rclone-gui.fp.refresh"

    /// Poste une notification Darwin cross-process (extension ↔ app principale).
    public static func postDarwinNotification(_ name: String) {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterPostNotification(
            center,
            CFNotificationName(name as CFString),
            nil,
            nil,
            true
        )
    }

    /// Délègue le téléchargement à l'app principale via App Group + Darwin notification.
    /// Une .appex iOS est limitée en mémoire (~256 Mo) et le combo Go runtime + librclone
    /// + déchiffrement crypt fait jetsam. L'app principale (1.5 Go RAM) gère ça sans souci.
    /// Polling de la destination toutes les 250ms jusqu'à apparition (ou timeout).
    public static func requestFetchViaMainApp(
        requestID: String,
        remote: String,
        path: String,
        destination: URL,
        timeout: TimeInterval
    ) async throws {
        try ensureDirectoriesExist()
        // Nettoyage défensif au cas où un fichier de précédente exécution traîne.
        try? FileManager.default.removeItem(at: destination)

        let pending = PendingFetch(
            requestID: requestID,
            remote: remote,
            path: path,
            destPath: destination.path,
            createdAt: .now
        )
        let pendingURL = pendingFetchURL(requestID: requestID)
        let data = try JSONEncoder().encode(pending)
        try data.write(to: pendingURL, options: [.atomic])

        appendDiagnostic("ipc fetch request id=\(requestID) remote=\(remote) path=\(path)")
        postDarwinNotification(notificationFetchRequest)

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            try Task.checkCancellation()
            if FileManager.default.fileExists(atPath: destination.path) {
                appendDiagnostic("ipc fetch ready id=\(requestID)")
                try? FileManager.default.removeItem(at: pendingURL)
                return
            }

            // L'app principale écrit aussi un .error sibling si elle échoue.
            let errorURL = pendingURL.appendingPathExtension("error")
            if let errorData = try? Data(contentsOf: errorURL),
               let message = String(data: errorData, encoding: .utf8) {
                appendDiagnostic("ipc fetch error id=\(requestID) message=\(message)")
                try? FileManager.default.removeItem(at: pendingURL)
                try? FileManager.default.removeItem(at: errorURL)
                throw NSError(
                    domain: NSFileProviderErrorDomain,
                    code: NSFileProviderError.serverUnreachable.rawValue,
                    userInfo: [NSLocalizedDescriptionKey: message]
                )
            }

            try? await Task.sleep(for: .milliseconds(250))
        }

        try? FileManager.default.removeItem(at: pendingURL)
        appendDiagnostic("ipc fetch timeout id=\(requestID)")
        throw NSError(
            domain: NSFileProviderErrorDomain,
            code: NSFileProviderError.serverUnreachable.rawValue,
            userInfo: [NSLocalizedDescriptionKey: "Lancez Rclone GUI puis réessayez (l'app n'est pas active)."]
        )
    }

    public static func ensureDirectoriesExist() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: containerURL.appending(path: "manifest"), withIntermediateDirectories: true)
        try fm.createDirectory(at: folderManifestsDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: pendingFetchesDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: fetchedFilesDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: streamingURLsDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: diagnosticsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    }

    public static func appendDiagnostic(_ message: String) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let line = "\(formatter.string(from: Date())) [INFO] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }

        do {
            try ensureDirectoriesExist()
            if FileManager.default.fileExists(atPath: diagnosticsURL.path) {
                let handle = try FileHandle(forWritingTo: diagnosticsURL)
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                try handle.close()
            } else {
                try data.write(to: diagnosticsURL, options: [.atomic])
            }
        } catch {
            // Last-resort debug path. Avoid throwing from FileProvider callbacks.
            NSLog("Rclone GUI FileProvider diagnostic write failed: %@", error.localizedDescription)
        }
    }

    /// Demande à l'app principale de démarrer (ou réutiliser) un serveur HTTP
    /// loopback rclone pour ce remote+path. Retourne l'URL+token via App Group.
    /// Cache : si une session récente existe déjà (<10min), on la réutilise sans IPC.
    public static func requestStreamURLViaMainApp(
        remote: String,
        path: String,
        timeout: TimeInterval
    ) async throws -> StreamSessionInfo {
        try ensureDirectoriesExist()

        let urlFile = streamingURLFile(remote: remote, path: path)

        if let existing = readStreamSession(at: urlFile),
           existing.createdAt.timeIntervalSinceNow > -600 {
            return existing
        }

        let requestID = UUID().uuidString
        let pending = PendingFetch(
            requestID: requestID,
            remote: remote,
            path: path,
            destPath: urlFile.path,
            createdAt: .now,
            kind: "stream-url"
        )
        let pendingURL = pendingFetchURL(requestID: requestID)
        let data = try JSONEncoder().encode(pending)
        try data.write(to: pendingURL, options: [.atomic])

        appendDiagnostic("ipc stream request id=\(requestID) remote=\(remote) path=\(path)")
        postDarwinNotification(notificationFetchRequest)

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            try Task.checkCancellation()

            if let session = readStreamSession(at: urlFile),
               session.createdAt.timeIntervalSinceNow > -600 {
                appendDiagnostic("ipc stream ready id=\(requestID) sid=\(session.sessionID)")
                try? FileManager.default.removeItem(at: pendingURL)
                return session
            }

            let errorURL = pendingURL.appendingPathExtension("error")
            if let errorData = try? Data(contentsOf: errorURL),
               let message = String(data: errorData, encoding: .utf8) {
                appendDiagnostic("ipc stream error id=\(requestID) message=\(message)")
                try? FileManager.default.removeItem(at: pendingURL)
                try? FileManager.default.removeItem(at: errorURL)
                throw NSError(
                    domain: NSFileProviderErrorDomain,
                    code: NSFileProviderError.serverUnreachable.rawValue,
                    userInfo: [NSLocalizedDescriptionKey: message]
                )
            }

            try? await Task.sleep(for: .milliseconds(150))
        }

        try? FileManager.default.removeItem(at: pendingURL)
        appendDiagnostic("ipc stream timeout id=\(requestID)")
        throw NSError(
            domain: NSFileProviderErrorDomain,
            code: NSFileProviderError.serverUnreachable.rawValue,
            userInfo: [NSLocalizedDescriptionKey: "Lancez Rclone GUI puis réessayez (streaming indisponible)."]
        )
    }

    private static func readStreamSession(at url: URL) -> StreamSessionInfo? {
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let session = try? JSONDecoder().decode(StreamSessionInfo.self, from: data) else {
            return nil
        }
        return session
    }

    /// Demande à l'app principale de lister ce dossier remote et d'écrire son
    /// folder manifest dans App Group. L'extension polle l'apparition du
    /// manifest. Évite d'appeler RcloneProviderClient.list dans la .appex
    /// (Go runtime + crypt → jetsam OOM sur les gros dossiers).
    public static func requestFolderManifestViaMainApp(
        remote: String,
        path: String,
        timeout: TimeInterval
    ) async throws {
        try ensureDirectoriesExist()
        let manifestURL = folderManifestURL(remote: remote, path: path)
        // Mtime min : si le manifest existe déjà mais est ancien (>10s), on le
        // considère comme stale et redemande pour le rafraîchir. iOS s'attend
        // à du contenu vivant.
        let staleThreshold: TimeInterval = 10
        if let attrs = try? FileManager.default.attributesOfItem(atPath: manifestURL.path),
           let mtime = attrs[.modificationDate] as? Date,
           mtime.timeIntervalSinceNow > -staleThreshold {
            return
        }

        let requestID = UUID().uuidString
        let pending = PendingFetch(
            requestID: requestID,
            remote: remote,
            path: path,
            destPath: manifestURL.path,
            createdAt: .now,
            kind: "list"
        )
        let pendingURL = pendingFetchURL(requestID: requestID)
        let data = try JSONEncoder().encode(pending)
        try data.write(to: pendingURL, options: [.atomic])

        appendDiagnostic("ipc list request id=\(requestID) remote=\(remote) path=\(path)")
        postDarwinNotification(notificationFetchRequest)

        let deadline = Date().addingTimeInterval(timeout)
        let startTime = Date()
        while Date() < deadline {
            try Task.checkCancellation()

            if let attrs = try? FileManager.default.attributesOfItem(atPath: manifestURL.path),
               let mtime = attrs[.modificationDate] as? Date,
               mtime > startTime {
                appendDiagnostic("ipc list ready id=\(requestID)")
                try? FileManager.default.removeItem(at: pendingURL)
                return
            }

            let errorURL = pendingURL.appendingPathExtension("error")
            if let errorData = try? Data(contentsOf: errorURL),
               let message = String(data: errorData, encoding: .utf8) {
                appendDiagnostic("ipc list error id=\(requestID) message=\(message)")
                try? FileManager.default.removeItem(at: pendingURL)
                try? FileManager.default.removeItem(at: errorURL)
                throw NSError(
                    domain: NSFileProviderErrorDomain,
                    code: NSFileProviderError.serverUnreachable.rawValue,
                    userInfo: [NSLocalizedDescriptionKey: message]
                )
            }

            try? await Task.sleep(for: .milliseconds(200))
        }

        try? FileManager.default.removeItem(at: pendingURL)
        appendDiagnostic("ipc list timeout id=\(requestID)")
        throw NSError(
            domain: NSFileProviderErrorDomain,
            code: NSFileProviderError.serverUnreachable.rawValue,
            userInfo: [NSLocalizedDescriptionKey: "Lancez Rclone GUI puis réessayez (listing indisponible)."]
        )
    }
}

public struct RemoteManifestEntry: Codable, Sendable {
    public let name: String
    public let type: String
    public let isCrypt: Bool
}

public struct FolderManifestEntry: Codable, Sendable {
    public let path: String
    public let name: String
    public let isDirectory: Bool
    public let size: Int64
    public let modTime: Date
    public let mimeType: String?
}

public struct PendingFetch: Codable, Sendable {
    public let requestID: String
    public let remote: String
    public let path: String
    public let destPath: String
    public let createdAt: Date
    /// "full" (default) = download le fichier complet vers destPath.
    /// "stream-url" = démarre un serveur HTTP loopback côté app principale et
    /// écrit l'URL+token dans <AppGroup>/streaming-urls/<key>.json.
    public let kind: String?

    public init(requestID: String, remote: String, path: String, destPath: String, createdAt: Date, kind: String? = "full") {
        self.requestID = requestID
        self.remote = remote
        self.path = path
        self.destPath = destPath
        self.createdAt = createdAt
        self.kind = kind
    }
}

/// Description du serveur HTTP loopback démarré par l'app principale pour un
/// (remote, path). Sérialisée dans <AppGroup>/streaming-urls/<key>.json.
public struct StreamSessionInfo: Codable, Sendable {
    public let sessionID: String
    public let url: String
    public let createdAt: Date

    public init(sessionID: String, url: String, createdAt: Date) {
        self.sessionID = sessionID
        self.url = url
        self.createdAt = createdAt
    }
}
