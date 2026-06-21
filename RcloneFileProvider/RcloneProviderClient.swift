//
//  RcloneProviderClient.swift
//  RcloneFileProvider
//
//  Minimal rclone client for the FileProvider extension.
//

import CryptoKit
import FileProvider
import Foundation
import Security
import Darwin

#if canImport(RcloneKit)
import RcloneKit
#endif

struct FPRemoteEntry: Sendable, Hashable {
    let path: String
    let name: String
    let isDirectory: Bool
    let size: Int64
    let modTime: Date
    let mimeType: String?
}

actor RcloneProviderClient {
    static let shared = RcloneProviderClient()

    private let masterKeyTag = "com.rougetet.rclone-gui.master-key"
    private var initialized = false
    private struct EmptyInput: Encodable {}

    func listRemoteNames() async throws -> [String] {
        struct Response: Decodable { let remotes: [String] }
        let response: Response = try await rpc("config/listremotes")
        return response.remotes
    }

    func list(remote: String, path: String) async throws -> [FPRemoteEntry] {
        struct Input: Encodable {
            let fs: String
            let remote: String
            let opt: Options
        }
        struct Options: Encodable {
            let recurse: Bool
            let noModTime: Bool
            let showHash: Bool
        }
        struct Output: Decodable { let list: [RawItem] }
        struct RawItem: Decodable {
            let path: String
            let name: String
            let size: Int64
            let mimeType: String?
            let modTime: String?
            let isDir: Bool

            enum CodingKeys: String, CodingKey {
                case path = "Path"
                case name = "Name"
                case size = "Size"
                case mimeType = "MimeType"
                case modTime = "ModTime"
                case isDir = "IsDir"
            }
        }

        let output: Output = try await rpc(
            "operations/list",
            input: Input(
                fs: "\(remote):",
                remote: path,
                opt: Options(recurse: false, noModTime: false, showHash: false)
            )
        )
        return output.list.map {
            FPRemoteEntry(
                path: $0.path,
                name: $0.name,
                isDirectory: $0.isDir,
                size: max($0.size, 0),
                modTime: Self.parseDate($0.modTime),
                mimeType: $0.mimeType
            )
        }
    }

    func stat(remote: String, path: String) async throws -> FPRemoteEntry? {
        struct Input: Encodable {
            let fs: String
            let remote: String
        }
        struct Output: Decodable { let item: RawItem? }
        struct RawItem: Decodable {
            let path: String
            let name: String
            let size: Int64
            let mimeType: String?
            let modTime: String?
            let isDir: Bool

            enum CodingKeys: String, CodingKey {
                case path = "Path"
                case name = "Name"
                case size = "Size"
                case mimeType = "MimeType"
                case modTime = "ModTime"
                case isDir = "IsDir"
            }
        }
        let output: Output = try await rpc("operations/stat", input: Input(fs: "\(remote):", remote: path))
        guard let item = output.item else { return nil }
        return FPRemoteEntry(
            path: item.path,
            name: item.name.isEmpty ? (path as NSString).lastPathComponent : item.name,
            isDirectory: item.isDir,
            size: max(item.size, 0),
            modTime: Self.parseDate(item.modTime),
            mimeType: item.mimeType
        )
    }

    func download(remote: String, path: String, to localURL: URL) async throws -> FPRemoteEntry? {
        FileProviderBridge.appendDiagnostic("download start remote=\(remote) path=\(path)")
        try FileManager.default.createDirectory(at: localURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileProviderBridge.appendDiagnostic("download dir ready, calling copyFile")
        let jobID = try await copyFile(
            srcFs: "\(remote):",
            srcPath: path,
            dstFs: localURL.deletingLastPathComponent().path,
            dstPath: localURL.lastPathComponent
        )
        FileProviderBridge.appendDiagnostic("download copyFile job=\(jobID), waiting")
        try await waitForJob(jobID)
        FileProviderBridge.appendDiagnostic("download job=\(jobID) finished, calling stat")
        let result = try await stat(remote: remote, path: path)
        FileProviderBridge.appendDiagnostic("download stat done, returning")
        return result
    }

    /// Téléchargement LÉGER directement dans l'extension via le bridge loopback
    /// (`RclonebridgeStartFileHTTP`) + URLSession en streaming. Bien plus économe
    /// en mémoire que `download(...)` (operations/copyfile + transfer manager
    /// rclone), qui faisait jetsam dans l'.appex. Utilisé en repli quand l'app
    /// principale n'est pas active pour assurer le relais → Fichiers fonctionne
    /// sans avoir à ouvrir l'app.
    func downloadViaBridge(remote: String, path: String, to localURL: URL, progress: Progress?) async throws {
        try await ensureInitialized()
        #if canImport(RcloneKit)
        FileProviderBridge.appendDiagnostic("downloadViaBridge start remote=\(remote)")
        let raw = RclonebridgeStartFileHTTP(remote, path)
        guard let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sessionID = object["id"] as? String,
              let urlString = object["url"] as? String,
              let url = URL(string: urlString),
              !sessionID.isEmpty else {
            throw providerError("Bridge StartFileHTTP a renvoyé une réponse invalide : \(raw)")
        }
        defer { RclonebridgeStopFileHTTP(sessionID) }
        try FileManager.default.createDirectory(
            at: localURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try? FileManager.default.removeItem(at: localURL)
        try await ExtensionBridgeDownloader(dest: localURL, progress: progress).download(from: url)
        FileProviderBridge.appendDiagnostic("downloadViaBridge done remote=\(remote)")
        #else
        throw providerError("RcloneKit indisponible pour le download direct")
        #endif
    }

    func upload(localURL: URL, remote: String, path: String) async throws -> FPRemoteEntry? {
        let jobID = try await copyFile(
            srcFs: localURL.deletingLastPathComponent().path,
            srcPath: localURL.lastPathComponent,
            dstFs: "\(remote):",
            dstPath: path
        )
        try await waitForJob(jobID)
        return try await stat(remote: remote, path: path)
    }

    func mkdir(remote: String, path: String) async throws {
        struct Input: Encodable {
            let fs: String
            let remote: String
        }
        struct Empty: Decodable {}
        let _: Empty = try await rpc("operations/mkdir", input: Input(fs: "\(remote):", remote: path))
    }

    func delete(remote: String, path: String, isDirectory: Bool) async throws {
        struct Input: Encodable {
            let fs: String
            let remote: String
            let _async: Bool
        }
        let method = isDirectory ? "operations/purge" : "operations/deletefile"
        let response: JobIDResponse = try await rpc(method, input: Input(fs: "\(remote):", remote: path, _async: true))
        try await waitForJob(response.jobid)
    }

    private func copyFile(srcFs: String, srcPath: String, dstFs: String, dstPath: String) async throws -> Int {
        struct Input: Encodable {
            let srcFs: String
            let srcRemote: String
            let dstFs: String
            let dstRemote: String
            let _async: Bool
        }
        let response: JobIDResponse = try await rpc(
            "operations/copyfile",
            input: Input(srcFs: srcFs, srcRemote: srcPath, dstFs: dstFs, dstRemote: dstPath, _async: true)
        )
        return response.jobid
    }

    private struct JobIDResponse: Decodable {
        let jobid: Int
    }

    private func waitForJob(_ jobID: Int) async throws {
        struct Input: Encodable { let jobid: Int }
        struct Status: Decodable {
            let finished: Bool
            let success: Bool
            let error: String?
        }

        while !Task.isCancelled {
            try await Task.sleep(for: .milliseconds(500))
            let status: Status = try await rpc("job/status", input: Input(jobid: jobID))
            guard status.finished else { continue }
            if status.success { return }
            throw NSError(
                domain: NSFileProviderErrorDomain,
                code: NSFileProviderError.serverUnreachable.rawValue,
                userInfo: [NSLocalizedDescriptionKey: status.error ?? "rclone job failed"]
            )
        }
        throw CancellationError()
    }

    private func rpc<O: Decodable>(_ method: String) async throws -> O {
        return try await rpc(method, input: EmptyInput())
    }

    private func rpc<I: Encodable, O: Decodable>(_ method: String, input: I) async throws -> O {
        try await ensureInitialized()
        let inputData = try JSONEncoder().encode(input)
        let inputJSON = String(decoding: inputData, as: UTF8.self)
        let outputJSON = try rpcRaw(method: method, inputJSON: inputJSON)
        return try JSONDecoder().decode(O.self, from: Data(outputJSON.utf8))
    }

    private func rpcRaw(method: String, inputJSON: String) throws -> String {
        #if canImport(RcloneKit)
        guard let result = RclonebridgeRPC(method, inputJSON) else {
            throw providerError("RcloneKit returned nil")
        }
        guard (200..<300).contains(Int(result.status)) else {
            throw providerError(result.output)
        }
        return result.output
        #else
        throw providerError("RcloneKit is not linked in the FileProvider extension")
        #endif
    }

    private func ensureInitialized() async throws {
        guard !initialized else { return }
        FileProviderBridge.appendDiagnostic("ensureInitialized: writing decrypted config")
        let confURL = try writeDecryptedConfigToTempFile()
        FileProviderBridge.appendDiagnostic("ensureInitialized: config written at=\(confURL.path)")
        #if canImport(RcloneKit)
        let workingDirectory = FileProviderBridge.containerURL
            .appending(path: "Library", directoryHint: .isDirectory)
            .appending(path: "RcloneRuntime", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
        _ = workingDirectory.path.withCString { chdir($0) }
        setenv("PWD", workingDirectory.path, 1)
        setenv("HOME", FileProviderBridge.containerURL.path, 1)
        setenv("TMPDIR", NSTemporaryDirectory(), 1)
        FileProviderBridge.appendDiagnostic("ensureInitialized: env set, calling RclonebridgeInitialize")
        RclonebridgeSetEnv("RCLONE_CONFIG", confURL.path)
        RclonebridgeInitialize()
        FileProviderBridge.appendDiagnostic("ensureInitialized: RclonebridgeInitialize returned")
        struct SetPathInput: Encodable { let path: String }
        let payload = String(decoding: try JSONEncoder().encode(SetPathInput(path: confURL.path)), as: UTF8.self)
        _ = try rpcRaw(method: "config/setpath", inputJSON: payload)
        initialized = true
        FileProviderBridge.appendDiagnostic("ensureInitialized: done")
        #else
        FileProviderBridge.appendDiagnostic("ensureInitialized: RcloneKit not available")
        throw providerError("RcloneKit is not available")
        #endif
    }

    private func writeDecryptedConfigToTempFile() throws -> URL {
        let encryptedURL = FileProviderBridge.containerURL.appending(path: "rclone.conf.enc")
        guard FileManager.default.fileExists(atPath: encryptedURL.path) else {
            throw providerError("Aucune configuration rclone importée")
        }
        let envelope = try Data(contentsOf: encryptedURL)
        let keyData = try fetchMasterKeyData()
        let key = SymmetricKey(data: keyData)
        let box = try ChaChaPoly.SealedBox(combined: envelope)
        let plaintext = try ChaChaPoly.open(box, using: key)
        let target = FileProviderBridge.containerURL.appending(path: "rclone-fileprovider.conf")
        try plaintext.write(to: target, options: [.atomic, .completeFileProtection])
        return target
    }

    private func fetchMasterKeyData() throws -> Data {
        if let sharedGroup = FileProviderBridge.keychainAccessGroup,
           let data = try fetchMasterKeyData(accessGroup: sharedGroup) {
            return data
        }
        if let data = try fetchMasterKeyData(accessGroup: nil) {
            return data
        }
        throw providerError("Cle Keychain rclone introuvable. Ouvrez Rclone GUI une fois, puis relancez Files.")
    }

    private func fetchMasterKeyData(accessGroup: String?) throws -> Data? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: masterKeyTag,
        ]
        if let accessGroup, !accessGroup.isEmpty {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw providerError("Keychain read failed (OSStatus \(status))")
        }
        return data
    }

    private static func parseDate(_ raw: String?) -> Date {
        guard let raw, !raw.isEmpty else { return .distantPast }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: raw) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: raw) ?? .distantPast
    }

    private func providerError(_ message: String) -> NSError {
        NSError(
            domain: NSFileProviderErrorDomain,
            code: NSFileProviderError.serverUnreachable.rawValue,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}

/// Télécharge un fichier depuis le bridge loopback via `URLSession` en streaming
/// (faible mémoire — pas de buffering du fichier entier), met à jour le `Progress`
/// et déplace le temp vers `dest` à la fin. Pendant du `BridgeFileDownloader`
/// côté app, dupliqué ici car l'extension est une cible séparée.
final class ExtensionBridgeDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let dest: URL
    private let progress: Progress?
    private var continuation: CheckedContinuation<Void, Error>?
    private var session: URLSession?
    private var moveError: Error?

    init(dest: URL, progress: Progress?) {
        self.dest = dest
        self.progress = progress
        super.init()
    }

    func download(from url: URL) async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                self.continuation = cont
                let config = URLSessionConfiguration.default
                config.timeoutIntervalForRequest = 60
                config.requestCachePolicy = .reloadIgnoringLocalCacheData
                let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
                self.session = session
                session.downloadTask(with: url).resume()
            }
        } onCancel: {
            self.session?.invalidateAndCancel()
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard let progress, totalBytesExpectedToWrite > 0 else { return }
        progress.totalUnitCount = totalBytesExpectedToWrite
        progress.completedUnitCount = totalBytesWritten
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? fm.removeItem(at: dest)
            try fm.moveItem(at: location, to: dest)
        } catch {
            moveError = error
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        session.finishTasksAndInvalidate()
        let cont = continuation
        continuation = nil
        if let moveError { cont?.resume(throwing: moveError); return }
        if let error { cont?.resume(throwing: error); return }
        if let http = task.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            cont?.resume(throwing: NSError(
                domain: NSFileProviderErrorDomain,
                code: NSFileProviderError.serverUnreachable.rawValue,
                userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode) (download direct extension)"]
            ))
            return
        }
        cont?.resume(returning: ())
    }
}
