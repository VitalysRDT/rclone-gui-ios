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
    public static let identifier = "group.com.rougetet.rclone-gui"

    /// Keychain access group for credentials shared between app and extension.
    public static let keychainAccessGroup = "$(AppIdentifierPrefix)com.rougetet.rclone-gui"

    /// URL of the App Group container, fatal-trap if entitlement is missing.
    public static var containerURL: URL {
        guard let url = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: identifier
        ) else {
            fatalError("App Group container '\(identifier)' is not accessible. Verify entitlements + provisioning profile.")
        }
        return url
    }

    /// Path inside the App Group where the encrypted rclone.conf is stored.
    public static var rcloneConfURL: URL {
        containerURL.appending(path: "rclone.conf.enc")
    }

    /// Path inside the App Group for the SwiftData store.
    public static var swiftDataStoreURL: URL {
        containerURL.appending(path: "RcloneGUI.sqlite")
    }

    /// Path for the thumbnail cache.
    public static var thumbnailCacheURL: URL {
        containerURL.appending(path: "Thumbnails", directoryHint: .isDirectory)
    }
}
