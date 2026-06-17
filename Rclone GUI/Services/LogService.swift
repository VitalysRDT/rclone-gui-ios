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

    public nonisolated init(
        id: UUID = UUID(),
        timestamp: Date = .now,
        level: LogLevel,
        category: String,
        message: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.category = category
        self.message = message
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
                : "App Group « \(AppGroup.identifier) » non provisionné — fallback vers Application Support. FileProvider ne pourra pas partager. Crée l'App Group sur Apple Developer Portal et réinstalle."
        )
        await shared.log(
            .info,
            category: "boot",
            message: "Container : \(AppGroup.containerURL.path)"
        )
        let hasConf = await ConfigStore.shared.hasStoredConf()
        await shared.log(
            hasConf ? .info : .info,
            category: "boot",
            message: hasConf
                ? "Configuration rclone importée détectée."
                : "Aucune configuration rclone importée — utilise Réglages → Importer."
        )
        let isMock = await RcloneCore.shared.isMockEngine
        await shared.log(
            .info,
            category: "boot",
            message: "Moteur rclone : \(isMock ? "Mock (pas de librclone embarqué)" : "Librclone v1.68.0 (réel)")"
        )
    }

    public func log(_ level: LogLevel, category: String, message: String) {
        if !didReserveCapacity {
            ring.reserveCapacity(maxEntries)
            didReserveCapacity = true
        }
        let entry = LogEntry(level: level, category: category, message: message)
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

    /// Write the entire ring to a temp file and return its URL — ready
    /// to feed to a ShareSheet.
    public func exportAsFile() throws -> URL {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let lines = ring.map { e in
            "\(formatter.string(from: e.timestamp)) [\(e.level.rawValue)] [\(e.category)] \(e.message)"
        }
        let text = lines.joined(separator: "\n")
        let url = FileManager.default
            .temporaryDirectory
            .appending(path: "rclone-gui-logs-\(UUID().uuidString.prefix(8)).log")
        try text.data(using: .utf8)?.write(to: url, options: .atomic)
        return url
    }
}
