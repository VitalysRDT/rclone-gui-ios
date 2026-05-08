//
//  RemoteEntry.swift
//  Rclone GUI — Models
//
//  SwiftData cache of one file or folder discovered on a remote.
//  Populated lazily by `RemoteService.list(remote:path:)` to enable
//  offline navigation, fast scrolling, and ETag-style change detection.
//

import Foundation
import SwiftData

@Model
public final class RemoteEntry {
    /// Full path inside the remote, e.g. "Movies/four-lions-2010.mp4".
    /// (Never includes the "remote:" prefix.)
    public var pathInRemote: String

    /// Basename, e.g. "four-lions-2010.mp4".
    public var name: String

    public var isDirectory: Bool

    /// File size in bytes. -1 means unknown (some backends don't return size for dirs).
    public var size: Int64

    public var modTime: Date

    public var mimeType: String?
    public var hashMD5: String?
    public var hashSHA1: String?

    /// Last time we saw this entry while browsing — used to evict stale cache.
    public var lastSeenAt: Date

    public var remote: Remote?

    public init(
        pathInRemote: String,
        name: String,
        isDirectory: Bool,
        size: Int64,
        modTime: Date,
        mimeType: String? = nil,
        hashMD5: String? = nil,
        hashSHA1: String? = nil,
        remote: Remote? = nil
    ) {
        self.pathInRemote = pathInRemote
        self.name = name
        self.isDirectory = isDirectory
        self.size = size
        self.modTime = modTime
        self.mimeType = mimeType
        self.hashMD5 = hashMD5
        self.hashSHA1 = hashSHA1
        self.lastSeenAt = .now
        self.remote = remote
    }
}
