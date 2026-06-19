//
//  FlowIntents.swift
//  Rclone GUI — AppIntents (Flows / automatisations locales)
//
//  Intents « Flows » (RG-2) : briques d'automatisation 100 % locales,
//  composables dans l'app Raccourcis et par Siri. Aucune dépendance serveur.
//
//    - RunPhotoSyncIntent   : « Sauvegarder mes photos » (lance PhotoSync)
//    - BackupFolderIntent   : « Sauvegarder un dossier » (sync remote → remote)
//    - PauseTransfersIntent  : met en pause tous les transferts
//    - ResumeTransfersIntent : reprend tous les transferts
//
//  Ces intents sont `AppIntent` (découvrables dans Raccourcis), à la
//  différence des LiveActivityIntent de PhotoSyncIntents.swift qui pilotent
//  l'Island.
//

import AppIntents
import Foundation

// MARK: - Sauvegarder mes photos

@available(iOS 17.0, *)
public struct RunPhotoSyncIntent: AppIntent {
    public static let title: LocalizedStringResource = "Sauvegarder mes photos"
    public static let description = IntentDescription(
        "Lance une sauvegarde de la photothèque via PhotoSync. Idéal pour une automatisation (ex. tous les soirs, sur secteur)."
    )

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let summary = await PhotoSyncService.shared.startFullSync()
        let done = summary.completedCount
        let failed = summary.failedCount
        let msg = failed > 0
            ? "Sauvegarde photos lancée — \(done) envoyée(s), \(failed) à revoir."
            : "Sauvegarde photos lancée — \(done) élément(s) traité(s)."
        return .result(dialog: IntentDialog(stringLiteral: msg))
    }
}

// MARK: - Sauvegarder un dossier (remote → remote)

@available(iOS 17.0, *)
public struct BackupFolderIntent: AppIntent {
    public static let title: LocalizedStringResource = "Sauvegarder un dossier"
    public static let description = IntentDescription(
        "Synchronise un dossier d'un remote vers un autre (sauvegarde rclone). Le dossier de destination est mis à jour pour refléter la source."
    )

    @Parameter(title: "Remote source")
    public var sourceRemote: String

    @Parameter(title: "Dossier source", default: "")
    public var sourcePath: String

    @Parameter(title: "Remote destination")
    public var destinationRemote: String

    @Parameter(title: "Dossier destination", default: "")
    public var destinationPath: String

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let src = sourcePath.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        let dst = destinationPath.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        let entry = RemoteEntryDTO(
            pathInRemote: src,
            name: src.isEmpty ? sourceRemote : (src as NSString).lastPathComponent,
            isDirectory: true,
            size: 0,
            modTime: Date(),
            mimeType: nil,
            hashMD5: nil,
            hashSHA1: nil
        )
        try await TransferQueue.shared.enqueueRemoteTransfer(
            kind: .sync,
            srcRemote: sourceRemote,
            entry: entry,
            dstRemote: destinationRemote,
            dstPath: dst
        )
        return .result(dialog: "Sauvegarde de \(sourceRemote):\(src) vers \(destinationRemote):\(dst) lancée.")
    }
}

// MARK: - Pause / reprise globale des transferts

@available(iOS 17.0, *)
public struct PauseTransfersIntent: AppIntent {
    public static let title: LocalizedStringResource = "Mettre les transferts en pause"
    public static let description = IntentDescription(
        "Met en pause tous les transferts en cours (utile pour économiser les données ou la batterie)."
    )

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        try await TransferQueue.shared.pauseAllTransfers()
        return .result(dialog: "Transferts mis en pause.")
    }
}

@available(iOS 17.0, *)
public struct ResumeTransfersIntent: AppIntent {
    public static let title: LocalizedStringResource = "Reprendre les transferts"
    public static let description = IntentDescription(
        "Reprend tous les transferts mis en pause."
    )

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let mbps = UserDefaults.standard.double(forKey: "transfer.bandwidthLimitMBps")
        let bytesPerSecond = Int64(mbps * 1024 * 1024)
        try await TransferQueue.shared.resumeAllTransfers(bytesPerSecond: bytesPerSecond)
        return .result(dialog: "Transferts repris.")
    }
}
