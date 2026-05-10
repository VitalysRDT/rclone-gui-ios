//
//  TrashEntry.swift
//  Rclone GUI — Models
//
//  Persistent metadata for a file or folder moved to the local recycle bin
//  via TrashService. The actual data lives on the remote at
//  `<remote>:.rclone-gui-trash/<id>/<name>` so a server-side rename is enough
//  to trash and restore — no copy + delete cycle, fast even on crypt remotes.
//

import Foundation
import SwiftData

@Model
public final class TrashEntry {
    @Attribute(.unique) public var id: String

    public var originalRemote: String

    /// Original path inside the remote (no `<remote>:` prefix).
    /// e.g. "Documents/contracts/2026.pdf"
    public var originalPath: String

    /// Original basename, surfaced in the UI.
    public var originalName: String

    public var isDirectory: Bool

    /// Size in bytes at trash time. -1 if unknown.
    public var sizeBytes: Int64

    public var trashedAt: Date

    /// Default retention is 30 days from trashedAt. Auto-purge after expiry.
    public var expiresAt: Date

    /// Current path of the item inside the trash dir, ex.
    /// `.rclone-gui-trash/<id>/<originalName>`. We always nest one level deep
    /// under the UUID so two trashed files with the same name don't collide.
    public var trashPath: String

    public init(
        id: String = UUID().uuidString,
        originalRemote: String,
        originalPath: String,
        originalName: String,
        isDirectory: Bool,
        sizeBytes: Int64,
        trashPath: String,
        trashedAt: Date = .now,
        retention: TimeInterval = 30 * 24 * 60 * 60
    ) {
        self.id = id
        self.originalRemote = originalRemote
        self.originalPath = originalPath
        self.originalName = originalName
        self.isDirectory = isDirectory
        self.sizeBytes = sizeBytes
        self.trashPath = trashPath
        self.trashedAt = trashedAt
        self.expiresAt = trashedAt.addingTimeInterval(retention)
    }
}
