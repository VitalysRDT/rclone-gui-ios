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

    public init(level: LogLevel, category: String, message: String) {
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
