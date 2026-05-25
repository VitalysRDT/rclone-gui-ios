//
//  FilesClipboard.swift
//  Rclone GUI — Services
//
//  In-memory clipboard for the Cut / Copy / Paste pattern à la Files.app.
//  The user stages a set of remote entries (with cut or copy semantics)
//  from any folder, then navigates anywhere and pastes them into the current
//  directory. Behind the scenes the paste delegates to TransferQueue's batch
//  remote-transfer API (`copyfile` / `movefile` server-side).
//
//  Why our own clipboard instead of UIPasteboard?
//   - UIPasteboard items are typed Data/string blobs; representing a list of
//     remote-rooted paths with metadata (isDirectory, size) is awkward there.
//   - We don't want this clipboard to leak across apps. A user's rclone paths
//     have no meaning outside Rclone GUI.
//   - SwiftUI views need to react to staging changes; @Observable gives us
//     that for free.
//
//  Persistence: in-memory only. If the app is force-quit between staging
//  and pasting, the clipboard is lost. Acceptable for an MVP — Files.app
//  has the same behavior.
//

import Foundation
import Observation

@MainActor
@Observable
public final class FilesClipboard {
    public static let shared = FilesClipboard()

    private init() {}

    // MARK: - Types

    public enum Operation: String, Sendable, Equatable {
        case copy
        case cut
    }

    public struct Item: Sendable, Identifiable, Hashable {
        public let remote: String
        public let path: String
        public let name: String
        public let isDirectory: Bool
        public let size: Int64

        public var id: String { "\(remote):\(path)" }

        public init(remote: String, path: String, name: String, isDirectory: Bool, size: Int64) {
            self.remote = remote
            self.path = path
            self.name = name
            self.isDirectory = isDirectory
            self.size = size
        }
    }

    // MARK: - Observable state

    public private(set) var items: [Item] = []
    public private(set) var operation: Operation = .copy

    // MARK: - Derived state

    public var isEmpty: Bool { items.isEmpty }
    public var count: Int { items.count }

    /// All staged items live on the same remote (we stage from a single
    /// folder context). The first item's remote is therefore canonical.
    public var sourceRemote: String? { items.first?.remote }

    // MARK: - Mutation

    /// Replace the current clipboard with a new set of items + operation.
    /// A subsequent stage replaces the clipboard, never appends — that mirrors
    /// the system clipboard model and avoids surprising the user.
    public func stage(items: [Item], operation: Operation) {
        self.items = items
        self.operation = operation
    }

    /// Convenience helper for staging from a list of `RemoteEntryDTO`.
    public func stage(entries: [RemoteEntryDTO], remote: String, operation: Operation) {
        let mapped = entries.map { entry in
            Item(
                remote: remote,
                path: entry.pathInRemote,
                name: entry.name,
                isDirectory: entry.isDirectory,
                size: entry.size
            )
        }
        stage(items: mapped, operation: operation)
    }

    public func clear() {
        items = []
    }

    // MARK: - Visual indicator helpers

    /// True when the path is staged in cut mode — the row should look dimmed.
    public func isStagedCut(remote: String, path: String) -> Bool {
        guard operation == .cut else { return false }
        return items.contains { $0.remote == remote && $0.path == path }
    }

    /// True when the path is staged in copy mode — useful for a subtle badge.
    public func isStagedCopy(remote: String, path: String) -> Bool {
        guard operation == .copy else { return false }
        return items.contains { $0.remote == remote && $0.path == path }
    }

    // MARK: - Paste

    /// Paste staged items into the target folder. Routes through
    /// `TransferQueue.enqueueRemoteTransferBatch` so the user sees the same
    /// progress UI as any other remote transfer.
    ///
    /// Clears the clipboard *before* dispatching, mirroring the system
    /// clipboard contract — the act of pasting commits the intent regardless
    /// of the async outcome. Per-item failures are recorded in TransferQueue
    /// so the user can inspect them; the clipboard does not stay dirty.
    ///
    /// Pre-flight: unless `force` is true, every destination path is stat-ed
    /// and any conflict throws `FilesClipboardError.destinationConflict` so
    /// the caller can prompt for confirmation. This prevents silent
    /// `rclone copyfile/movefile` overwrites — the canonical data-loss
    /// scenario for a file manager.
    @discardableResult
    public func paste(into remote: String, folder: String, force: Bool = false) async throws -> TransferBatch? {
        guard !items.isEmpty, let srcRemote = sourceRemote else { return nil }

        // Pre-flight conflict check (skip with `force: true`, e.g. after the
        // user has confirmed an overwrite dialog). We collect *all* conflicts
        // before throwing so the dialog can list them, not surface them one
        // at a time.
        if !force {
            var conflicts: [String] = []
            for item in items {
                let destPath = joined(folder, item.name)
                let exists = (try? await RemoteService.shared.stat(remote: remote, path: destPath)) ?? nil
                if exists != nil {
                    conflicts.append(item.name)
                }
            }
            if !conflicts.isEmpty {
                throw FilesClipboardError.destinationConflict(conflicts)
            }
        }

        // Snapshot before clearing so the dispatch loop still has the data.
        let snapshot = items
        let snapshotOperation = operation
        clear()

        let entries: [RemoteEntryDTO] = snapshot.map { item in
            RemoteEntryDTO(
                pathInRemote: item.path,
                name: item.name,
                isDirectory: item.isDirectory,
                size: item.size,
                modTime: .now,
                mimeType: nil,
                hashMD5: nil,
                hashSHA1: nil
            )
        }

        let kind: TransferKind = snapshotOperation == .cut ? .move : .copy
        return try await TransferQueue.shared.enqueueRemoteTransferBatch(
            kind: kind,
            srcRemote: srcRemote,
            entries: entries,
            dstRemote: remote,
            dstFolder: folder
        )
    }

    /// Whether pasting into the given target makes sense given the current
    /// clipboard. Returns false for an empty clipboard, or for a cut where
    /// *any* staged item would land back into its own parent folder
    /// (a no-op self-move that some rclone backends error on).
    public func canPaste(into remote: String, folder: String) -> Bool {
        guard !items.isEmpty else { return false }
        guard operation == .cut else { return true }
        // Refuse if any single item would no-op-move into its own parent.
        return !items.contains { item in
            item.remote == remote && parent(of: item.path) == folder
        }
    }

    // MARK: - Helpers

    private func parent(of path: String) -> String {
        let parent = (path as NSString).deletingLastPathComponent
        return parent
    }

    /// Mirror of TransferQueue.joinedRemotePath — strips leading/trailing
    /// slashes from the folder so we don't produce paths like "/foo/bar"
    /// that some rclone backends choke on.
    private func joined(_ folder: String, _ name: String) -> String {
        let cleanFolder = folder.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return cleanFolder.isEmpty ? name : "\(cleanFolder)/\(name)"
    }
}

public enum FilesClipboardError: LocalizedError, Equatable {
    /// One or more destination paths already exist; the user must confirm
    /// the overwrite before the paste proceeds. The associated value is the
    /// list of conflicting basenames so the UI can list them.
    case destinationConflict([String])

    public var errorDescription: String? {
        switch self {
        case .destinationConflict(let names):
            if names.count == 1 {
                return String(localized: "« \(names[0]) » existe déjà à cet emplacement.")
            }
            return String(localized: "\(names.count) éléments existent déjà à cet emplacement.")
        }
    }
}
