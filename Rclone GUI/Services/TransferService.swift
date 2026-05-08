//
//  TransferService.swift
//  Rclone GUI — Services
//
//  Typed wrappers around rclone rc methods that mutate data:
//  copy, move, rename, delete, purge, mkdir + job status polling.
//  All long-running operations are dispatched in async mode (`_async: true`)
//  so the call returns a job ID immediately and progress is observed via
//  `jobStatus(jobID:)`.
//

import Foundation

public actor TransferService {
    public static let shared = TransferService()

    private init() {}

    // MARK: - Async helpers (return jobID)

    /// Copy a file. Source and destination can each be either a remote
    /// (use `"<name>:"` syntax) or a local absolute filesystem path.
    public func copyFileAsync(
        srcFs: String,
        srcPath: String,
        dstFs: String,
        dstPath: String
    ) async throws -> Int {
        try await jobIDFromRPC(
            method: "operations/copyfile",
            input: PathPair(srcFs: srcFs, srcRemote: srcPath, dstFs: dstFs, dstRemote: dstPath, _async: true)
        )
    }

    /// Move a file (server-side when supported, fallback to copy+delete).
    public func moveFileAsync(
        srcFs: String,
        srcPath: String,
        dstFs: String,
        dstPath: String
    ) async throws -> Int {
        try await jobIDFromRPC(
            method: "operations/movefile",
            input: PathPair(srcFs: srcFs, srcRemote: srcPath, dstFs: dstFs, dstRemote: dstPath, _async: true)
        )
    }

    /// Rename in place: same parent, new name. Wraps moveFile.
    public func renameAsync(remote: String, oldPath: String, newPath: String) async throws -> Int {
        try await moveFileAsync(srcFs: "\(remote):", srcPath: oldPath, dstFs: "\(remote):", dstPath: newPath)
    }

    /// Delete a single file.
    public func deleteFileAsync(remote: String, path: String) async throws -> Int {
        struct Input: Encodable {
            let fs: String
            let remote: String
            let _async: Bool
        }
        return try await jobIDFromRPC(
            method: "operations/deletefile",
            input: Input(fs: "\(remote):", remote: path, _async: true)
        )
    }

    /// Purge an entire directory recursively.
    public func purgeAsync(remote: String, path: String) async throws -> Int {
        struct Input: Encodable {
            let fs: String
            let remote: String
            let _async: Bool
        }
        return try await jobIDFromRPC(
            method: "operations/purge",
            input: Input(fs: "\(remote):", remote: path, _async: true)
        )
    }

    /// Synchronous mkdir (no job ID — instantaneous on most backends).
    public func mkdir(remote: String, path: String) async throws {
        struct Input: Encodable {
            let fs: String
            let remote: String
        }
        struct Output: Decodable {}
        let _: Output = try await RcloneCore.shared.rpc(
            "operations/mkdir",
            input: Input(fs: "\(remote):", remote: path)
        )
    }

    // MARK: - Job status

    public func jobStatus(jobID: Int) async throws -> JobInfoDTO {
        struct Input: Encodable {
            let jobid: Int
        }
        struct Raw: Decodable {
            let id: Int
            let finished: Bool
            let success: Bool
            let error: String?
            let startTime: String?
            // operations/copyfile reports progress through core/stats, NOT job/status.
            // job/status only returns finished/success/error for "single-file" jobs.
            // For long copies and especially folder syncs, you'd query core/stats too.
        }
        let raw: Raw = try await RcloneCore.shared.rpc("job/status", input: Input(jobid: jobID))
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return JobInfoDTO(
            id: raw.id,
            finished: raw.finished,
            success: raw.success,
            error: raw.error,
            bytesTransferred: 0,
            bytesTotal: 0,
            speedBytesPerSec: 0,
            etaSeconds: nil,
            startTime: raw.startTime.flatMap { dateFormatter.date(from: $0) }
        )
    }

    /// Global rclone stats — supplements per-job status with byte counters.
    public func coreStats() async throws -> CoreStatsDTO {
        struct Empty: Encodable {}
        struct Raw: Decodable {
            let bytes: Int64
            let speed: Double
            let totalBytes: Int64
            let transferring: [Transferring]?

            struct Transferring: Decodable {
                let name: String
                let size: Int64
                let bytes: Int64
                let speed: Double
                let eta: Int64?
            }
        }
        let raw: Raw = try await RcloneCore.shared.rpc("core/stats", input: Empty())
        return CoreStatsDTO(
            totalBytes: raw.totalBytes,
            transferredBytes: raw.bytes,
            globalSpeed: raw.speed,
            transferring: raw.transferring?.map {
                CoreStatsDTO.Transferring(
                    name: $0.name,
                    bytesTotal: $0.size,
                    bytesTransferred: $0.bytes,
                    speed: $0.speed,
                    eta: $0.eta
                )
            } ?? []
        )
    }

    public func stopJob(jobID: Int) async throws {
        struct Input: Encodable { let jobid: Int }
        struct Empty: Decodable {}
        let _: Empty = try await RcloneCore.shared.rpc("job/stop", input: Input(jobid: jobID))
    }

    // MARK: - Internals

    private struct PathPair: Encodable {
        let srcFs: String
        let srcRemote: String
        let dstFs: String
        let dstRemote: String
        let _async: Bool
    }

    private func jobIDFromRPC<I: Encodable>(method: String, input: I) async throws -> Int {
        let resp: JobIDResponse = try await RcloneCore.shared.rpc(method, input: input)
        return resp.jobid
    }

    private struct JobIDResponse: Decodable {
        let jobid: Int
    }
}

public struct CoreStatsDTO: Sendable, Hashable {
    public let totalBytes: Int64
    public let transferredBytes: Int64
    public let globalSpeed: Double
    public let transferring: [Transferring]

    public struct Transferring: Sendable, Hashable {
        public let name: String
        public let bytesTotal: Int64
        public let bytesTransferred: Int64
        public let speed: Double
        public let eta: Int64?
    }
}
