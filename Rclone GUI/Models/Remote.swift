//
//  Remote.swift
//  Rclone GUI — Models
//
//  SwiftData @Model representing one rclone remote (e.g. "r2-vitalys",
//  "backblaze-crypt", "drive-perso"). Mirrors the [<name>] sections of
//  rclone.conf.
//
//  The instance is populated by `RemoteService` after a successful
//  `config/listremotes` + `config/dump` round-trip.
//

import Foundation
import SwiftData

@Model
public final class Remote {
    /// Remote name, exactly as defined in rclone.conf.
    @Attribute(.unique) public var name: String

    /// rclone backend type identifier ("s3", "sftp", "drive", "crypt", "alias", ...).
    public var type: String

    /// True for crypt-backed remotes (UI shows a 🔒 indicator).
    public var isCrypt: Bool

    /// True for "alias", "union", "combine", "chunker" — composed remotes.
    public var isComposed: Bool

    public var addedAt: Date
    public var lastVisitedAt: Date?

    /// Cached `operations/about` results — refreshed manually.
    public var totalBytes: Int64?
    public var freeBytes: Int64?
    public var usedBytes: Int64?
    public var aboutCheckedAt: Date?

    /// Optional SFTP host fingerprint for pinning (filled by user opt-in).
    public var sftpFingerprint: String?

    @Relationship(deleteRule: .cascade, inverse: \RemoteEntry.remote)
    public var entries: [RemoteEntry] = []

    public init(
        name: String,
        type: String,
        isCrypt: Bool = false,
        isComposed: Bool = false
    ) {
        self.name = name
        self.type = type
        self.isCrypt = isCrypt
        self.isComposed = isComposed
        self.addedAt = .now
    }
}
