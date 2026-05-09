//
//  LogService.swift
//  Rclone GUI — Services
//
//  Lightweight in-memory ring buffer of log entries + export-to-file
//  helper. Phase E v1 ; Phase E2 will wire `core/log` rclone rc to
//  capture verbose rclone logs (-vv equivalent).
//

import Foundation

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

    public nonisolated init(level: LogLevel, category: String, message: String) {
        self.id = UUID()
        self.timestamp = .now
        self.level = level
        self.category = category
        self.message = message
    }
}

public actor LogService {
    public static let shared = LogService()

    private let maxEntries = 5000
    private var ring: [LogEntry] = []

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
        let entry = LogEntry(level: level, category: category, message: message)
        ring.append(entry)
        if ring.count > maxEntries {
            ring.removeFirst(ring.count - maxEntries)
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
