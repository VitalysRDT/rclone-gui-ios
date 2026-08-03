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

public struct RemoteSizeDTO: Sendable, Hashable {
    public let count: Int64
    public let bytes: Int64
    public let sizeless: Int64
}

// MARK: - Service

public actor RemoteService {
    public static let shared = RemoteService()

    private init() {}

    /// Whether rclone reports the backend PublicLink capability used by
    /// operations/publiclink. Wrapper remotes may forward this feature.
    public func supportsPublicLink(remote: String) async -> Bool {
        struct Input: Encodable { let fs: String }
        struct Output: Decodable {
            let features: Features?
            struct Features: Decodable {
                let publicLink: Bool?
                enum CodingKeys: String, CodingKey { case publicLink = "PublicLink" }
            }
            enum CodingKeys: String, CodingKey { case features = "Features" }
        }
        do {
            let output: Output = try await RcloneCore.shared.rpc("operations/fsinfo", input: Input(fs: "\(remote):"))
            return output.features?.publicLink == true
        } catch { return false }
    }

    /// Creates or retrieves a provider-backed public link through rclone.
    /// This is deliberately invoked only after an explicit user action: some
    /// backends change the object's sharing permissions while creating it.
    public func createPublicLink(remote: String, path: String) async throws -> URL {
        struct Input: Encodable {
            let fs: String
            let remote: String
        }
        struct Output: Decodable { let url: String }

        let output: Output = try await RcloneCore.shared.rpc(
            "operations/publiclink",
            input: Input(fs: "\(remote):", remote: path)
        )
        guard let url = URL(string: output.url),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http" else {
            throw RcloneError.unexpectedResponseShape(
                method: "operations/publiclink",
                expected: "une URL HTTP(S) dans le champ url",
                raw: output.url
            )
        }
        return url
    }

    // Cache + inflight dedup pour operations/about. Sans ça, chaque
    // déclencheur de FilesRootView.load() (boot .task, .onReceive
    // rcloneConfigurationDidChange, scenePhase, refreshable…) relançait
    // 6 abouts indépendants. Avec 5 batches en cascade au boot ça
    // saturait le pool TCP Drive/SFTP et tous les RPC pendaient.
    private static let spaceCacheTTL: TimeInterval = 60
    private var spaceCache: [String: (value: RemoteSpaceDTO, expires: Date)] = [:]
    private var spaceInflight: [String: Task<RemoteSpaceDTO, Error>] = [:]

    // MARK: List remotes

    /// Names of all remotes in rclone.conf (`config/listremotes`).
    public func listRemoteNames() async throws -> [String] {
        try await RcloneCore.shared.listRemoteNames()
    }

    /// Names + types of all remotes (`config/dump` then filtered).
    /// Utilise le cache 30s côté RcloneCore pour éviter les rafales lors
    /// des navigations fréquentes Settings ↔ RemotesList ↔ Folder.
    public func listRemoteSummaries() async throws -> [RemoteSummaryDTO] {
        let names = try await listRemoteNames()
        let dump = (try? await RcloneCore.shared.configDump()) ?? [:]
        return names.map { name in
            let type = dump[name]?["type"] ?? "unknown"
            return RemoteSummaryDTO(
                name: name,
                type: type,
                isCrypt: type == "crypt"
            )
        }
    }

    /// Force rclone à recréer ses objets `Fs` (vide le cache d'Fs global via
    /// `fscache/clear`). À appeler sur un pull-to-refresh EXPLICITE pour
    /// garantir le listing le plus frais possible : certains backends gardent
    /// un cache de répertoires en mémoire sur l'Fs (ex. Drive) et ne reflètent
    /// pas immédiatement un changement fait ailleurs. Best-effort (no-op si la
    /// RC n'existe pas). N'interrompt PAS un flux média en cours : le serve
    /// loopback garde sa propre référence forte d'Fs.
    public func invalidateListingCache() async {
        _ = try? await RcloneCore.shared.rpcRaw("fscache/clear", "{}")
    }

    // MARK: List folder

    /// List the entries inside `<remote>:<path>` via `operations/list`.
    ///
    /// A successful but empty response is normally authoritative. Some crypt +
    /// backend combinations can however transiently return `[]` for a populated
    /// directory. Treating that first response as final is dangerous: the UI says
    /// "Dossier vide" and File Provider persists an empty manifest. For crypt
    /// remotes only, verify an empty response with a fresh Fs and finally a
    /// recursive listing before accepting it as truly empty.
    public func list(remote: String, path: String = "") async throws -> [RemoteEntryDTO] {
        let first: [RemoteEntryDTO]
        var alreadyRefreshedFs = false
        do {
            first = try await listOnce(remote: remote, path: path, recurse: false)
        } catch {
            // Drime peut conserver brièvement un ancien mapping de répertoire
            // après un renommage. Un seul nouvel Fs est tenté pour les remotes
            // crypt ; un second 404 reste une erreur et ne devient jamais `[]`.
            guard Self.isDirectoryNotFoundListError(error), await isCryptRemote(remote) else {
                throw error
            }
            await LogService.shared.log(
                .info,
                category: "list",
                message: "Dossier crypt introuvable pour \(remote):\(path) — nouvel Fs puis unique retry",
                supportMessage: "operation=listing stage=retrying reason=missing_directory"
            )
            await invalidateListingCache()
            alreadyRefreshedFs = true
            first = try await listOnce(remote: remote, path: path, recurse: false)
        }
        guard first.isEmpty, await isCryptRemote(remote) else { return first }

        await LogService.shared.log(
            .info,
            category: "list",
            message: "Listing crypt vide inattendu pour \(remote):\(path) — vérification fraîche",
            supportMessage: "operation=listing stage=retrying"
        )

        let fresh: [RemoteEntryDTO]
        if alreadyRefreshedFs {
            fresh = first
        } else {
            await invalidateListingCache()
            fresh = try await listOnce(remote: remote, path: path, recurse: false)
        }
        guard fresh.isEmpty else { return fresh }

        // A recursive walk uses a different rclone traversal path on backends
        // exposing ListR/ListP. If it finds descendants while the non-recursive
        // call returned [], rebuild just the immediate children for this screen.
        let recursive = try await listOnce(remote: remote, path: path, recurse: true)
        let recovered = Self.immediateEntries(fromRecursive: recursive, under: path)
        if !recovered.isEmpty {
            await LogService.shared.log(
                .info,
                category: "list",
                message: "Listing crypt récupéré pour \(remote):\(path) — \(recovered.count) enfant(s) immédiat(s)",
                supportMessage: "operation=listing stage=completed count=\(recovered.count)"
            )
        }
        return recovered
    }

    static func isDirectoryNotFoundListError(_ error: Error) -> Bool {
        guard case let RcloneError.rcloneError(code, method, message) = error else {
            return false
        }
        return code == 404
            && method == "operations/list"
            && message.localizedCaseInsensitiveContains("directory not found")
    }

    private func isCryptRemote(_ remote: String) async -> Bool {
        let dump = try? await RcloneCore.shared.configDump()
        return dump?[remote]?["type"] == "crypt"
    }

    private func listOnce(remote: String, path: String, recurse: Bool) async throws -> [RemoteEntryDTO] {
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
            opt: ListOptions(recurse: recurse, noModTime: false, showHash: false)
        )
        let started = Date()
        await LogService.shared.log(
            .info,
            category: "list",
            message: "operations/list start remote=\(remote) path=\(path.isEmpty ? "/" : path) recurse=\(recurse)",
            supportMessage: "operation=listing stage=started recursive=\(recurse)"
        )
        let output: Output
        do {
            output = try await RcloneCore.shared.rpc("operations/list", input: input)
        } catch {
            let ms = Int(Date().timeIntervalSince(started) * 1000)
            await LogService.shared.log(
                .error,
                category: "list",
                message: "operations/list FAIL remote=\(remote) path=\(path) after \(ms)ms : \(error.localizedDescription)",
                supportMessage: Self.listFailureSupportMessage(
                    error,
                    durationMilliseconds: ms,
                    recurse: recurse
                )
            )
            throw error
        }
        let ms = Int(Date().timeIntervalSince(started) * 1000)
        // Log diagnostique : on liste les NOMS exacts renvoyés par rclone (📁
        // pour les dossiers) afin de distinguer une staleness serveur (le
        // nouveau dossier est absent de la réponse rclone) d'un bug d'affichage
        // (présent dans la réponse mais pas à l'écran). Plafonné pour les gros
        // dossiers.
        let names = output.list.map { ($0.isDir ? "📁" : "· ") + $0.name }
        let preview = names.count <= 40
            ? names.joined(separator: ", ")
            : names.prefix(40).joined(separator: ", ") + " …(+\(names.count - 40))"
        await LogService.shared.log(
            .info,
            category: "list",
            message: "operations/list ok remote=\(remote) path=\(path.isEmpty ? "/" : path) recurse=\(recurse) entries=\(output.list.count) in \(ms)ms · [\(preview)]",
            supportMessage: "operation=listing stage=completed count=\(output.list.count) duration_ms=\(ms) recursive=\(recurse)"
        )

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

    /// Collapse a recursive listing to the direct children of `path`.
    /// Directory entries are normally present in rclone's recursive response;
    /// a synthetic directory is added defensively when only a deeper descendant
    /// is returned by a backend.
    static func immediateEntries(
        fromRecursive entries: [RemoteEntryDTO],
        under path: String
    ) -> [RemoteEntryDTO] {
        let base = normalizedRemotePath(path)
        let prefix = base.isEmpty ? "" : "\(base)/"
        var order: [String] = []
        var byPath: [String: RemoteEntryDTO] = [:]

        for entry in entries {
            let fullPath = normalizedRemotePath(entry.pathInRemote)
            let relative: String
            if prefix.isEmpty {
                relative = fullPath
            } else {
                guard fullPath.hasPrefix(prefix) else { continue }
                relative = String(fullPath.dropFirst(prefix.count))
            }
            guard !relative.isEmpty else { continue }

            let components = relative.split(separator: "/", omittingEmptySubsequences: true)
            guard let first = components.first else { continue }
            let childName = String(first)
            let childPath = base.isEmpty ? childName : "\(base)/\(childName)"

            if components.count == 1 {
                if !byPath.keys.contains(childPath) { order.append(childPath) }
                byPath[childPath] = entry
            } else if !byPath.keys.contains(childPath) {
                order.append(childPath)
                byPath[childPath] = RemoteEntryDTO(
                    pathInRemote: childPath,
                    name: childName,
                    isDirectory: true,
                    size: 0,
                    modTime: entry.modTime,
                    mimeType: "inode/directory",
                    hashMD5: nil,
                    hashSHA1: nil
                )
            }
        }

        return order.compactMap { byPath[$0] }
    }

    private static func normalizedRemotePath(_ path: String) -> String {
        path.split(separator: "/", omittingEmptySubsequences: true)
            .joined(separator: "/")
    }

    private static func listFailureSupportMessage(
        _ error: Error,
        durationMilliseconds: Int,
        recurse: Bool
    ) -> String {
        var fields = [
            "operation=listing",
            "stage=failed",
            "duration_ms=\(max(durationMilliseconds, 0))",
            "recursive=\(recurse)",
        ]
        if case let RcloneError.rcloneError(code, _, message) = error,
           (100...599).contains(code) {
            fields.append("status=\(code)")
            let normalized = message.lowercased()
            if code == 404, normalized.contains("directory not found") {
                fields.append("reason=missing_directory")
            } else if code == 401 {
                fields.append("reason=authentication")
            } else if code == 403 {
                fields.append("reason=permission")
            } else if code == 408 {
                fields.append("reason=timeout")
            } else if code == 429 {
                fields.append("reason=rate_limit")
            } else if (500...599).contains(code) {
                fields.append("reason=connectivity")
            }
        }
        return fields.joined(separator: " ")
    }

    /// Liste récursive complète d'un dossier : renvoie TOUS les fichiers
    /// (et sous-dossiers) sous `<remote>:<path>` en un seul appel RPC. Utilisé
    /// par `BridgeFolderDownloader` pour télécharger un dossier via N workers
    /// parallèles au lieu de `sync/copy` (qui sature l'iCloud Drive `bird`
    /// daemon et gelait l'app). Renvoie uniquement les fichiers (pas les
    /// dossiers — les dossiers sont recréés localement à la volée).
    public func listRecursive(remote: String, path: String = "") async throws -> [RemoteEntryDTO] {
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
        let started = Date()
        await LogService.shared.log(
            .info, category: "list",
            message: "operations/list RECURSIVE start remote=\(remote) path=\(path.isEmpty ? "/" : path)"
        )
        let output: Output
        do {
            output = try await RcloneCore.shared.rpc("operations/list", input: Input(
                fs: "\(remote):",
                remote: path,
                opt: ListOptions(recurse: true, noModTime: true, showHash: false)
            ))
        } catch {
            let ms = Int(Date().timeIntervalSince(started) * 1000)
            await LogService.shared.log(
                .error, category: "list",
                message: "operations/list RECURSIVE FAIL remote=\(remote) path=\(path) after \(ms)ms : \(error.localizedDescription)"
            )
            throw error
        }
        let ms = Int(Date().timeIntervalSince(started) * 1000)
        let files = output.list.filter { !$0.isDir }
        await LogService.shared.log(
            .info, category: "list",
            message: "operations/list RECURSIVE ok remote=\(remote) path=\(path.isEmpty ? "/" : path) entries=\(output.list.count) files=\(files.count) in \(ms)ms"
        )
        return files.map { raw in
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

    public func stat(remote: String, path: String) async throws -> RemoteEntryDTO? {
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
            let item: RawItem?
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

        let output: Output = try await RcloneCore.shared.rpc(
            "operations/stat",
            input: Input(
                fs: "\(remote):",
                remote: path,
                opt: ListOptions(recurse: false, noModTime: false, showHash: true)
            )
        )
        guard let raw = output.item else { return nil }
        return RemoteEntryDTO(
            pathInRemote: raw.path,
            name: raw.name.isEmpty ? (path as NSString).lastPathComponent : raw.name,
            isDirectory: raw.isDir,
            size: max(raw.size, 0),
            modTime: Self.parseRcloneTime(raw.modTime),
            mimeType: raw.mimeType,
            hashMD5: raw.hashes?["md5"],
            hashSHA1: raw.hashes?["sha1"]
        )
    }

    public func size(remote: String, path: String) async throws -> RemoteSizeDTO {
        struct Input: Encodable {
            let fs: String
        }
        struct Output: Decodable {
            let count: Int64
            let bytes: Int64
            let sizeless: Int64?
        }
        let fs = path.isEmpty ? "\(remote):" : "\(remote):\(path)"
        let output: Output = try await RcloneCore.shared.rpc("operations/size", input: Input(fs: fs))
        return RemoteSizeDTO(count: output.count, bytes: output.bytes, sizeless: output.sizeless ?? 0)
    }

    // MARK: Remote space

    /// `operations/about` for a remote (when the backend supports it).
    /// Cache 60 s par remote + dedup inflight : si plusieurs vues
    /// demandent simultanément le quota du même remote, un seul RPC
    /// est envoyé et toutes attendent le même résultat.
    public func space(remote: String) async throws -> RemoteSpaceDTO {
        if let cached = spaceCache[remote], cached.expires > Date() {
            return cached.value
        }
        if let inflight = spaceInflight[remote] {
            return try await inflight.value
        }
        let task = Task<RemoteSpaceDTO, Error> {
            struct Input: Encodable { let fs: String }
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
        spaceInflight[remote] = task
        defer { spaceInflight[remote] = nil }
        do {
            let value = try await task.value
            spaceCache[remote] = (value, Date().addingTimeInterval(Self.spaceCacheTTL))
            return value
        } catch {
            throw error
        }
    }

    /// Invalide le cache `operations/about` pour forcer un refresh au
    /// prochain appel (par ex. après import de config ou pull-to-refresh).
    public func invalidateSpaceCache() {
        spaceCache.removeAll()
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
