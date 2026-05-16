//
//  TransferQueue.swift
//  Rclone GUI — Services
//
//  MainActor orchestrator. Persists Transfer rows via SwiftData,
//  dispatches the rclone async jobs, and polls progress until done.
//
//  Wired up from `Rclone_GUIApp` via `TransferQueue.shared.attach(modelContext:)`
//  on first appearance of the root view.
//
//  Phase C scope:
//    - download / upload / delete / move / rename
//    - polling loop (~500 ms) merging job/status + core/stats
//    - cold-start replay (resume interrupted transfers)
//
//  Phase C non-scope (deferred to D/E):
//    - URLSession-direct path for HTTP backends (S3/R2/Bunny)
//    - Live Activities
//    - Bandwidth limiting
//

import Foundation
import SwiftData

@MainActor
public final class TransferQueue {
    public static let shared = TransferQueue()

    private init() {}

    // MARK: - State

    private var modelContext: ModelContext?
    private var pollTasks: [Int: Task<Void, Never>] = [:]
    private var statsTask: Task<Void, Never>?

    // MARK: - Setup

    /// Attach the SwiftData model context. Idempotent; safe to call multiple
    /// times (e.g. on every scene activation).
    public func attach(modelContext: ModelContext) {
        guard self.modelContext !== modelContext else { return }
        self.modelContext = modelContext
        Task { await replayInterrupted() }
        startStatsPolling()
    }

    // MARK: - Enqueue API

    public func enqueueDownload(remote: String, path: String, to localURL: URL) async throws {
        let parent = localURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)

        let transfer = Transfer(
            kind: .download,
            sourceRemote: remote,
            sourcePath: path,
            destinationPath: localURL.path,
            displayName: localURL.lastPathComponent,
            sourceKind: .remote
        )
        transfer.status = .running
        modelContext?.insert(transfer)
        try modelContext?.save()

        let jobID = try await TransferService.shared.copyFileAsync(
            srcFs: "\(remote):",
            srcPath: path,
            dstFs: parent.path,
            dstPath: localURL.lastPathComponent
        )
        transfer.jobID = jobID
        try modelContext?.save()
        startPolling(transfer)
    }

    @discardableResult
    public func enqueueDownloadBatch(
        remote: String,
        entries: [RemoteEntryDTO],
        to directory: URL,
        conflictPolicy: LocalConflictPolicy
    ) async throws -> TransferBatch {
        let batch = TransferBatch(
            title: entries.count == 1 ? "Téléchargement \(entries[0].name)" : "Téléchargement de \(entries.count) éléments",
            kind: .download,
            totalItems: entries.count
        )
        batch.status = .running
        modelContext?.insert(batch)
        try modelContext?.save()

        for entry in entries {
            try await enqueueDownload(
                remote: remote,
                entry: entry,
                to: directory,
                conflictPolicy: conflictPolicy,
                batchID: batch.id
            )
        }
        return batch
    }

    public func enqueueDownload(
        remote: String,
        entry: RemoteEntryDTO,
        to directory: URL,
        conflictPolicy: LocalConflictPolicy = .keepBoth,
        batchID: String? = nil
    ) async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let requestedURL = directory.appending(path: entry.name, directoryHint: entry.isDirectory ? .isDirectory : .notDirectory)
        guard let destinationURL = try LocalFileConflictResolver.destination(for: requestedURL, policy: conflictPolicy) else {
            await LogService.shared.log(.info, category: "transfer", message: "Téléchargement ignoré : \(remote):\(entry.pathInRemote)")
            return
        }

        if entry.isDirectory {
            try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)
            let transfer = Transfer(
                kind: .download,
                sourceRemote: remote,
                sourcePath: entry.pathInRemote,
                destinationPath: destinationURL.path,
                batchID: batchID,
                relativePath: entry.name,
                displayName: entry.name,
                sourceKind: .remote
            )
            transfer.status = .running
            modelContext?.insert(transfer)
            try modelContext?.save()

            let jobID = try await TransferService.shared.copyDirAsync(
                srcFs: "\(remote):\(entry.pathInRemote)",
                dstFs: destinationURL.path
            )
            transfer.jobID = jobID
            try modelContext?.save()
            startPolling(transfer)
        } else {
            let transfer = Transfer(
                kind: .download,
                sourceRemote: remote,
                sourcePath: entry.pathInRemote,
                destinationPath: destinationURL.path,
                batchID: batchID,
                relativePath: entry.name,
                displayName: entry.name,
                sourceKind: .remote,
                bytesTotal: entry.size
            )
            transfer.status = .running
            modelContext?.insert(transfer)
            try modelContext?.save()

            let parent = destinationURL.deletingLastPathComponent()
            let jobID = try await TransferService.shared.copyFileAsync(
                srcFs: "\(remote):",
                srcPath: entry.pathInRemote,
                dstFs: parent.path,
                dstPath: destinationURL.lastPathComponent
            )
            transfer.jobID = jobID
            try modelContext?.save()
            startPolling(transfer)
        }
    }

    public func enqueueUpload(
        local: URL,
        remote: String,
        path: String,
        batchID: String? = nil,
        relativePath: String? = nil,
        sourceKind: TransferSourceKind = .localFile
    ) async throws {
        let transfer = Transfer(
            kind: .upload,
            sourcePath: local.path,
            destinationRemote: remote,
            destinationPath: path,
            batchID: batchID,
            relativePath: relativePath,
            displayName: local.lastPathComponent,
            sourceKind: sourceKind,
            bytesTotal: fileSize(at: local)
        )
        transfer.status = .running
        modelContext?.insert(transfer)
        try modelContext?.save()

        let jobID = try await TransferService.shared.copyFileAsync(
            srcFs: local.deletingLastPathComponent().path,
            srcPath: local.lastPathComponent,
            dstFs: "\(remote):",
            dstPath: path
        )
        transfer.jobID = jobID
        try modelContext?.save()
        startPolling(transfer)
    }

    @discardableResult
    public func enqueueUploadBatch(
        localURLs: [URL],
        remote: String,
        destinationFolder: String,
        sourceKind: TransferSourceKind = .localFile
    ) async throws -> TransferBatch {
        let batch = TransferBatch(
            title: localURLs.count == 1 ? "Upload \(localURLs[0].lastPathComponent)" : "Upload de \(localURLs.count) éléments",
            kind: .upload,
            totalItems: localURLs.count
        )
        batch.status = .running
        modelContext?.insert(batch)
        try modelContext?.save()

        for localURL in localURLs {
            let didStart = localURL.startAccessingSecurityScopedResource()
            defer { if didStart { localURL.stopAccessingSecurityScopedResource() } }

            if isDirectory(localURL) {
                let dstPath = joinedRemotePath(destinationFolder, localURL.lastPathComponent)
                try await enqueueUploadFolder(
                    localFolder: localURL,
                    remote: remote,
                    destinationFolder: dstPath,
                    batchID: batch.id,
                    sourceKind: sourceKind
                )
            } else {
                let dstPath = joinedRemotePath(destinationFolder, localURL.lastPathComponent)
                try await enqueueUpload(
                    local: localURL,
                    remote: remote,
                    path: dstPath,
                    batchID: batch.id,
                    relativePath: localURL.lastPathComponent,
                    sourceKind: sourceKind
                )
            }
        }
        return batch
    }

    public func enqueueUploadFolder(
        localFolder: URL,
        remote: String,
        destinationFolder: String,
        batchID: String? = nil,
        sourceKind: TransferSourceKind = .localFolder
    ) async throws {
        let transfer = Transfer(
            kind: .upload,
            sourcePath: localFolder.path,
            destinationRemote: remote,
            destinationPath: destinationFolder,
            batchID: batchID,
            relativePath: localFolder.lastPathComponent,
            displayName: localFolder.lastPathComponent,
            sourceKind: sourceKind,
            bytesTotal: directorySize(at: localFolder)
        )
        transfer.status = .running
        modelContext?.insert(transfer)
        try modelContext?.save()

        let jobID = try await TransferService.shared.copyDirAsync(
            srcFs: localFolder.path,
            dstFs: "\(remote):\(destinationFolder)"
        )
        transfer.jobID = jobID
        try modelContext?.save()
        startPolling(transfer)
    }

    public func enqueueDelete(remote: String, path: String, isDirectory: Bool) async throws {
        let transfer = Transfer(
            kind: .delete,
            sourceRemote: remote,
            sourcePath: path,
            destinationPath: ""
        )
        transfer.status = .running
        modelContext?.insert(transfer)
        try modelContext?.save()

        let jobID: Int
        if isDirectory {
            jobID = try await TransferService.shared.purgeAsync(remote: remote, path: path)
        } else {
            jobID = try await TransferService.shared.deleteFileAsync(remote: remote, path: path)
        }
        transfer.jobID = jobID
        try modelContext?.save()
        startPolling(transfer)
    }

    /// Soft-delete: move the item to the per-remote trash folder via TrashService.
    /// The original path is recorded so the user can restore it within the
    /// retention window (30 days by default).
    ///
    /// `sizeBytes` is best-effort metadata for the trash UI. Pass -1 if unknown.
    public func enqueueTrash(
        remote: String,
        path: String,
        name: String,
        isDirectory: Bool,
        sizeBytes: Int64
    ) async throws {
        let transfer = Transfer(
            kind: .delete,
            sourceRemote: remote,
            sourcePath: path,
            destinationPath: "",
            displayName: "Corbeille — \(name)"
        )
        transfer.status = .running
        modelContext?.insert(transfer)
        try modelContext?.save()

        do {
            _ = try await TrashService.shared.moveToTrash(
                remote: remote,
                path: path,
                name: name,
                isDirectory: isDirectory,
                sizeBytes: sizeBytes
            )
            transfer.status = .completed
            transfer.finishedAt = .now
            try modelContext?.save()
        } catch {
            transfer.status = .failed
            transfer.lastError = error.localizedDescription
            transfer.finishedAt = .now
            try? modelContext?.save()
            throw error
        }
    }

    public func enqueueRename(remote: String, oldPath: String, newPath: String) async throws {
        let transfer = Transfer(
            kind: .move,
            sourceRemote: remote,
            sourcePath: oldPath,
            destinationRemote: remote,
            destinationPath: newPath
        )
        transfer.status = .running
        modelContext?.insert(transfer)
        try modelContext?.save()

        let jobID = try await TransferService.shared.renameAsync(remote: remote, oldPath: oldPath, newPath: newPath)
        transfer.jobID = jobID
        try modelContext?.save()
        startPolling(transfer)
    }

    public func enqueueMove(srcRemote: String, srcPath: String, dstRemote: String, dstPath: String) async throws {
        let transfer = Transfer(
            kind: .move,
            sourceRemote: srcRemote,
            sourcePath: srcPath,
            destinationRemote: dstRemote,
            destinationPath: dstPath
        )
        transfer.status = .running
        modelContext?.insert(transfer)
        try modelContext?.save()

        let jobID = try await TransferService.shared.moveFileAsync(
            srcFs: "\(srcRemote):",
            srcPath: srcPath,
            dstFs: "\(dstRemote):",
            dstPath: dstPath
        )
        transfer.jobID = jobID
        try modelContext?.save()
        startPolling(transfer)
    }

    @discardableResult
    public func enqueueRemoteTransferBatch(
        kind: TransferKind,
        srcRemote: String,
        entries: [RemoteEntryDTO],
        dstRemote: String,
        dstFolder: String
    ) async throws -> TransferBatch {
        let batch = TransferBatch(
            title: remoteBatchTitle(kind: kind, count: entries.count),
            kind: kind,
            totalItems: entries.count
        )
        batch.status = .running
        modelContext?.insert(batch)
        try modelContext?.save()

        for entry in entries {
            try await enqueueRemoteTransfer(
                kind: kind,
                srcRemote: srcRemote,
                entry: entry,
                dstRemote: dstRemote,
                dstPath: joinedRemotePath(dstFolder, entry.name),
                batchID: batch.id
            )
        }

        return batch
    }

    public func enqueueRemoteTransfer(
        kind: TransferKind,
        srcRemote: String,
        entry: RemoteEntryDTO,
        dstRemote: String,
        dstPath: String,
        batchID: String? = nil
    ) async throws {
        precondition(kind == .copy || kind == .move || kind == .sync)

        let transfer = Transfer(
            kind: kind,
            sourceRemote: srcRemote,
            sourcePath: entry.pathInRemote,
            destinationRemote: dstRemote,
            destinationPath: dstPath,
            batchID: batchID,
            relativePath: entry.name,
            displayName: entry.name,
            sourceKind: .remote,
            bytesTotal: entry.size
        )
        transfer.isDirectoryTransfer = entry.isDirectory
        transfer.status = .running
        modelContext?.insert(transfer)
        try modelContext?.save()

        let jobID: Int
        switch (kind, entry.isDirectory) {
        case (.copy, false), (.sync, false):
            jobID = try await TransferService.shared.copyFileAsync(
                srcFs: "\(srcRemote):",
                srcPath: entry.pathInRemote,
                dstFs: "\(dstRemote):",
                dstPath: dstPath
            )
        case (.copy, true):
            jobID = try await TransferService.shared.copyDirAsync(
                srcFs: "\(srcRemote):\(entry.pathInRemote)",
                dstFs: "\(dstRemote):\(dstPath)"
            )
        case (.move, false):
            jobID = try await TransferService.shared.moveFileAsync(
                srcFs: "\(srcRemote):",
                srcPath: entry.pathInRemote,
                dstFs: "\(dstRemote):",
                dstPath: dstPath
            )
        case (.move, true):
            jobID = try await TransferService.shared.moveDirAsync(
                srcFs: "\(srcRemote):\(entry.pathInRemote)",
                dstFs: "\(dstRemote):\(dstPath)"
            )
        case (.sync, true):
            jobID = try await TransferService.shared.syncDirAsync(
                srcFs: "\(srcRemote):\(entry.pathInRemote)",
                dstFs: "\(dstRemote):\(dstPath)"
            )
        default:
            throw RcloneError.engineNotAvailable("Type de transfert remote non supporté : \(kind.rawValue)")
        }

        transfer.jobID = jobID
        try modelContext?.save()
        startPolling(transfer)
    }

    public func cancel(_ transfer: Transfer) async {
        if let id = transfer.jobID {
            pollTasks[id]?.cancel()
            pollTasks[id] = nil
            try? await TransferService.shared.stopJob(jobID: id)
        }
        transfer.status = .failed
        transfer.lastError = "Annulé par l'utilisateur"
        transfer.finishedAt = .now
        try? modelContext?.save()
    }

    /// Retry a failed transfer by re-enqueuing an equivalent operation. The
    /// failed Transfer record stays in the store as audit trail; a brand new
    /// Transfer is created via the regular enqueue path. Not every kind can
    /// be retried automatically — uploads need the original local file (often
    /// deleted by then), and deletes don't carry the isDirectory hint.
    public func retry(_ transfer: Transfer) async throws {
        switch transfer.kind {
        case .download:
            guard let srcRemote = transfer.sourceRemote, !transfer.destinationPath.isEmpty else {
                throw TransferQueueError.cannotRetry("Métadonnées du téléchargement incomplètes.")
            }
            try await enqueueDownload(
                remote: srcRemote,
                path: transfer.sourcePath,
                to: URL(fileURLWithPath: transfer.destinationPath)
            )

        case .copy, .move, .sync:
            guard let srcRemote = transfer.sourceRemote,
                  let dstRemote = transfer.destinationRemote else {
                throw TransferQueueError.cannotRetry("Source ou destination manquante.")
            }
            // Use the persisted isDirectoryTransfer flag set by enqueueRemoteTransfer.
            // Pre-Sprint-3 records have nil → treat as file (the old default behavior).
            // For records where we know it's a directory, we route through the right
            // rclone RPC (sync/copy or sync/move instead of operations/copyfile).
            let synthetic = RemoteEntryDTO(
                pathInRemote: transfer.sourcePath,
                name: transfer.displayName ?? (transfer.sourcePath as NSString).lastPathComponent,
                isDirectory: transfer.isDirectoryTransfer ?? false,
                size: transfer.bytesTotal,
                modTime: .now,
                mimeType: nil,
                hashMD5: nil,
                hashSHA1: nil
            )
            try await enqueueRemoteTransfer(
                kind: transfer.kind,
                srcRemote: srcRemote,
                entry: synthetic,
                dstRemote: dstRemote,
                dstPath: transfer.destinationPath
            )

        case .upload:
            throw TransferQueueError.cannotRetry(
                "Le retry d'un upload n'est pas supporté — relancez l'upload depuis le dossier d'origine."
            )

        case .delete:
            throw TransferQueueError.cannotRetry(
                "Le retry d'une suppression n'est pas supporté — réessayez depuis le dossier."
            )
        }

        // Annotate the original transfer so the UI can collapse old failures.
        transfer.lastError = (transfer.lastError ?? "Échec") + " — retry lancé"
        try? modelContext?.save()
    }

    /// Persisted across launches so that the UI and rclone agree on the
    /// pause state after a cold start. rclone forgets its bwlimit between
    /// runs, so we replay this flag at boot via `restoreFromPersistedState`.
    public static let persistedPauseKey = "transfer.isPausedGlobally"

    /// Pause every running rclone job by lowering the global bandwidth ceiling
    /// to 1 byte/second (rclone treats rate "0" as "unlimited"). Idempotent.
    public func pauseAllTransfers() async throws {
        try await TransferService.shared.pauseAllTransfers()
        isPausedGlobally = true
        UserDefaults.standard.set(true, forKey: Self.persistedPauseKey)
    }

    /// Restore the user's preferred bandwidth ceiling and resume progress.
    /// `bytesPerSecond == 0` means "no limit" (rate "off").
    public func resumeAllTransfers(bytesPerSecond: Int64) async throws {
        try await TransferService.shared.resumeAllTransfers(bytesPerSecond: bytesPerSecond)
        isPausedGlobally = false
        UserDefaults.standard.set(false, forKey: Self.persistedPauseKey)
    }

    /// Apply the user's bandwidth setting without toggling pause state.
    /// Called at app launch and whenever the user changes the slider in
    /// the Performance settings.
    public func applyBandwidthLimit(bytesPerSecond: Int64) async throws {
        try await TransferService.shared.setBandwidthLimit(bytesPerSecond: bytesPerSecond)
    }

    // MARK: - Throttle pendant l'activité utilisateur

    /// Limite temporaire appliquée pendant que l'utilisateur navigue dans
    /// l'app. 512 KB/s : assez bas pour libérer le réseau et le radio
    /// cellulaire le temps d'un geste, assez haut pour que la sync ne se
    /// fige pas. La pleine vitesse est restaurée dès que l'utilisateur
    /// arrête d'interagir (cf. UserActivityMonitor.inactivityThreshold).
    private static let userActivityThrottleBytes: Int64 = 524_288

    /// Compteur de bypass : TransfersView l'incrémente à .onAppear et le
    /// décrémente à .onDisappear pour ne PAS throttler quand l'utilisateur
    /// regarde explicitement les transferts (il veut voir le débit réel).
    private var userActivityBypassCount: Int = 0
    private var isThrottlingForUserActivity = false

    public func incrementActivityBypass() {
        userActivityBypassCount += 1
        // Re-évalue : si on était en throttle mais bypass demandé, on retire.
        Task { await reevaluateUserActivityThrottle() }
    }

    public func decrementActivityBypass() {
        userActivityBypassCount = max(0, userActivityBypassCount - 1)
        Task { await reevaluateUserActivityThrottle() }
    }

    /// Appelé par UserActivityMonitor (via Notification) quand l'état
    /// d'activité change. Throttle vers 1MB/s pendant la nav, restaure
    /// le ceiling utilisateur après inactivité.
    public func applyThrottleForUserActivity(isActive: Bool, userPreferredBytes: Int64) async {
        let shouldThrottle = isActive
            && !isPausedGlobally
            && userActivityBypassCount == 0
            // Ne throttle que si la valeur normale est >1MB/s (sinon useless)
            && (userPreferredBytes == 0 || userPreferredBytes > Self.userActivityThrottleBytes)

        guard shouldThrottle != isThrottlingForUserActivity else { return }

        do {
            if shouldThrottle {
                try await TransferService.shared.setBandwidthLimit(
                    bytesPerSecond: Self.userActivityThrottleBytes
                )
                isThrottlingForUserActivity = true
            } else {
                try await TransferService.shared.setBandwidthLimit(
                    bytesPerSecond: userPreferredBytes
                )
                isThrottlingForUserActivity = false
            }
        } catch {
            // Best effort : si la RPC bwlimit fail, on log mais on n'altère
            // pas le flag pour qu'un retry futur tente à nouveau.
            await LogService.shared.log(
                .debug,
                category: "transfer",
                message: "Throttle activity échec : \(error.localizedDescription)"
            )
        }
    }

    private func reevaluateUserActivityThrottle() async {
        // Réajuste après changement de bypass count : on relit la prefs
        // depuis UserDefaults et on aligne sur l'état actif courant.
        let mbps = UserDefaults.standard.double(forKey: "transfer.bandwidthLimitMBps")
        let bytes = Int64(mbps * 1024 * 1024)
        let isActive = await UserActivityMonitor.shared.isUserActive
        await applyThrottleForUserActivity(isActive: isActive, userPreferredBytes: bytes)
    }

    /// Cold-start handler: re-applies the persisted pause/bwlimit state to
    /// rclone (which forgot it) and updates the in-memory `isPausedGlobally`
    /// flag so the UI matches the real backend state.
    ///
    /// `bytesPerSecond` is the user's preferred ceiling (0 = unlimited),
    /// read from `@AppStorage("transfer.bandwidthLimitMBps")` by the caller.
    /// Retries with exponential backoff on RPC failure — rclone's Go runtime
    /// may not be listening yet at the moment this is invoked.
    public func restoreFromPersistedState(bytesPerSecond: Int64) async {
        let wasPaused = UserDefaults.standard.bool(forKey: Self.persistedPauseKey)

        // Up to 3 attempts with 0.5s, 1s, 2s backoff covers a slow Go runtime
        // start without making the launch path feel sluggish on a healthy boot.
        let delays: [UInt64] = [500_000_000, 1_000_000_000, 2_000_000_000]
        for (index, delay) in delays.enumerated() {
            do {
                if wasPaused {
                    try await TransferService.shared.pauseAllTransfers()
                    isPausedGlobally = true
                } else {
                    try await TransferService.shared.setBandwidthLimit(bytesPerSecond: bytesPerSecond)
                    isPausedGlobally = false
                }
                if index > 0 {
                    await LogService.shared.log(
                        .info,
                        category: "transfer",
                        message: "Bandwidth/pause state restored after \(index) retry attempt(s)"
                    )
                }
                return
            } catch {
                if index == delays.count - 1 {
                    await LogService.shared.log(
                        .error,
                        category: "transfer",
                        message: "Failed restoring bandwidth/pause after \(delays.count) attempts: \(error.localizedDescription)"
                    )
                    return
                }
                try? await Task.sleep(nanoseconds: delay)
            }
        }
    }

    /// Live state mirrored from `pauseAllTransfers` / `resumeAllTransfers`
    /// and rehydrated by `restoreFromPersistedState` at launch.
    public private(set) var isPausedGlobally: Bool = false

    // MARK: - Polling

    private func startPolling(_ transfer: Transfer) {
        guard let jobID = transfer.jobID else { return }
        let transferID = transfer.id
        let task = Task { [weak self] in
            await self?.pollLoop(transferID: transferID, jobID: jobID)
            return ()
        }
        pollTasks[jobID] = task
    }

    private func pollLoop(transferID: String, jobID: Int) async {
        while !Task.isCancelled {
            do {
                let status = try await TransferService.shared.jobStatus(jobID: jobID)
                let transfer = self.fetchTransfer(id: transferID)
                guard let transfer else {
                    break
                }
                if status.finished {
                    let finalKind = transfer.kind
                    let finalSrc = transfer.sourcePath
                    if status.success {
                        transfer.bytesTransferred = max(transfer.bytesTransferred, transfer.bytesTotal)
                        transfer.status = .completed
                        updateBatch(transfer.batchID, completedDelta: 1, failedDelta: 0)
                        if transfer.sourceKind == .photoLibrary {
                            PhotoSyncService.shared.transferDidFinish(
                                destinationPath: transfer.destinationPath,
                                success: true,
                                error: nil
                            )
                        }
                        await LogService.shared.log(
                            .info,
                            category: "transfer",
                            message: "✅ \(finalKind.rawValue) terminé : \(finalSrc)"
                        )
                    } else {
                        transfer.status = .failed
                        transfer.lastError = status.error ?? "Échec inconnu"
                        updateBatch(transfer.batchID, completedDelta: 0, failedDelta: 1)
                        if transfer.sourceKind == .photoLibrary {
                            PhotoSyncService.shared.transferDidFinish(
                                destinationPath: transfer.destinationPath,
                                success: false,
                                error: transfer.lastError
                            )
                        }
                        await LogService.shared.log(
                            .error,
                            category: "transfer",
                            message: "❌ \(finalKind.rawValue) échoué : \(finalSrc) — \(status.error ?? "raison inconnue")"
                        )
                    }
                    transfer.finishedAt = .now
                    try? modelContext?.save()
                    break
                }
                try? modelContext?.save()
                try await Task.sleep(for: .milliseconds(500))
            } catch is CancellationError {
                break
            } catch {
                let transfer = self.fetchTransfer(id: transferID)
                transfer?.status = .failed
                transfer?.lastError = error.localizedDescription
                transfer?.finishedAt = .now
                updateBatch(transfer?.batchID, completedDelta: 0, failedDelta: transfer == nil ? 0 : 1)
                try? modelContext?.save()
                await LogService.shared.log(
                    .error,
                    category: "transfer",
                    message: "Polling jobID=\(jobID) interrompu : \(error.localizedDescription)"
                )
                break
            }
        }
        pollTasks[jobID] = nil
    }

    private func fetchTransfer(id: String) -> Transfer? {
        guard let modelContext else { return nil }
        let descriptor = FetchDescriptor<Transfer>(
            predicate: #Predicate { $0.id == id }
        )
        return try? modelContext.fetch(descriptor).first
    }

    // MARK: - Stats polling (running transfers progress)

    private func startStatsPolling() {
        guard statsTask == nil else { return }
        statsTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.tickStats()
                try? await Task.sleep(for: .milliseconds(800))
            }
        }
    }

    private func tickStats() async {
        guard let modelContext else { return }
        let descriptor = FetchDescriptor<Transfer>(
            predicate: #Predicate { $0.statusRaw == "running" }
        )
        guard let running = try? modelContext.fetch(descriptor), !running.isEmpty else {
            return
        }
        guard let stats = try? await TransferService.shared.coreStats() else { return }

        // core/stats reports per-file under `transferring`, keyed by the destination basename.
        // We do best-effort matching. Dirty flag : on évite save() si rien
        // n'a changé (épargne ~10ms × 75/min = 750ms CPU/min en idle).
        var didMutate = false
        for transfer in running {
            if let match = stats.transferring.first(where: { statMatchesTransfer($0, transfer: transfer) })
                ?? uniqueSizeFallback(stats: stats, running: running, transfer: transfer)
                ?? singleTransferFallback(stats: stats, running: running) {
                let newBytes = match.bytesTransferred
                let newTotal = max(match.bytesTotal, transfer.bytesTotal)
                if transfer.bytesTransferred != newBytes || transfer.bytesTotal != newTotal {
                    transfer.bytesTransferred = newBytes
                    transfer.bytesTotal = newTotal
                    didMutate = true
                }
            }
        }
        let batchesChanged = updateRunningBatches()
        if didMutate || batchesChanged {
            try? modelContext.save()
        }
    }

    private func statMatchesTransfer(_ stat: CoreStatsDTO.Transferring, transfer: Transfer) -> Bool {
        let statName = stat.name
        let statBase = (statName as NSString).lastPathComponent
        let sourceBase = (transfer.sourcePath as NSString).lastPathComponent
        let destinationBase = (transfer.destinationPath as NSString).lastPathComponent
        let displayName = transfer.displayName ?? ""

        let candidates = [
            transfer.sourcePath,
            transfer.destinationPath,
            sourceBase,
            destinationBase,
            displayName,
        ].filter { !$0.isEmpty }

        return candidates.contains { candidate in
            statName == candidate
                || statBase == candidate
                || statName.hasSuffix("/\(candidate)")
                || candidate.hasSuffix("/\(statName)")
        }
    }

    private func uniqueSizeFallback(
        stats: CoreStatsDTO,
        running: [Transfer],
        transfer: Transfer
    ) -> CoreStatsDTO.Transferring? {
        guard transfer.bytesTotal > 0 else { return nil }
        let sameSizeTransfers = running.filter { $0.bytesTotal == transfer.bytesTotal }
        guard sameSizeTransfers.count == 1 else { return nil }
        let sameSizeStats = stats.transferring.filter { $0.bytesTotal == transfer.bytesTotal }
        guard sameSizeStats.count == 1 else { return nil }
        return sameSizeStats.first
    }

    private func singleTransferFallback(
        stats: CoreStatsDTO,
        running: [Transfer]
    ) -> CoreStatsDTO.Transferring? {
        guard stats.transferring.count == 1, running.count == 1 else { return nil }
        return stats.transferring.first
    }

    // MARK: - Cold start replay

    private func replayInterrupted() async {
        guard let modelContext else { return }
        let descriptor = FetchDescriptor<Transfer>(
            predicate: #Predicate { $0.statusRaw == "running" || $0.statusRaw == "pending" }
        )
        guard let candidates = try? modelContext.fetch(descriptor) else { return }
        for transfer in candidates {
            // For Phase C, we mark them failed and let the user retry manually.
            // Phase E will re-enqueue automatically based on transfer.kind.
            transfer.status = .failed
            transfer.lastError = "Interrompu — relance manuelle requise"
            transfer.finishedAt = .now
        }
        try? modelContext.save()
    }

    // MARK: - Batch helpers

    private func updateBatch(_ batchID: String?, completedDelta: Int, failedDelta: Int) {
        guard let batchID, let batch = fetchBatch(id: batchID) else { return }
        batch.completedItems += completedDelta
        batch.failedItems += failedDelta
        if batch.completedItems + batch.failedItems >= batch.totalItems {
            batch.status = batch.failedItems > 0 ? .failed : .completed
            batch.finishedAt = .now
        }
        try? modelContext?.save()
    }

    /// Renvoie `true` si au moins un champ d'un batch a été modifié, pour
    /// que tickStats puisse skip le save() quand rien n'a bougé.
    @discardableResult
    private func updateRunningBatches() -> Bool {
        guard let modelContext else { return false }
        let descriptor = FetchDescriptor<TransferBatch>(
            predicate: #Predicate { $0.statusRaw == "running" }
        )
        guard let batches = try? modelContext.fetch(descriptor), !batches.isEmpty else { return false }
        var didMutate = false
        for batch in batches {
            let id = batch.id
            let transferDescriptor = FetchDescriptor<Transfer>(
                predicate: #Predicate { $0.batchID == id }
            )
            guard let transfers = try? modelContext.fetch(transferDescriptor) else { continue }
            let total = transfers.reduce(Int64(0)) { $0 + $1.bytesTotal }
            let transferred = transfers.reduce(Int64(0)) { $0 + $1.bytesTransferred }
            if batch.bytesTotal != total || batch.bytesTransferred != transferred {
                batch.bytesTotal = total
                batch.bytesTransferred = transferred
                didMutate = true
            }
        }
        return didMutate
    }

    private func fetchBatch(id: String) -> TransferBatch? {
        guard let modelContext else { return nil }
        let descriptor = FetchDescriptor<TransferBatch>(
            predicate: #Predicate { $0.id == id }
        )
        return try? modelContext.fetch(descriptor).first
    }

    private func joinedRemotePath(_ folder: String, _ name: String) -> String {
        let cleanFolder = folder.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return cleanFolder.isEmpty ? name : "\(cleanFolder)/\(name)"
    }

    private func remoteBatchTitle(kind: TransferKind, count: Int) -> String {
        let action: String
        switch kind {
        case .copy: action = "Copie"
        case .move: action = "Déplacement"
        case .sync: action = "Synchronisation"
        default: action = "Transfert"
        }
        return count == 1 ? "\(action) d'un élément" : "\(action) de \(count) éléments"
    }

    private func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        return isDirectory.boolValue
    }

    private func fileSize(at url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values?.fileSize ?? 0)
    }

    private func directorySize(at url: URL) -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
            if values?.isDirectory != true {
                total += Int64(values?.fileSize ?? 0)
            }
        }
        return total
    }
}

public enum TransferQueueError: LocalizedError, Equatable {
    /// The retry path can't fully reconstruct the original transfer (missing
    /// metadata, unsupported kind). The associated message is shown to the user.
    case cannotRetry(String)

    public var errorDescription: String? {
        switch self {
        case .cannotRetry(let reason):
            return "Retry impossible : \(reason)"
        }
    }
}
