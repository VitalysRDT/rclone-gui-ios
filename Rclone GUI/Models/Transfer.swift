//
//  Transfer.swift
//  Rclone GUI — Models
//
//  Persistent record of an in-flight or finished transfer.
//  Used by `TransferQueue` (Phase C) and the future Live Activities
//  + background URLSession resume manifest.
//

import Foundation
import SwiftData

public enum TransferKind: String, Codable, Sendable, CaseIterable {
    case download
    case upload
    case move
    case copy
    case sync
    case delete
}

public enum TransferStatus: String, Codable, Sendable, CaseIterable {
    case pending
    case running
    case paused
    case enqueued
    case completed
    case failed
}

public enum TransferSourceKind: String, Codable, Sendable, CaseIterable {
    case remote
    case localFile
    case localFolder
    case photoLibrary
    case fileProvider
}

@Model
public final class TransferBatch {
    @Attribute(.unique) public var id: String
    public var title: String
    public var kindRaw: String
    public var statusRaw: String
    public var createdAt: Date
    public var finishedAt: Date?
    public var totalItems: Int
    public var completedItems: Int
    public var failedItems: Int
    public var bytesTotal: Int64
    public var bytesTransferred: Int64
    public var lastError: String?

    public var kind: TransferKind {
        get { TransferKind(rawValue: kindRaw) ?? .download }
        set { kindRaw = newValue.rawValue }
    }

    public var status: TransferStatus {
        get { TransferStatus(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }

    public init(
        id: String = UUID().uuidString,
        title: String,
        kind: TransferKind,
        totalItems: Int
    ) {
        self.id = id
        self.title = title
        self.kindRaw = kind.rawValue
        self.statusRaw = TransferStatus.pending.rawValue
        self.createdAt = .now
        self.totalItems = totalItems
        self.completedItems = 0
        self.failedItems = 0
        self.bytesTotal = 0
        self.bytesTransferred = 0
    }
}

@Model
public final class Transfer {
    @Attribute(.unique) public var id: String

    /// Stored as raw String to keep SwiftData migration simple.
    public var kindRaw: String
    public var statusRaw: String

    public var sourceRemote: String?
    public var sourcePath: String

    public var destinationRemote: String?
    public var destinationPath: String

    public var batchID: String?
    public var relativePath: String?
    public var displayName: String?
    public var retryCount: Int
    public var sourceKindRaw: String

    /// True when the transfer source is a directory tree (recursive copy/move/sync).
    /// Used by retry() to dispatch to the correct rclone RPC. Optional with default
    /// nil → treated as false for backward compat with pre-Sprint-3 records.
    public var isDirectoryTransfer: Bool? = false

    public var bytesTotal: Int64
    public var bytesTransferred: Int64

    public var startedAt: Date
    public var finishedAt: Date?
    public var lastError: String?

    /// rclone job id (returned by async RPC). nil for sync ops.
    public var jobID: Int?

    public var kind: TransferKind {
        get { TransferKind(rawValue: kindRaw) ?? .download }
        set { kindRaw = newValue.rawValue }
    }

    public var status: TransferStatus {
        get { TransferStatus(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }

    public var sourceKind: TransferSourceKind {
        get { TransferSourceKind(rawValue: sourceKindRaw) ?? .remote }
        set { sourceKindRaw = newValue.rawValue }
    }

    public init(
        id: String = UUID().uuidString,
        kind: TransferKind,
        sourceRemote: String? = nil,
        sourcePath: String,
        destinationRemote: String? = nil,
        destinationPath: String,
        batchID: String? = nil,
        relativePath: String? = nil,
        displayName: String? = nil,
        sourceKind: TransferSourceKind = .remote,
        bytesTotal: Int64 = 0,
        status: TransferStatus = .pending
    ) {
        self.id = id
        self.kindRaw = kind.rawValue
        self.statusRaw = status.rawValue
        self.sourceRemote = sourceRemote
        self.sourcePath = sourcePath
        self.destinationRemote = destinationRemote
        self.destinationPath = destinationPath
        self.batchID = batchID
        self.relativePath = relativePath
        self.displayName = displayName
        self.retryCount = 0
        self.sourceKindRaw = sourceKind.rawValue
        self.bytesTotal = bytesTotal
        self.bytesTransferred = 0
        self.startedAt = .now
    }
}
