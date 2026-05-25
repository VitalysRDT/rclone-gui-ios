//
//  PhotoSyncFormatters.swift
//  Rclone GUI — Views/Shared
//
//  Single source of truth for byte, throughput, ETA and percent string
//  formatting used across the Transfers card, PhotoSyncSettings view,
//  PhotoSyncStats view and TransferRow view. Replaces 5 previously
//  duplicated implementations (each subtly different).
//

import Foundation

enum PhotoSyncFormat {
    /// Shared formatter. `ByteCountFormatter` is thread-safe according to
    /// the Foundation docs as long as its configuration is fixed at init.
    nonisolated(unsafe) private static let byteFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowsNonnumericFormatting = true
        return f
    }()

    /// "1.2 MB" / "523 KB" — clamps negative inputs to 0.
    static func bytes(_ bytes: Int64) -> String {
        byteFormatter.string(fromByteCount: max(0, bytes))
    }

    /// "1.2 MB/s" — returns "—" below 1 B/s (caller didn't measure).
    static func throughput(_ bytesPerSecond: Double) -> String {
        guard bytesPerSecond > 1 else { return "—" }
        return "\(byteFormatter.string(fromByteCount: Int64(bytesPerSecond)))/s"
    }

    /// "42 s" / "3 min 12 s" / "2 h 04 min". Rounded to nearest integer
    /// second; negative inputs clamped to 0.
    static func eta(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds.rounded()))
        if s < 60 { return "\(s) s" }
        if s < 3600 { return "\(s / 60) min \(s % 60) s" }
        let h = s / 3600
        let m = (s % 3600) / 60
        return "\(h) h \(m) min"
    }

    /// "42 %" — clamps ratio to 0..1 then rounds to nearest integer percent.
    /// Used by accessibility labels and percentage chips on the hero card.
    static func percent(_ ratio: Double) -> String {
        let r = max(0, min(1, ratio))
        return "\(Int((r * 100).rounded()))"
    }
}
