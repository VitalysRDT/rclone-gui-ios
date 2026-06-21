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

    // Coalescing des signalEnumerator : iOS Files.app recharge à chaque
    // signal, donc 100 manifests écrits en rafale = 100 reloads inutiles.
    // On collecte les identifiers et on flush en un seul batch après 500ms
    // d'inactivité.
    private var pendingSignals: Set<String> = []
    private var signalFlushTask: Task<Void, Never>?
    private static let signalDebounce: Duration = .milliseconds(500)

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
            // L'ajout a échoué — typiquement un domaine ORPHELIN laissé par une
            // réinstallation Xcode (⇧⌘K + réinstall) : iOS garde une entrée
            // incohérente et le domaine n'apparaît PLUS dans Fichiers, tandis que
            // `add` est rejeté. On s'auto-répare : remove puis add, puis on
            // réécrit le manifest + signale la racine pour que Fichiers ré-énumère.
            await LogService.shared.log(
                .error,
                category: "fileprovider",
                message: "Enregistrement FileProvider échoué (\(error.localizedDescription)) → récupération remove+add"
            )
            do {
                try? await NSFileProviderManager.remove(domain)
                try await NSFileProviderManager.add(domain)
                if let remotes = try? await RemoteService.shared.listRemoteSummaries() {
                    await writeRemotesManifest(remotes)
                }
                signalRefresh(remote: "", path: "")
                await LogService.shared.log(
                    .info,
                    category: "fileprovider",
                    message: "Domaine FileProvider récupéré (remove+add) : \(Self.domainIdentifier.rawValue)"
                )
            } catch {
                await LogService.shared.log(
                    .error,
                    category: "fileprovider",
                    message: "Récupération FileProvider échouée : \(error.localizedDescription). Essaie : Réglages → Logs → « Réinitialiser Fichiers », ou supprime+réinstalle l'app."
                )
            }
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
    /// Debounced 500ms : empêche un burst de manifest writes (100 dossiers
    /// énumérés à la suite) de provoquer 100 reloads dans Files.app.
    public func signalRefresh(remote: String, path: String = "") {
        let key = remote.isEmpty && path.isEmpty
            ? "__ROOT__"
            : "\(remote):\(path)"
        pendingSignals.insert(key)
        signalFlushTask?.cancel()
        signalFlushTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.signalDebounce)
            guard !Task.isCancelled, let self else { return }
            self.flushPendingSignals()
        }
    }

    /// Flush immédiat : utilisé par les chemins critiques (resetDomain) qui
    /// ne peuvent pas attendre les 500ms du debounce.
    public func flushSignalsNow() {
        signalFlushTask?.cancel()
        signalFlushTask = nil
        flushPendingSignals()
    }

    private func flushPendingSignals() {
        #if canImport(FileProvider)
        let signals = pendingSignals
        pendingSignals.removeAll(keepingCapacity: true)
        guard !signals.isEmpty else { return }
        let manager = NSFileProviderManager(for: NSFileProviderDomain(
            identifier: Self.domainIdentifier,
            displayName: Self.domainDisplayName
        ))
        for key in signals {
            let identifier: NSFileProviderItemIdentifier = key == "__ROOT__"
                ? .rootContainer
                : NSFileProviderItemIdentifier(key)
            manager?.signalEnumerator(for: identifier) { _ in }
        }
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

    /// Supprime tous les folder manifests d'un remote après sa suppression,
    /// pour que l'extension Fichiers ne serve plus son contenu en cache (sinon
    /// un remote effacé reste navigable depuis Fichiers / les Récents).
    public func purgeFolderManifests(remote: String) {
        let dir = AppGroup.containerURL
            .appending(path: "manifest", directoryHint: .isDirectory)
            .appending(path: "folders", directoryHint: .isDirectory)
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil
        ) else { return }
        // Les manifests sont nommés percentEncode("<remote>:<path>").json ; le
        // séparateur ":" encodé (%3A) évite de matcher un remote au nom plus long.
        let prefix = "\(remote):".addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "\(remote):"
        for file in files where file.deletingPathExtension().lastPathComponent.hasPrefix(prefix) {
            try? FileManager.default.removeItem(at: file)
        }
        signalRefresh(remote: remote, path: "")
    }

    /// Supprime tous les folder manifests (après un wipe complet de la config).
    public func purgeAllFolderManifests() {
        let dir = AppGroup.containerURL
            .appending(path: "manifest", directoryHint: .isDirectory)
            .appending(path: "folders", directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: dir)
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
