//
//  AppNotifications.swift
//  Rclone GUI
//
//  App-wide notifications used to refresh long-lived SwiftUI tabs after
//  configuration changes.
//

import Foundation

extension Notification.Name {
    static let rcloneConfigurationDidChange = Notification.Name("com.rougetet.rclone-gui.configuration-did-change")
    static let ghostVaultDidChange = Notification.Name("com.rougetet.rclone-gui.ghost-vault-did-change")
}
