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
            let purgedRequests = purgePendingEnumerationRequests()
            purgeAllFolderManifests()
            try? await NSFileProviderManager.remove(domain)
            try await NSFileProviderManager.add(domain)
            await LogService.shared.log(
                .info,
                category: "fileprovider",
                message: "Domaine FileProvider réinitialisé : \(Self.domainIdentifier.rawValue) (\(purgedRequests) requête(s) de listing purgée(s))"
            )

            // Sans manifest réécrit + signalEnumerator(.rootContainer) après
            // re-add, iOS 16+ ne déclenche pas l'énumération de la racine et
            // affiche "Contenu indisponible".
            if let remotes = try? await RemoteService.shared.listRemoteSummaries() {
                await writeRemotesManifest(remotes)
            }
            signalRefresh(remote: "", path: "")
            flushSignalsNow()
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

    @discardableResult
    public func writeFolderManifest(
        remote: String,
        path: String,
        entries: [RemoteEntryDTO]
    ) async -> Bool {
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
            return true
        } catch {
            Task {
                await LogService.shared.log(.error, category: "fileprovider", message: "Manifest dossier FileProvider non écrit : \(error.localizedDescription)")
            }
            return false
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

    /// Réglages → Réinitialiser Fichiers doit aussi vider les listings IPC qui
    /// ont survécu à un ancien timeout. Les téléchargements complets restent
    /// intacts : leur durée de vie est indépendante de l'énumération.
    @discardableResult
    private func purgePendingEnumerationRequests() -> Int {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: AppGroup.pendingFetchesDir,
            includingPropertiesForKeys: nil
        ) else { return 0 }

        var count = 0
        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let pending = try? JSONDecoder().decode(AppGroupPendingFetch.self, from: data),
                  pending.kind == "list" || pending.kind == "stream-url" else {
                continue
            }
            try? fm.removeItem(at: file)
            try? fm.removeItem(at: file.appendingPathExtension("status"))
            try? fm.removeItem(at: file.appendingPathExtension("error"))
            count += 1
        }
        return count
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

    /// Version exportable des diagnostics de l'extension. Le texte brut peut
    /// contenir identifiants File Provider, remotes, chemins, noms de fichiers ou
    /// URLs. L'export support ne conserve que l'opération, l'étape et quelques
    /// métriques non identifiantes.
    public func supportDiagnosticEntries() -> [LogEntry] {
        diagnosticEntries().map { entry in
            let message = Self.supportDiagnosticMessage(entry.message)
            let failed = message.contains("stage=failed")
            return LogEntry(
                timestamp: entry.timestamp,
                level: failed ? .error : entry.level,
                category: "fileprovider-extension",
                message: message,
                supportMessage: message
            )
        }
    }

    nonisolated static func supportDiagnosticMessage(_ message: String) -> String {
        let lower = message.lowercased()

        let operation: String
        if lower.hasPrefix("upload") { operation = "upload" }
        else if lower.hasPrefix("create") { operation = "create" }
        else if lower.hasPrefix("modify") { operation = "modify" }
        else if lower.hasPrefix("delete") { operation = "delete" }
        else if lower.hasPrefix("ipc stream") { operation = "stream" }
        else if lower.hasPrefix("download")
            || lower.hasPrefix("ipc fetch")
            || lower.hasPrefix("fetchcontents")
            || lower.hasPrefix("fetchpartialcontents") { operation = "download" }
        else if lower.hasPrefix("enumerat")
            || lower.hasPrefix("ipc list")
            || lower.hasPrefix("manifest")
            || lower.hasPrefix("folder manifest")
            || lower.hasPrefix("write folder manifest")
            || lower.hasPrefix("invalidate folder manifest")
            || lower.hasPrefix("stale manifest")
            || lower.hasPrefix("relay app inactive") { operation = "listing" }
        else if lower.hasPrefix("vault") || lower.hasPrefix("subscription gate") { operation = "vault" }
        else if lower.hasPrefix("extension init domain")
            || lower.hasPrefix("remotes manifest")
            || lower.hasPrefix("current root") { operation = "domain" }
        else { operation = "other" }

        let stage: String
        if lower.contains("failed") || lower.contains("error") { stage = "failed" }
        else if lower.contains("timeout") { stage = "timeout" }
        else if lower.contains("cancel") { stage = "cancelled" }
        else if lower.contains("done") || lower.contains("ready") || lower.contains("completed") { stage = "completed" }
        else if lower.contains("ack") { stage = "acknowledged" }
        else if lower.contains("start") || lower.contains("request") { stage = "started" }
        else { stage = "event" }

        var fields = ["operation=\(operation)", "stage=\(stage)"]
        if trustedProviderCodePrefix(in: lower),
           let code = supportTrailingInteger(after: "code=", in: lower) {
            fields.append("code=\(code)")
        }
        return fields.joined(separator: " ")
    }

    private nonisolated static func trustedProviderCodePrefix(in message: String) -> Bool {
        message.hasPrefix("upload staging failed id=")
            || message.hasPrefix("upload remote failed id=")
            || message.hasPrefix("create failed remote=")
    }

    private nonisolated static func supportTrailingInteger(
        after marker: String,
        in message: String
    ) -> String? {
        guard let range = message.range(of: marker, options: .backwards) else { return nil }
        let suffix = message[range.upperBound...]
        guard !suffix.isEmpty, suffix.allSatisfy({ $0.isNumber || $0 == "-" }), Int(suffix) != nil else {
            return nil
        }
        return String(suffix)
    }

    public func clearDiagnostics() {
        try? FileManager.default.removeItem(at: AppGroup.fileProviderDiagnosticsURL)
    }
}
