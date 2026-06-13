//
//  AppGroup.swift
//  Rclone GUI — Core
//
//  Constants for the App Group container shared between the main app
//  and the FileProvider extension. The container holds:
//    - The encrypted rclone.conf blob
//    - SwiftData store (browse cache, transfers, manifests)
//    - Thumbnail cache directory
//
//  IMPORTANT: the App Group identifier MUST match the one declared in
//  Rclone_GUI.entitlements AND in the FileProvider extension's
//  entitlements (when the extension target is created).
//

import Foundation

public enum AppGroup {
    /// Shared App Group identifier. Update both this constant and the
    /// `com.apple.security.application-groups` entitlement together.
    public nonisolated static let identifier = "group.com.rougetet.rclone-gui"

    /// Keychain access group for credentials shared between app and extension.
    public nonisolated static var keychainAccessGroup: String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "RcloneKeychainAccessGroup") as? String,
              !value.isEmpty,
              !value.contains("$(") else {
            return nil
        }
        return value
    }

    /// URL of the App Group container.
    /// Falls back to the app's own `Application Support` directory if the
    /// entitlement is not provisioned (free Apple ID, App Group not declared
    /// in the developer portal, fresh device with stale profile, etc.).
    /// Side effect of the fallback: the FileProvider extension can no longer
    /// share data with the main app — already documented as a Phase D v1
    /// limitation in PHASE-D.md.
    public nonisolated static var containerURL: URL {
        if let url = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: identifier
        ) {
            return url
        }

        let fm = FileManager.default
        if let support = try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) {
            return support
        }
        // Last-resort fallback if even Application Support is unavailable
        // (extremely unlikely but keeps us crash-free).
        return URL(fileURLWithPath: NSHomeDirectory())
            .appending(path: "Library/Application Support", directoryHint: .isDirectory)
    }

    /// True when the real App Group container is being used (i.e. the
    /// entitlement is provisioned). Useful for diagnostics in Settings.
    public nonisolated static var isAppGroupProvisioned: Bool {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) != nil
    }

    /// Path inside the App Group where the encrypted rclone.conf is stored.
    public nonisolated static var rcloneConfURL: URL {
        containerURL.appending(path: "rclone.conf.enc")
    }

    /// Path inside the App Group for the SwiftData store.
    public nonisolated static var swiftDataStoreURL: URL {
        applicationSupportURL.appending(path: "RcloneGUI.store")
    }

    /// Path for the thumbnail cache.
    public nonisolated static var thumbnailCacheURL: URL {
        containerURL.appending(path: "Thumbnails", directoryHint: .isDirectory)
    }

    public nonisolated static var fileProviderDiagnosticsURL: URL {
        containerURL
            .appending(path: "FileProvider", directoryHint: .isDirectory)
            .appending(path: "diagnostics.log")
    }

    /// Path du snapshot d'abonnement partagé. L'app principale l'écrit
    /// après chaque résolution StoreKit ; l'extension FileProvider le lit
    /// au début de chaque opération pour gater l'accès aux remotes.
    public nonisolated static var subscriptionStatusURL: URL {
        containerURL.appending(path: "subscription-status.json")
    }

    /// Écrit atomiquement le snapshot d'abonnement dans l'App Group.
    /// L'extension FileProvider lit ce fichier à chaque entrée publique.
    public nonisolated static func writeSubscription(_ snapshot: SubscriptionSnapshot) throws {
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: subscriptionStatusURL, options: [.atomic])
    }

    /// Lit le snapshot d'abonnement persisté. Retourne nil si le fichier
    /// n'existe pas (1er lancement, jamais authentifié) ou si la lecture
    /// échoue (corruption, format incompatible).
    public nonisolated static func readSubscription() -> SubscriptionSnapshot? {
        guard FileManager.default.fileExists(atPath: subscriptionStatusURL.path),
              let data = try? Data(contentsOf: subscriptionStatusURL),
              let snapshot = try? JSONDecoder().decode(SubscriptionSnapshot.self, from: data) else {
            return nil
        }
        return snapshot
    }

    // MARK: - Coffre-fort (verrous biométriques par remote)

    /// Répertoire des fichiers du coffre-fort partagé avec l'extension.
    public nonisolated static var vaultDir: URL {
        containerURL.appending(path: "vault", directoryHint: .isDirectory)
    }

    /// Liste des remotes protégés par biométrie (JSON `[String]`).
    /// Source de vérité unique : l'extension FileProvider ne peut pas lire
    /// le store SwiftData, donc l'état du coffre-fort vit dans ce fichier.
    public nonisolated static var vaultLockedRemotesURL: URL {
        vaultDir.appending(path: "locked-remotes.json")
    }

    /// Déverrouillages actifs (JSON `[name: epochSeconds]`). Écrit par l'app
    /// principale après une authentification biométrique réussie ; l'extension
    /// le lit et ignore les entrées expirées.
    public nonisolated static var vaultUnlocksURL: URL {
        vaultDir.appending(path: "unlocks.json")
    }

    public nonisolated static var pendingFetchesDir: URL {
        containerURL.appending(path: "pending-fetches", directoryHint: .isDirectory)
    }

    public nonisolated static var streamingURLsDir: URL {
        containerURL.appending(path: "streaming-urls", directoryHint: .isDirectory)
    }

    public nonisolated static func streamingURLFile(remote: String, path: String) -> URL {
        let key = "\(remote):\(path)"
        let safe = key.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? UUID().uuidString
        return streamingURLsDir.appending(path: safe).appendingPathExtension("json")
    }

    /// Nom de la Darwin notification postée par l'extension FileProvider
    /// pour signaler une nouvelle demande de fetch à l'app principale.
    public static let fileProviderFetchRequestNotification = "com.rougetet.rclone-gui.fp.fetch-request"

    /// Writable Application Support directory inside the group container.
    /// CoreData/SwiftData will not reliably create this nested directory on
    /// iOS when the store lives in an App Group, so the app creates it before
    /// building the ModelContainer.
    public nonisolated static var applicationSupportURL: URL {
        containerURL
            .appending(path: "Library", directoryHint: .isDirectory)
            .appending(path: "Application Support", directoryHint: .isDirectory)
    }

    /// A safe writable cwd for Go/rclone. Avoid using the app bundle path:
    /// gomobile/cgo can receive it URL-escaped when the app product name has
    /// spaces, which triggers a noisy `chdir(...%20...) failed` at launch.
    public nonisolated static var runtimeWorkingDirectoryURL: URL {
        containerURL
            .appending(path: "Library", directoryHint: .isDirectory)
            .appending(path: "RcloneRuntime", directoryHint: .isDirectory)
    }

    @discardableResult
    public nonisolated static func prepareSharedContainerLayout() throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: applicationSupportURL, withIntermediateDirectories: true)
        try fm.createDirectory(at: thumbnailCacheURL, withIntermediateDirectories: true)
        try fm.createDirectory(at: runtimeWorkingDirectoryURL, withIntermediateDirectories: true)
        try fm.createDirectory(at: pendingFetchesDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: streamingURLsDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: vaultDir, withIntermediateDirectories: true)
        try fm.createDirectory(
            at: fileProviderDiagnosticsURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        return swiftDataStoreURL
    }
}

/// Mirror du PendingFetch défini côté extension (RcloneFileProvider/AppGroupBridge.swift).
/// Codé identique pour assurer le decoding cross-target via JSON. Les deux structs
/// doivent rester synchronisées (mêmes champs, mêmes noms).
public struct AppGroupPendingFetch: Codable, Sendable {
    public let requestID: String
    public let remote: String
    public let path: String
    public let destPath: String
    public let createdAt: Date
    public let kind: String?
}

/// Mirror du FetchStatus défini côté extension. Écrit dans
/// pending-fetches/<requestID>.json.status pendant les materializations Files.app.
public struct AppGroupFetchStatus: Codable, Sendable {
    public let stage: String
    public let jobID: Int?
    public let bytesTransferred: Int64
    public let bytesTotal: Int64
    public let updatedAt: Date
    public let message: String?

    public init(
        stage: String,
        jobID: Int?,
        bytesTransferred: Int64,
        bytesTotal: Int64,
        updatedAt: Date,
        message: String? = nil
    ) {
        self.stage = stage
        self.jobID = jobID
        self.bytesTransferred = bytesTransferred
        self.bytesTotal = bytesTotal
        self.updatedAt = updatedAt
        self.message = message
    }
}

/// Mirror du StreamSessionInfo défini côté extension. Sérialisé dans
/// streaming-urls/<key>.json par FileProviderFetchService.
public struct AppGroupStreamSessionInfo: Codable, Sendable {
    public let sessionID: String
    public let url: String
    public let createdAt: Date

    public init(sessionID: String, url: String, createdAt: Date) {
        self.sessionID = sessionID
        self.url = url
        self.createdAt = createdAt
    }
}
