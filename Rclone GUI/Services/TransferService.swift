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

/// How a move (or rename, which is just a move in place) maps onto rclone's
/// rc API.
///
/// rclone exposes two *different* call shapes, and they are not interchangeable:
///
///   - `operations/movefile` takes an fs **root** plus a path relative to it.
///     It resolves the source through `NewObject`, which returns
///     `fs.ErrorIsDir` — surfaced verbatim as "is a directory not a file" —
///     as soon as the path designates a directory.
///   - `sync/move` takes a **complete** fs string on each side
///     ("remote:some/dir") and is the only way to move a directory.
///
/// Issue #142: renaming a folder went through `operations/movefile`
/// unconditionally, so every directory rename failed. Crypt remotes made it
/// visible because they forward the wrapped backend's `ErrorIsDir` untouched,
/// where other backends blur it into a not-found error.
///
/// Keeping the decision in one `Equatable` value makes it unit-testable
/// without an rclone engine, and stops the routing being re-implemented (and
/// re-broken) at each call site.
///
/// `nonisolated` because the target defaults to `MainActor` isolation: this is
/// a pure value type built and compared from `TransferService` (a non-main
/// actor) and from tests, so a main-actor-isolated `Equatable` conformance
/// would be a Swift 6 error.
public nonisolated enum RemoteMovePlan: Equatable, Sendable {
    /// `operations/movefile`: fs root + relative path, on each side.
    case file(srcFs: String, srcPath: String, dstFs: String, dstPath: String)
    /// `sync/move`: full fs string on each side.
    case directory(srcFs: String, dstFs: String)

    /// Resolve the call shape for moving `srcPath` on `srcRemote` to `dstPath`
    /// on `dstRemote`. Source and destination remotes may differ; a rename is
    /// simply the same-remote, same-parent case.
    public static func make(
        srcRemote: String,
        srcPath: String,
        dstRemote: String,
        dstPath: String,
        isDirectory: Bool
    ) -> RemoteMovePlan {
        isDirectory
            ? .directory(srcFs: "\(srcRemote):\(srcPath)", dstFs: "\(dstRemote):\(dstPath)")
            : .file(srcFs: "\(srcRemote):", srcPath: srcPath, dstFs: "\(dstRemote):", dstPath: dstPath)
    }
}

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

    /// Copy an entire directory tree. `srcFs` and `dstFs` are complete
    /// rclone fs strings, e.g. "drive:Photos/2026" or a local absolute path.
    public func copyDirAsync(srcFs: String, dstFs: String, createEmptySrcDirs: Bool = true) async throws -> Int {
        try await jobIDFromRPC(
            method: "sync/copy",
            input: DirPair(srcFs: srcFs, dstFs: dstFs, createEmptySrcDirs: createEmptySrcDirs, _async: true)
        )
    }

    /// Sync an entire directory tree. This mirrors the source into the
    /// destination, including deletion of destination-only files according
    /// to rclone sync semantics.
    public func syncDirAsync(srcFs: String, dstFs: String, createEmptySrcDirs: Bool = true) async throws -> Int {
        try await jobIDFromRPC(
            method: "sync/sync",
            input: DirPair(srcFs: srcFs, dstFs: dstFs, createEmptySrcDirs: createEmptySrcDirs, _async: true)
        )
    }

    /// Move an entire directory tree. Server-side when supported by rclone,
    /// otherwise rclone falls back to copy + delete.
    public func moveDirAsync(
        srcFs: String,
        dstFs: String,
        deleteEmptySrcDirs: Bool = true,
        createEmptySrcDirs: Bool = true
    ) async throws -> Int {
        try await jobIDFromRPC(
            method: "sync/move",
            input: MoveDirPair(
                srcFs: srcFs,
                dstFs: dstFs,
                createEmptySrcDirs: createEmptySrcDirs,
                deleteEmptySrcDirs: deleteEmptySrcDirs,
                _async: true
            )
        )
    }

    /// Run a move/rename, dispatching on the shape resolved by `RemoteMovePlan`.
    /// Single entry point so the file-vs-directory decision lives in exactly
    /// one place (see `RemoteMovePlan` for why it must not be duplicated).
    public func moveAsync(_ plan: RemoteMovePlan) async throws -> Int {
        switch plan {
        case let .file(srcFs, srcPath, dstFs, dstPath):
            return try await moveFileAsync(srcFs: srcFs, srcPath: srcPath, dstFs: dstFs, dstPath: dstPath)
        case let .directory(srcFs, dstFs):
            return try await moveDirAsync(srcFs: srcFs, dstFs: dstFs)
        }
    }

    /// Rename in place: same remote, same parent, new name.
    ///
    /// `isDirectory` has no default on purpose: guessing wrong silently sends a
    /// folder through `operations/movefile`, which is exactly the bug reported
    /// in issue #142. Callers must state what they are renaming.
    public func renameAsync(
        remote: String,
        oldPath: String,
        newPath: String,
        isDirectory: Bool
    ) async throws -> Int {
        try await moveAsync(
            RemoteMovePlan.make(
                srcRemote: remote,
                srcPath: oldPath,
                dstRemote: remote,
                dstPath: newPath,
                isDirectory: isDirectory
            )
        )
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

    // MARK: - Bandwidth control

    /// Set the global rclone bandwidth ceiling. `bytesPerSecond == 0` removes
    /// the limit entirely (rate = "off"). Otherwise the value is forwarded
    /// to rclone as raw bytes per second; rclone applies the same ceiling
    /// to upload and download.
    public func setBandwidthLimit(bytesPerSecond: Int64) async throws {
        struct Input: Encodable { let rate: String }
        struct Empty: Decodable {}
        let rate = bytesPerSecond <= 0 ? "off" : "\(bytesPerSecond)b"
        let _: Empty = try await RcloneCore.shared.rpc("core/bwlimit", input: Input(rate: rate))
    }

    /// Pause every running transfer by setting the bandwidth ceiling to 0
    /// bytes/second. Active jobs keep their slots — they just stop making
    /// progress until `resumeAllTransfers` restores a positive rate.
    public func pauseAllTransfers() async throws {
        struct Input: Encodable { let rate: String }
        struct Empty: Decodable {}
        let _: Empty = try await RcloneCore.shared.rpc("core/bwlimit", input: Input(rate: "1b"))
        // rclone treats rate "0" as "no limit" rather than "stop", which
        // is the opposite of intuition. The lowest non-zero rate that
        // effectively stops progress is 1b/s.
    }

    /// Restore a positive bandwidth ceiling. Pass 0 to resume to "off"
    /// (unlimited). Used as the counterpart of `pauseAllTransfers()`.
    public func resumeAllTransfers(bytesPerSecond: Int64) async throws {
        try await setBandwidthLimit(bytesPerSecond: bytesPerSecond)
    }

    // MARK: - Internals

    private struct PathPair: Encodable {
        let srcFs: String
        let srcRemote: String
        let dstFs: String
        let dstRemote: String
        let _async: Bool
    }

    private struct DirPair: Encodable {
        let srcFs: String
        let dstFs: String
        let createEmptySrcDirs: Bool
        let _async: Bool
    }

    private struct MoveDirPair: Encodable {
        let srcFs: String
        let dstFs: String
        let createEmptySrcDirs: Bool
        let deleteEmptySrcDirs: Bool
        let _async: Bool
    }

    private func jobIDFromRPC<I: Encodable & Sendable>(method: String, input: I) async throws -> Int {
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
