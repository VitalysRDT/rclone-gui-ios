//
//  RemoteService.swift
//  Rclone GUI — Services
//
//  Typed wrapper around RcloneCore RPCs that the UI consumes.
//  Phase B scope: list remotes, get remote space info, list a folder.
//
//  All public methods return value types (DTOs) so the UI doesn't depend
//  on SwiftData @Model lifetimes. SwiftData persistence is wired by
//  consumers (e.g. RemotesListView) in their own context.
//

import Foundation

// MARK: - DTOs

public struct RemoteSummaryDTO: Sendable, Identifiable, Hashable {
    public var id: String { name }
    public let name: String
    public let type: String
    public let isCrypt: Bool
}

public struct RemoteEntryDTO: Sendable, Identifiable, Hashable {
    public var id: String { pathInRemote.isEmpty ? name : pathInRemote }
    public let pathInRemote: String
    public let name: String
    public let isDirectory: Bool
    public let size: Int64
    public let modTime: Date
    public let mimeType: String?
    public let hashMD5: String?
    public let hashSHA1: String?
}

public struct RemoteSpaceDTO: Sendable, Hashable {
    public let total: Int64?
    public let used: Int64?
    public let free: Int64?
    public let trashed: Int64?
}

// MARK: - Service

public actor RemoteService {
    public static let shared = RemoteService()

    private init() {}

    // MARK: List remotes

    /// Names of all remotes in rclone.conf (`config/listremotes`).
    public func listRemoteNames() async throws -> [String] {
        try await RcloneCore.shared.listRemoteNames()
    }

    /// Names + types of all remotes (`config/dump` then filtered).
    public func listRemoteSummaries() async throws -> [RemoteSummaryDTO] {
        struct DumpEntry: Decodable {
            let type: String
        }
        let names = try await listRemoteNames()
        let dump: [String: DumpEntry] = (try? await RcloneCore.shared.rpc("config/dump")) ?? [:]
        return names.map { name in
            let type = dump[name]?.type ?? "unknown"
            return RemoteSummaryDTO(
                name: name,
                type: type,
                isCrypt: type == "crypt"
            )
        }
    }

    // MARK: List folder

    /// List the entries inside `<remote>:<path>` via `operations/list`.
    public func list(remote: String, path: String = "") async throws -> [RemoteEntryDTO] {
        struct Input: Encodable {
            let fs: String
            let remote: String
            let opt: ListOptions
        }
        struct ListOptions: Encodable {
            let recurse: Bool
            let noModTime: Bool
            let showHash: Bool
        }
        struct Output: Decodable {
            let list: [RawItem]
        }
        struct RawItem: Decodable {
            let path: String
            let name: String
            let size: Int64
            let mimeType: String?
            let modTime: String?
            let isDir: Bool
            let hashes: [String: String]?

            enum CodingKeys: String, CodingKey {
                case path = "Path"
                case name = "Name"
                case size = "Size"
                case mimeType = "MimeType"
                case modTime = "ModTime"
                case isDir = "IsDir"
                case hashes = "Hashes"
            }
        }

        let input = Input(
            fs: "\(remote):",
            remote: path,
            opt: ListOptions(recurse: false, noModTime: false, showHash: false)
        )
        let output: Output = try await RcloneCore.shared.rpc("operations/list", input: input)

        return output.list.map { raw in
            RemoteEntryDTO(
                pathInRemote: raw.path,
                name: raw.name,
                isDirectory: raw.isDir,
                size: max(raw.size, 0),
                modTime: Self.parseRcloneTime(raw.modTime),
                mimeType: raw.mimeType,
                hashMD5: raw.hashes?["md5"],
                hashSHA1: raw.hashes?["sha1"]
            )
        }
    }

    // MARK: Remote space

    /// `operations/about` for a remote (when the backend supports it).
    public func space(remote: String) async throws -> RemoteSpaceDTO {
        struct Input: Encodable {
            let fs: String
        }
        struct Output: Decodable {
            let total: Int64?
            let used: Int64?
            let free: Int64?
            let trashed: Int64?
        }
        let resp: Output = try await RcloneCore.shared.rpc(
            "operations/about",
            input: Input(fs: "\(remote):")
        )
        return RemoteSpaceDTO(
            total: resp.total,
            used: resp.used,
            free: resp.free,
            trashed: resp.trashed
        )
    }

    // MARK: Internals

    private static func parseRcloneTime(_ raw: String?) -> Date {
        guard let raw, !raw.isEmpty else { return .distantPast }
        // rclone serializes timestamps as RFC3339 with optional fractional seconds:
        //   2026-01-15T12:34:56.789Z
        //   2026-01-15T12:34:56Z
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFraction.date(from: raw) { return d }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: raw) ?? .distantPast
    }
}
