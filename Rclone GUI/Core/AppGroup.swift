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
    public nonisolated static let keychainAccessGroup = "$(AppIdentifierPrefix)com.rougetet.rclone-gui"

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
        containerURL.appending(path: "RcloneGUI.sqlite")
    }

    /// Path for the thumbnail cache.
    public nonisolated static var thumbnailCacheURL: URL {
        containerURL.appending(path: "Thumbnails", directoryHint: .isDirectory)
    }
}
