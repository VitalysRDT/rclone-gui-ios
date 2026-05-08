//
//  MockRcloneEngine.swift
//  Rclone GUI — Core
//
//  Stand-in engine used while RcloneKit.xcframework is not yet wired.
//  Where possible, the mock answers from the actually-imported
//  rclone.conf (read via ConfigStore + parsed as INI). That way the
//  user can SEE their remotes even before building librclone — handy
//  to validate the import flow.
//
//  What the mock cannot do : list folder contents, run a transfer,
//  stream media. Those still require the real librclone backing.
//

import Foundation

public struct MockRcloneEngine: RcloneEngine {
    public init() {}

    public func initialize() async throws {
        // no-op
    }

    public func rpcRaw(method: String, inputJSON: String) async throws -> String {
        switch method {
        case "core/version":
            return #"{"version":"v1.68.0-mock","isGit":false,"goVersion":"go1.22.0","os":"ios","arch":"arm64"}"#

        case "config/listremotes":
            return try await renderListRemotes()

        case "config/dump":
            return try await renderConfigDump()

        case "operations/list":
            return #"{"list":[]}"#

        case "operations/about":
            return #"{}"#

        case "core/stats":
            return #"{"bytes":0,"speed":0,"totalBytes":0,"transfers":0,"elapsedTime":0,"transferring":[]}"#

        case "core/quit":
            return #"{}"#

        default:
            throw RcloneError.rpcFailed(
                method: method,
                message: "MockRcloneEngine has no canned response for '\(method)'. Build et intégrer RcloneKit.xcframework pour utiliser le vrai moteur."
            )
        }
    }

    // MARK: - Conf-aware responses

    private func renderListRemotes() async throws -> String {
        let parsed = await loadParsedRemotes()
        let names = parsed.map { $0.name }
        let payload: [String: Any] = ["remotes": names]
        let data = try JSONSerialization.data(withJSONObject: payload)
        return String(decoding: data, as: UTF8.self)
    }

    private func renderConfigDump() async throws -> String {
        let parsed = await loadParsedRemotes()
        var dump: [String: [String: String]] = [:]
        for entry in parsed {
            dump[entry.name] = ["type": entry.type]
        }
        let data = try JSONSerialization.data(withJSONObject: dump)
        return String(decoding: data, as: UTF8.self)
    }

    private func loadParsedRemotes() async -> [(name: String, type: String)] {
        let stored: Data?
        do {
            stored = try await ConfigStore.shared.load()
        } catch {
            return []
        }
        guard let data = stored else { return [] }
        return Self.parseRcloneConf(data)
    }

    // MARK: - INI parser (rclone.conf is INI with `key = value` lines)

    static func parseRcloneConf(_ data: Data) -> [(name: String, type: String)] {
        guard let text = String(data: data, encoding: .utf8) else { return [] }

        var result: [(name: String, type: String)] = []
        var currentName: String?
        var currentType: String = "unknown"

        func flush() {
            if let name = currentName {
                result.append((name: name, type: currentType))
            }
        }

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line.hasPrefix("#") || line.hasPrefix(";") { continue }

            if line.hasPrefix("[") && line.hasSuffix("]") {
                flush()
                let name = String(line.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                currentName = name
                currentType = "unknown"
                continue
            }

            // key = value
            guard let equalIdx = line.firstIndex(of: "=") else { continue }
            let key = line[..<equalIdx].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: equalIdx)...].trimmingCharacters(in: .whitespaces)
            if key == "type" {
                currentType = value
            }
        }
        flush()
        return result
    }
}
