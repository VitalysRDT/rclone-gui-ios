//
//  FileProviderManager.swift
//  Rclone GUI — Services
//
//  Registers the single Rclone GUI FileProvider domain when the app
//  launches (and the extension target is enabled). Phase D v1 scope:
//  domain registration + signaling. The actual fetch/enumerate logic
//  lives in the extension target (FileProvider/).
//
//  IPC pattern (per PRD FR-045): the extension is a thin client. When
//  it needs bytes, it writes a request to the App Group container and
//  posts a Darwin Notification. The main app observes, fetches via
//  librclone, writes the file to the cache, and signals back.
//

import Foundation
#if canImport(FileProvider)
import FileProvider
#endif

@MainActor
public final class FileProviderManager {
    public static let shared = FileProviderManager()
    private init() {}

    public static let domainIdentifier = NSFileProviderDomainIdentifier("com.rougetet.rclone-gui.main")
    public static let domainDisplayName = "Rclone GUI"

    /// Register the single FileProvider domain. No-op if the extension
    /// target is not built or not provisioned.
    public func registerDomain() async {
        #if canImport(FileProvider)
        let domain = NSFileProviderDomain(
            identifier: Self.domainIdentifier,
            displayName: Self.domainDisplayName
        )
        await LogService.shared.log(
            AppGroup.isAppGroupProvisioned ? .info : .error,
            category: "fileprovider",
            message: AppGroup.isAppGroupProvisioned
                ? "App Group disponible pour FileProvider : \(AppGroup.identifier)"
                : "App Group indisponible : l'extension Fichiers ne pourra pas partager le manifest."
        )
        do {
            try await NSFileProviderManager.add(domain)
            await LogService.shared.log(
                .info,
                category: "fileprovider",
                message: "Domaine FileProvider enregistré : \(Self.domainIdentifier.rawValue)"
            )
        } catch {
            await LogService.shared.log(
                .debug,
                category: "fileprovider",
                message: "Enregistrement FileProvider ignoré/échoué : \(error.localizedDescription)"
            )
        }
        #endif
    }

    public func resetDomain() async {
        #if canImport(FileProvider)
        let domain = NSFileProviderDomain(
            identifier: Self.domainIdentifier,
            displayName: Self.domainDisplayName
        )
        do {
            try? await NSFileProviderManager.remove(domain)
            try await NSFileProviderManager.add(domain)
            await LogService.shared.log(
                .info,
                category: "fileprovider",
                message: "Domaine FileProvider réinitialisé : \(Self.domainIdentifier.rawValue)"
            )

            // Sans manifest réécrit + signalEnumerator(.rootContainer) après
            // re-add, iOS 16+ ne déclenche pas l'énumération de la racine et
            // affiche "Contenu indisponible".
            if let remotes = try? await RemoteService.shared.listRemoteSummaries() {
                await writeRemotesManifest(remotes)
            }
            signalRefresh(remote: "", path: "")
        } catch {
            await LogService.shared.log(
                .error,
                category: "fileprovider",
                message: "Réinitialisation FileProvider échouée : \(error.localizedDescription)"
            )
        }
        #endif
    }

    public func writeRemotesManifest(_ remotes: [RemoteSummaryDTO]) async {
        struct ManifestEntry: Encodable {
            let name: String
            let type: String
            let isCrypt: Bool
        }

        do {
            let manifestDir = AppGroup.containerURL.appending(path: "manifest", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: manifestDir, withIntermediateDirectories: true)
            let payload = remotes.map { ManifestEntry(name: $0.name, type: $0.type, isCrypt: $0.isCrypt) }
            let data = try JSONEncoder().encode(payload)
            try data.write(to: manifestDir.appending(path: "remotes.json"), options: [.atomic, .completeFileProtection])
            await LogService.shared.log(
                .debug,
                category: "fileprovider",
                message: "Manifest remotes écrit : \(remotes.count) remote(s)."
            )
            signalRefresh(remote: "", path: "")
        } catch {
            Task {
                await LogService.shared.log(.error, category: "fileprovider", message: "Manifest FileProvider non écrit : \(error.localizedDescription)")
            }
        }
    }

    public func writeFolderManifest(remote: String, path: String, entries: [RemoteEntryDTO]) async {
        struct ManifestEntry: Encodable {
            let path: String
            let name: String
            let isDirectory: Bool
            let size: Int64
            let modTime: Date
            let mimeType: String?
        }

        do {
            let manifestDir = AppGroup.containerURL
                .appending(path: "manifest", directoryHint: .isDirectory)
                .appending(path: "folders", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: manifestDir, withIntermediateDirectories: true)

            let key = "\(remote):\(path)"
            let safe = key.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? UUID().uuidString
            let payload = entries.map {
                ManifestEntry(
                    path: $0.pathInRemote,
                    name: $0.name,
                    isDirectory: $0.isDirectory,
                    size: $0.size,
                    modTime: $0.modTime,
                    mimeType: $0.mimeType
                )
            }
            let data = try JSONEncoder().encode(payload)
            try data.write(to: manifestDir.appending(path: safe).appendingPathExtension("json"), options: [.atomic])
            signalRefresh(remote: remote, path: path)
        } catch {
            Task {
                await LogService.shared.log(.error, category: "fileprovider", message: "Manifest dossier FileProvider non écrit : \(error.localizedDescription)")
            }
        }
    }

    /// Signal that the cached enumeration for `<remote>:<path>` is stale.
    public func signalRefresh(remote: String, path: String = "") {
        #if canImport(FileProvider)
        let manager = NSFileProviderManager(for: NSFileProviderDomain(
            identifier: Self.domainIdentifier,
            displayName: Self.domainDisplayName
        ))
        let identifier: NSFileProviderItemIdentifier = remote.isEmpty && path.isEmpty
            ? .rootContainer
            : NSFileProviderItemIdentifier("\(remote):\(path)")
        manager?.signalEnumerator(for: identifier) { _ in }
        #endif
    }

    /// Tear down the domain (used by Settings → Reset).
    public func unregisterDomain() async {
        #if canImport(FileProvider)
        let domain = NSFileProviderDomain(
            identifier: Self.domainIdentifier,
            displayName: Self.domainDisplayName
        )
        try? await NSFileProviderManager.remove(domain)
        #endif
    }

    public func diagnosticEntries() -> [LogEntry] {
        let url = AppGroup.fileProviderDiagnosticsURL
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else {
            return []
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        return text
            .split(separator: "\n")
            .compactMap { rawLine -> LogEntry? in
                let line = String(rawLine)
                guard let separatorRange = line.range(of: " [") else {
                    return LogEntry(level: .debug, category: "fileprovider-extension", message: line)
                }

                let timestampText = String(line[..<separatorRange.lowerBound])
                let remainder = String(line[separatorRange.upperBound...])
                let timestamp = formatter.date(from: timestampText) ?? .now
                let level: LogLevel
                let message: String
                if remainder.hasPrefix("ERROR] ") {
                    level = .error
                    message = String(remainder.dropFirst(7))
                } else if remainder.hasPrefix("DEBUG] ") {
                    level = .debug
                    message = String(remainder.dropFirst(7))
                } else if remainder.hasPrefix("INFO] ") {
                    level = .info
                    message = String(remainder.dropFirst(6))
                } else {
                    level = .debug
                    message = remainder
                }
                return LogEntry(
                    timestamp: timestamp,
                    level: level,
                    category: "fileprovider-extension",
                    message: message
                )
            }
    }

    public func clearDiagnostics() {
        try? FileManager.default.removeItem(at: AppGroup.fileProviderDiagnosticsURL)
    }
}
