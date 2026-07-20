//
//  AppNotifications.swift
//  Rclone GUI
//
//  App-wide notifications used to refresh long-lived SwiftUI tabs after
//  configuration changes.
//

import Foundation

extension Notification.Name {
    nonisolated static let rcloneConfigurationDidChange = Notification.Name("com.rougetet.rclone-gui.configuration-did-change")
    nonisolated static let ghostVaultDidChange = Notification.Name("com.rougetet.rclone-gui.ghost-vault-did-change")
}
