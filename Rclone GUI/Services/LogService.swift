//
//  LogService.swift
//  Rclone GUI — Services
//
//  Lightweight in-memory ring buffer of log entries + export-to-file
//  helper. Phase E v1 ; Phase E2 will wire `core/log` rclone rc to
//  capture verbose rclone logs (-vv equivalent).
//

import Foundation
#if canImport(RcloneKit)
import RcloneKit
#endif

public enum LogLevel: String, Sendable, Codable {
    case info = "INFO"
    case debug = "DEBUG"
    case error = "ERROR"
}

public struct LogEntry: Sendable, Codable, Identifiable, Hashable {
    public let id: UUID
    public let timestamp: Date
    public let level: LogLevel
    public let category: String
    public let message: String
    /// Métadonnées déjà structurées par le producteur pour l'export support.
    /// Jamais dérivées d'un payload backend ou d'un chemin utilisateur.
    public let supportMessage: String?

    public nonisolated init(
        id: UUID = UUID(),
        timestamp: Date = .now,
        level: LogLevel,
        category: String,
        message: String,
        supportMessage: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.category = category
        self.message = message
        self.supportMessage = supportMessage
    }
}

public actor LogService {
    public static let shared = LogService()

    // Cap réduit à 1000 (vs 5000 historique) : suffit pour debug live,
    // divise par 5 l'empreinte mémoire en condition d'usage normal.
    // L'export reste possible via exportAsFile() pour garder l'historique.
    private let maxEntries = 1000
    private var ring: [LogEntry] = []
    // Pré-allocation pour éviter les reallocs successives lors des bursts.
    private var didReserveCapacity = false

    private init() {}

    /// Emit a one-shot diagnostic snapshot at boot. Useful in TestFlight
    /// where the user can't read Xcode console. Surfaces App Group state,
    /// ConfigStore presence, engine type — every fact that would otherwise
    /// require connecting a debugger to discover.
    public static func emitBoot() async {
        let isAppGroup = AppGroup.isAppGroupProvisioned
        await shared.log(
            isAppGroup ? .info : .error,
            category: "boot",
            message: isAppGroup
                ? "App Group OK : \(AppGroup.identifier)"
                : "App Group « \(AppGroup.identifier) » non provisionné — fallback vers Application Support. FileProvider ne pourra pas partager. Crée l'App Group sur Apple Developer Portal et réinstalle.",
            supportMessage: "operation=app_group stage=event state=\(isAppGroup ? "available" : "unavailable")"
        )
        await shared.log(
            .info,
            category: "boot",
            message: "Container : \(AppGroup.containerURL.path)",
            supportMessage: "operation=container stage=event state=available"
        )
        let hasConf = await ConfigStore.shared.hasStoredConf()
        await shared.log(
            hasConf ? .info : .info,
            category: "boot",
            message: hasConf
                ? "Configuration rclone importée détectée."
                : "Aucune configuration rclone importée — utilise Réglages → Importer.",
            supportMessage: "operation=configuration stage=event state=\(hasConf ? "present" : "absent")"
        )
        let isMock = await RcloneCore.shared.isMockEngine
        let engineDescription: String
        let engineSupportMessage: String
        if isMock {
            engineDescription = "Mock (pas de librclone embarqué)"
            engineSupportMessage = "operation=engine stage=event engine=mock"
        } else if let version = try? await RcloneCore.shared.version() {
            engineDescription = "Librclone \(version) (réel)"
            engineSupportMessage = "operation=engine stage=event version=\(version.lowercased())"
        } else {
            engineDescription = "Librclone (réel, version indisponible)"
            engineSupportMessage = "operation=engine stage=event engine=librclone"
        }
        await shared.log(
            .info,
            category: "boot",
            message: "Moteur rclone : \(engineDescription)",
            supportMessage: engineSupportMessage
        )
    }

    public func log(
        _ level: LogLevel,
        category: String,
        message: String,
        supportMessage: String? = nil
    ) {
        if !didReserveCapacity {
            ring.reserveCapacity(maxEntries)
            didReserveCapacity = true
        }
        let entry = LogEntry(
            level: level,
            category: category,
            message: message,
            supportMessage: supportMessage
        )
        ring.append(entry)
        if ring.count > maxEntries {
            // Trim par batch de 100 pour éviter une realloc à chaque insertion
            // une fois la capacité atteinte.
            let overflow = ring.count - maxEntries
            ring.removeFirst(max(overflow, 100))
        }
        #if DEBUG
        // Mirror vers la console Xcode en DEBUG : sans ça, le ring buffer
        // reste invisible quand on debug depuis Xcode (Cmd+R).
        let icon: String
        switch level {
        case .info:  icon = "ℹ️"
        case .debug: icon = "🔧"
        case .error: icon = "❌"
        }
        print("\(icon) [\(category)] \(message)")
        #endif
    }

    private static let bridgeDateParser: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// Phase E2 — récupère les lignes de log internes de rclone capturées par
    /// le bridge Go (slog) et les fond dans le ring sous la catégorie « rclone ».
    /// Polled par LogsView tant que l'écran est visible. No-op si le moteur réel
    /// (RcloneKit) n'est pas embarqué.
    public func ingestBridgeLogs() {
        #if canImport(RcloneKit)
        let raw = RclonebridgeDrainLogs()
        guard let data = raw.data(using: .utf8),
              let lines = try? JSONDecoder().decode([String].self, from: data),
              !lines.isEmpty else { return }
        for line in lines {
            let parts = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
            let timestamp = parts.count > 0 ? (Self.bridgeDateParser.date(from: String(parts[0])) ?? .now) : .now
            let levelStr = parts.count > 1 ? String(parts[1]) : "INFO"
            let message = parts.count > 2 ? String(parts[2]) : line
            let level: LogLevel
            switch levelStr {
            case "ERROR":  level = .error
            case "DEBUG":  level = .debug
            default:       level = .info   // INFO / NOTICE / WARNING
            }
            appendEntry(LogEntry(timestamp: timestamp, level: level, category: "rclone", message: message))
        }
        #endif
    }

    /// Append sans miroir console (utilisé pour l'ingestion bridge — rclone a
    /// déjà écrit ces lignes sur stderr via son handler d'origine).
    private func appendEntry(_ entry: LogEntry) {
        if !didReserveCapacity {
            ring.reserveCapacity(maxEntries)
            didReserveCapacity = true
        }
        ring.append(entry)
        if ring.count > maxEntries {
            let overflow = ring.count - maxEntries
            ring.removeFirst(max(overflow, 100))
        }
    }

    public func entries(filter: LogLevel? = nil, category: String? = nil) -> [LogEntry] {
        ring.filter { entry in
            (filter == nil || entry.level == filter)
                && (category == nil || entry.category == category)
        }
    }

    public func clear() {
        ring.removeAll(keepingCapacity: true)
    }

    /// Write the ring to a temp file and return its URL — ready to feed to a
    /// ShareSheet. Pass `category` to export only the lines of one category
    /// (ex. "transfer" pour les logs de transferts exportables).
    public func exportAsFile(
        category: String? = nil,
        additionalEntries: [LogEntry] = []
    ) throws -> URL {
        let appEntries = category == nil ? ring : ring.filter { $0.category == category }
        let extraEntries = category == nil
            ? additionalEntries
            : additionalEntries.filter { $0.category == category }
        let scoped = (appEntries + extraEntries).sorted { $0.timestamp < $1.timestamp }
        let suffix = category.map { "-\($0)" } ?? ""
        return try write(entries: scoped, suffix: suffix)
    }

    /// Export support volontairement metadata-only. Le ring brut contient des
    /// chemins de container/config, remotes, noms de fichiers et parfois des
    /// messages backend (URL ou token possibles). Ce chemin conserve seulement
    /// l'opération, l'étape, les compteurs/durées/codes et quelques états sûrs.
    /// Les exports spécialisés existants (`category: "transfer"`) restent
    /// inchangés et ne passent pas silencieusement par ce filtre.
    public func exportSupportAsFile(
        additionalEntries: [LogEntry] = []
    ) throws -> URL {
        let scoped = (ring + additionalEntries)
            .map(Self.supportSafeEntry)
            .sorted { $0.timestamp < $1.timestamp }
        return try write(entries: scoped, suffix: "-support")
    }

    nonisolated static func supportSafeEntry(_ entry: LogEntry) -> LogEntry {
        let category = supportSafeCategory(entry.category)
        let fallbackOperation: String
        switch category {
        case "boot": fallbackOperation = "boot"
        case "list": fallbackOperation = "listing"
        case "rpc": fallbackOperation = "rpc"
        case "fileprovider", "fileprovider-extension": fallbackOperation = "fileprovider"
        case "transfer": fallbackOperation = "transfer"
        case "rclone": fallbackOperation = "rclone"
        default: fallbackOperation = "app"
        }
        let fallbackStage = entry.level == .error ? "failed" : "event"
        let message = validatedSupportMessage(entry.supportMessage)
            ?? "operation=\(fallbackOperation) stage=\(fallbackStage)"

        return LogEntry(
            id: entry.id,
            timestamp: entry.timestamp,
            level: entry.level,
            category: category,
            message: message,
            supportMessage: message
        )
    }

    private nonisolated static func supportSafeCategory(_ category: String) -> String {
        switch category.lowercased() {
        case "boot": return "boot"
        case "list": return "list"
        case "rpc": return "rpc"
        case "fileprovider": return "fileprovider"
        case "fileprovider-extension": return "fileprovider-extension"
        case "transfer": return "transfer"
        case "rclone": return "rclone"
        case "logs": return "logs"
        default: return "app"
        }
    }

    /// N'accepte qu'un petit langage `clé=valeur` produit par nos propres
    /// appels. Aucun texte libre, query string ou payload rclone ne peut devenir
    /// une métadonnée support par simple ressemblance (`code=123456`, etc.).
    private nonisolated static func validatedSupportMessage(_ message: String?) -> String? {
        guard let message, !message.isEmpty else { return nil }
        let tokens = message.split(separator: " ").map(String.init)
        guard !tokens.isEmpty else { return nil }

        let operations: Set<String> = [
            "app", "app_group", "boot", "configuration", "container", "create",
            "delete", "domain", "download", "engine", "fileprovider", "listing", "modify",
            "other", "rpc", "rclone", "stream", "transfer", "upload", "vault",
        ]
        let stages: Set<String> = [
            "acknowledged", "cancelled", "completed", "event", "failed", "queued",
            "retrying", "running", "started", "timeout",
        ]
        let reasons: Set<String> = [
            "authentication", "cancelled", "connectivity", "invalid_response",
            "missing_directory", "permission", "quota", "rate_limit", "timeout",
        ]
        let states: Set<String> = ["absent", "available", "present", "unavailable"]
        let engines: Set<String> = ["librclone", "mock"]
        let numericKeys: Set<String> = [
            "code", "count", "duration_ms", "expired_count", "status",
            "unreadable_count", "waiters",
        ]
        let allowedKeys: Set<String> = numericKeys.union([
            "engine", "operation", "reason", "recursive", "stage", "state", "version",
        ])

        var seen: Set<String> = []
        for token in tokens {
            let pair = token.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard pair.count == 2 else { return nil }
            let key = String(pair[0])
            let value = String(pair[1])
            guard allowedKeys.contains(key), !value.isEmpty, seen.insert(key).inserted else {
                return nil
            }

            switch key {
            case "operation": guard operations.contains(value) else { return nil }
            case "stage": guard stages.contains(value) else { return nil }
            case "reason": guard reasons.contains(value) else { return nil }
            case "state": guard states.contains(value) else { return nil }
            case "engine": guard engines.contains(value) else { return nil }
            case "recursive": guard value == "true" || value == "false" else { return nil }
            case "version":
                guard value.range(
                    of: #"^v\d+(?:\.\d+){1,3}(?:-[a-z0-9]+)?$"#,
                    options: .regularExpression
                ) != nil else { return nil }
            default:
                guard numericKeys.contains(key), let number = Int(value) else { return nil }
                if key == "status" {
                    guard (100...599).contains(number) else { return nil }
                } else if key == "code" {
                    guard (-100_000...100_000).contains(number) else { return nil }
                } else {
                    guard (0...1_000_000_000_000).contains(number) else { return nil }
                }
            }
        }

        guard seen.contains("operation"), seen.contains("stage") else { return nil }
        return tokens.joined(separator: " ")
    }

    private func write(entries: [LogEntry], suffix: String) throws -> URL {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let lines = entries.map { entry in
            "\(formatter.string(from: entry.timestamp)) [\(entry.level.rawValue)] [\(entry.category)] \(entry.message)"
        }
        let text = lines.joined(separator: "\n")
        let url = FileManager.default
            .temporaryDirectory
            .appending(path: "rclone-gui-logs\(suffix)-\(UUID().uuidString.prefix(8)).log")
        try text.data(using: .utf8)?.write(to: url, options: .atomic)
        return url
    }
}
