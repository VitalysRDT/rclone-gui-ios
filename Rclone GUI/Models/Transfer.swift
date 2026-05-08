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
    case completed
    case failed
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

    public init(
        id: String = UUID().uuidString,
        kind: TransferKind,
        sourceRemote: String? = nil,
        sourcePath: String,
        destinationRemote: String? = nil,
        destinationPath: String,
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
        self.bytesTotal = bytesTotal
        self.bytesTransferred = 0
        self.startedAt = .now
    }
}
