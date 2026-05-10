//
//  TrashService.swift
//  Rclone GUI — Services
//
//  Soft-delete buffer ("corbeille") for files & folders trashed from the app.
//  Implementation: server-side rename to `<remote>:.rclone-gui-trash/<uuid>/<name>`
//  (one rclone moveto / sync.move call) and a SwiftData TrashEntry for the metadata.
//
//  Why a metadata table instead of just listing the trash folder?
//  - The trash folder lives on the remote, so listing it requires a network call.
//  - On crypt remotes the original filename is encrypted; we'd lose it without metadata.
//  - We track the original parent path so "Restore" puts the file back exactly where it was.
//
//  Default retention is 30 days. Auto-purge is run at app launch via
//  `purgeExpired()`. Permanent delete and "empty trash" are also supported.
//
//  Wired up from `Rclone_GUIApp` via `TrashService.shared.attach(modelContext:)`.
//

import Foundation
import SwiftData

@MainActor
public final class TrashService {
    public static let shared = TrashService()

    /// Folder name used on every remote to hold trashed items. Starts with a dot
    /// so it stays out of the way in raw rclone listings.
    public static let trashRoot = ".rclone-gui-trash"

    /// 30 days, in seconds.
    public static let defaultRetention: TimeInterval = 30 * 24 * 60 * 60

    private init() {}

    private var modelContext: ModelContext?

    public func attach(modelContext: ModelContext) {
        guard self.modelContext !== modelContext else { return }
        self.modelContext = modelContext
    }

    // MARK: - Public API

    /// Move a file or folder to the trash on its remote. Records metadata
    /// so the original location can be restored later.
    /// Throws on rclone failure or if the model context is not attached.
    @discardableResult
    public func moveToTrash(
        remote: String,
        path: String,
        name: String,
        isDirectory: Bool,
        sizeBytes: Int64
    ) async throws -> TrashEntry {
        guard let modelContext else {
            throw TrashError.notAttached
        }

        let id = UUID().uuidString
        // We always put a wrapper folder per item so two trashed files with
        // the same basename don't collide. On crypt remotes this also means
        // the original encrypted name doesn't leak into the trash structure.
        let trashFolder = "\(Self.trashRoot)/\(id)"
        let trashPath = "\(trashFolder)/\(name)"

        // Make sure the wrapper folder exists. mkdir is idempotent on rclone
        // and a no-op on backends that auto-create parents.
        try await TransferService.shared.mkdir(remote: remote, path: trashFolder)

        // Server-side rename. operations/movefile for files, sync/move for folders.
        if isDirectory {
            _ = try await TransferService.shared.moveDirAsync(
                srcFs: "\(remote):\(path)",
                dstFs: "\(remote):\(trashPath)"
            )
        } else {
            _ = try await TransferService.shared.moveFileAsync(
                srcFs: "\(remote):",
                srcPath: path,
                dstFs: "\(remote):",
                dstPath: trashPath
            )
        }

        let entry = TrashEntry(
            id: id,
            originalRemote: remote,
            originalPath: path,
            originalName: name,
            isDirectory: isDirectory,
            sizeBytes: sizeBytes,
            trashPath: trashPath
        )
        modelContext.insert(entry)
        try modelContext.save()

        await LogService.shared.log(
            .info,
            category: "trash",
            message: "Trashed \(remote):\(path) → \(trashPath) (id=\(id))"
        )

        return entry
    }

    /// Move a trashed item back to its original path. Fails if the original
    /// path no longer exists (the parent folder was deleted) — caller should
    /// handle that by offering a destination picker.
    public func restore(_ entry: TrashEntry) async throws {
        guard let modelContext else {
            throw TrashError.notAttached
        }

        if entry.isDirectory {
            _ = try await TransferService.shared.moveDirAsync(
                srcFs: "\(entry.originalRemote):\(entry.trashPath)",
                dstFs: "\(entry.originalRemote):\(entry.originalPath)"
            )
        } else {
            _ = try await TransferService.shared.moveFileAsync(
                srcFs: "\(entry.originalRemote):",
                srcPath: entry.trashPath,
                dstFs: "\(entry.originalRemote):",
                dstPath: entry.originalPath
            )
        }

        // Remove the wrapper folder we created (it's empty after the move).
        let wrapper = (entry.trashPath as NSString).deletingLastPathComponent
        try? await TransferService.shared.purgeAsync(remote: entry.originalRemote, path: wrapper)

        modelContext.delete(entry)
        try modelContext.save()

        await LogService.shared.log(
            .info,
            category: "trash",
            message: "Restored \(entry.originalRemote):\(entry.originalPath) (id=\(entry.id))"
        )
    }

    /// Permanently delete a trashed item.
    public func permanentlyDelete(_ entry: TrashEntry) async throws {
        guard let modelContext else {
            throw TrashError.notAttached
        }

        // Purge the wrapper folder — that takes both the item and its parent.
        let wrapper = (entry.trashPath as NSString).deletingLastPathComponent
        _ = try await TransferService.shared.purgeAsync(remote: entry.originalRemote, path: wrapper)

        modelContext.delete(entry)
        try modelContext.save()

        await LogService.shared.log(
            .info,
            category: "trash",
            message: "Permanently deleted \(entry.originalRemote):\(entry.originalPath) (id=\(entry.id))"
        )
    }

    /// Drop every trash entry whose `expiresAt` is in the past. Returns the
    /// number of items purged. Best-effort: a backend failure on one entry
    /// is logged but does not abort the cleanup of the others.
    @discardableResult
    public func purgeExpired(now: Date = .now) async -> Int {
        guard let modelContext else { return 0 }

        let predicate = #Predicate<TrashEntry> { $0.expiresAt < now }
        let descriptor = FetchDescriptor<TrashEntry>(predicate: predicate)
        let expired: [TrashEntry]
        do {
            expired = try modelContext.fetch(descriptor)
        } catch {
            await LogService.shared.log(
                .error,
                category: "trash",
                message: "Failed fetching expired trash entries: \(error.localizedDescription)"
            )
            return 0
        }

        var purgedCount = 0
        for entry in expired {
            do {
                try await permanentlyDelete(entry)
                purgedCount += 1
            } catch {
                await LogService.shared.log(
                    .error,
                    category: "trash",
                    message: "Failed purging expired entry \(entry.id): \(error.localizedDescription)"
                )
            }
        }
        if purgedCount > 0 {
            await LogService.shared.log(
                .info,
                category: "trash",
                message: "Auto-purged \(purgedCount) expired trash entries"
            )
        }
        return purgedCount
    }

    /// Permanently delete every trashed item. Returns the count effectively purged.
    @discardableResult
    public func emptyAll() async -> Int {
        guard let modelContext else { return 0 }
        let descriptor = FetchDescriptor<TrashEntry>()
        let all: [TrashEntry]
        do {
            all = try modelContext.fetch(descriptor)
        } catch {
            return 0
        }
        var purgedCount = 0
        for entry in all {
            do {
                try await permanentlyDelete(entry)
                purgedCount += 1
            } catch {
                await LogService.shared.log(
                    .error,
                    category: "trash",
                    message: "Failed emptying trash entry \(entry.id): \(error.localizedDescription)"
                )
            }
        }
        return purgedCount
    }

    /// Snapshot of all trash entries, newest first.
    public func entries() -> [TrashEntry] {
        guard let modelContext else { return [] }
        var descriptor = FetchDescriptor<TrashEntry>(
            sortBy: [SortDescriptor(\.trashedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1000
        return (try? modelContext.fetch(descriptor)) ?? []
    }
}

public enum TrashError: LocalizedError {
    case notAttached

    public var errorDescription: String? {
        switch self {
        case .notAttached:
            return "Le service de corbeille n'est pas initialisé."
        }
    }
}
