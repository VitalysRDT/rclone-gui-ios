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
            destinationPath: localURL.path
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

    public func enqueueUpload(local: URL, remote: String, path: String) async throws {
        let transfer = Transfer(
            kind: .upload,
            sourcePath: local.path,
            destinationRemote: remote,
            destinationPath: path
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
                        transfer.status = .completed
                        await LogService.shared.log(
                            .info,
                            category: "transfer",
                            message: "✅ \(finalKind.rawValue) terminé : \(finalSrc)"
                        )
                    } else {
                        transfer.status = .failed
                        transfer.lastError = status.error ?? "Échec inconnu"
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
        // We do best-effort matching.
        for transfer in running {
            let targetName = (transfer.destinationPath as NSString).lastPathComponent
            if let match = stats.transferring.first(where: { $0.name == targetName }) {
                transfer.bytesTransferred = match.bytesTransferred
                transfer.bytesTotal = max(match.bytesTotal, transfer.bytesTotal)
            }
        }
        try? modelContext.save()
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
}
