//
//  RcloneGUIIntents.swift
//  Rclone GUI — App Intents (iOS Shortcuts)
//
//  Phase E v1 minimum — three intents :
//    - OpenRemoteIntent     : "Ouvrir <remote> dans Rclone GUI"
//    - DownloadFileIntent   : "Télécharger <path> depuis <remote>"
//    - ListRemotesIntent    : "Liste mes remotes rclone"
//
//  Phase E2 : OpenRemoteIntent deep-links directly into the remote's folder,
//  and UploadFileIntent uploads a file from Shortcuts/Share Sheet.
//

import AppIntents
import Foundation

extension Notification.Name {
    /// Posté par OpenRemoteIntent ; observé par MainTabView pour naviguer
    /// directement vers le dossier racine du remote demandé.
    static let rgOpenRemote = Notification.Name("com.rougetet.rclone-gui.openRemote")
}

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
        AppShortcut(
            intent: RunPhotoSyncIntent(),
            phrases: [
                "Sauvegarder mes photos avec \(.applicationName)",
                "Lancer la sauvegarde photos \(.applicationName)",
            ],
            shortTitle: "Sauvegarder mes photos",
            systemImageName: "photo.on.rectangle.angled"
        )
        AppShortcut(
            intent: PauseTransfersIntent(),
            phrases: [
                "Mettre en pause les transferts \(.applicationName)",
            ],
            shortTitle: "Pause des transferts",
            systemImageName: "pause.circle.fill"
        )
        AppShortcut(
            intent: ResumeTransfersIntent(),
            phrases: [
                "Reprendre les transferts \(.applicationName)",
            ],
            shortTitle: "Reprendre les transferts",
            systemImageName: "play.circle.fill"
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
        // Phase E2 : deep-link réel — on poste une notification que MainTabView
        // intercepte pour basculer sur l'onglet Fichiers et pousser le dossier
        // racine du remote dans la pile de navigation.
        NotificationCenter.default.post(
            name: .rgOpenRemote,
            object: nil,
            userInfo: ["remote": remoteName]
        )
        return .result(dialog: "Ouverture de \(remoteName)…")
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

// MARK: - Upload file

@available(iOS 17.0, *)
public struct UploadFileIntent: AppIntent {
    public static let title: LocalizedStringResource = "Téléverser un fichier"
    public static let description = IntentDescription(
        "Téléverse un fichier vers un remote rclone (depuis Raccourcis ou la feuille de partage)."
    )

    @Parameter(title: "Fichier")
    public var file: IntentFile

    @Parameter(title: "Remote")
    public var remoteName: String

    @Parameter(title: "Dossier de destination", default: "")
    public var destinationFolder: String

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        // Matérialise le fichier fourni par Raccourcis dans un emplacement
        // local temporaire avant de l'enquêter pour upload.
        let tmpDir = FileManager.default.temporaryDirectory
            .appending(path: "intent-uploads", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        let filename = file.filename
        let localURL = tmpDir.appending(path: filename)
        try? FileManager.default.removeItem(at: localURL)
        try file.data.write(to: localURL)

        let folder = destinationFolder.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        let destPath = folder.isEmpty ? filename : "\(folder)/\(filename)"
        try await TransferQueue.shared.enqueueUpload(
            local: localURL,
            remote: remoteName,
            path: destPath
        )
        return .result(dialog: "Téléversement de \(filename) vers \(remoteName) lancé.")
    }
}
