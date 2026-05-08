//
//  JobInfoDTO.swift
//  Rclone GUI — Models
//
//  In-memory snapshot of a rclone async job (`job/status` response).
//  Not persisted as a SwiftData @Model — Transfer is the persistent
//  record; JobInfoDTO is the volatile progress shape.
//

import Foundation

public struct JobInfoDTO: Sendable, Hashable {
    public let id: Int
    public let finished: Bool
    public let success: Bool
    public let error: String?
    public let bytesTransferred: Int64
    public let bytesTotal: Int64
    public let speedBytesPerSec: Double
    public let etaSeconds: Int64?
    public let startTime: Date?
}
