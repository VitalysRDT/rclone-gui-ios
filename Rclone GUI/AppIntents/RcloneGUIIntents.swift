//
//  RcloneGUIIntents.swift
//  Rclone GUI — App Intents (iOS Shortcuts)
//
//  Phase E v1 minimum — three intents :
//    - OpenRemoteIntent     : "Ouvrir <remote> dans Rclone GUI"
//    - DownloadFileIntent   : "Télécharger <path> depuis <remote>"
//    - ListRemotesIntent    : "Liste mes remotes rclone"
//
//  Phase E2 will add UploadFileIntent + parameter resolvers (interactive
//  remote/path picker via AppEntity).
//

import AppIntents
import Foundation

@available(iOS 17.0, *)
public struct RcloneGUIShortcuts: AppShortcutsProvider {
    public static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ListRemotesIntent(),
            phrases: [
                "Liste mes remotes \(.applicationName)",
                "Affiche les remotes \(.applicationName)",
            ],
            shortTitle: "Mes remotes",
            systemImageName: "externaldrive"
        )
        AppShortcut(
            intent: OpenRemoteIntent(),
            phrases: [
                "Ouvrir un remote \(.applicationName)",
            ],
            shortTitle: "Ouvrir un remote",
            systemImageName: "externaldrive.fill"
        )
    }
}

// MARK: - List remotes

@available(iOS 17.0, *)
public struct ListRemotesIntent: AppIntent {
    public static let title: LocalizedStringResource = "Liste les remotes rclone"
    public static let description = IntentDescription(
        "Renvoie la liste des remotes définis dans la configuration."
    )

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult & ReturnsValue<[String]> & ProvidesDialog {
        let names = try await RemoteService.shared.listRemoteNames()
        let summary = names.isEmpty
            ? "Aucun remote n'est configuré."
            : "\(names.count) remote(s) : \(names.joined(separator: ", "))"
        return .result(value: names, dialog: IntentDialog(stringLiteral: summary))
    }
}

// MARK: - Open remote

@available(iOS 17.0, *)
public struct OpenRemoteIntent: AppIntent {
    public static let title: LocalizedStringResource = "Ouvrir un remote"
    public static let description = IntentDescription(
        "Ouvre un remote rclone dans Rclone GUI."
    )
    public static let openAppWhenRun: Bool = true

    @Parameter(title: "Remote")
    public var remoteName: String

    public init() {}
    public init(remoteName: String) { self.remoteName = remoteName }

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        // Phase E1 minimum : the app is foregrounded and the user is told
        // which remote to navigate to. Phase E2 will deep-link directly
        // to FolderView via NavigationStack programmatic push.
        return .result(dialog: "Ouvre l'onglet Remotes pour aller dans \(remoteName).")
    }
}

// MARK: - Download file

@available(iOS 17.0, *)
public struct DownloadFileIntent: AppIntent {
    public static let title: LocalizedStringResource = "Télécharger un fichier"
    public static let description = IntentDescription(
        "Télécharge un fichier depuis un remote rclone vers le stockage local."
    )

    @Parameter(title: "Remote")
    public var remoteName: String

    @Parameter(title: "Chemin")
    public var pathInRemote: String

    public init() {}
    public init(remoteName: String, pathInRemote: String) {
        self.remoteName = remoteName
        self.pathInRemote = pathInRemote
    }

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let docs = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let basename = (pathInRemote as NSString).lastPathComponent
        let dst = docs
            .appending(path: "Downloads", directoryHint: .isDirectory)
            .appending(path: remoteName, directoryHint: .isDirectory)
            .appending(path: basename)
        try FileManager.default.createDirectory(
            at: dst.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try await TransferQueue.shared.enqueueDownload(
            remote: remoteName,
            path: pathInRemote,
            to: dst
        )
        return .result(dialog: "Téléchargement de \(basename) lancé.")
    }
}
