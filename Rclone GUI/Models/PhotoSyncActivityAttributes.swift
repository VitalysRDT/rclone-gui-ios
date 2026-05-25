//
//  PhotoSyncActivityAttributes.swift
//  Rclone GUI — Models
//
//  Shared ActivityAttributes for the PhotoSync Live Activity. When the
//  `RclonePhotoSyncActivity` Widget Extension target is added in Xcode
//  (File → New → Target → Widget Extension, with "Include Live Activity"
//  ON), this file MUST be added to that target's "Compile Sources" build
//  phase as well — both processes (main app + extension) must compile
//  the exact same struct definition for ActivityKit to deserialize the
//  payload correctly.
//
//  Until the extension target exists, the Live Activity is started but
//  cannot be rendered. The bridge service (`PhotoSyncLiveActivity`) still
//  compiles fine in the main app, and `Activity.request(...)` returns
//  `.unsupported` gracefully on iOS < 16.2 or when no extension renders
//  the activity.
//

import Foundation
#if canImport(ActivityKit)
import ActivityKit
#endif

#if canImport(ActivityKit)
@available(iOS 16.2, *)
struct PhotoSyncActivityAttributes: ActivityAttributes {
    /// Display label of the remote being synced ("iCloud Crypt", "pCloud").
    let remoteLabel: String
    /// Raw backend kind (`RGBackend.rawValue` or rclone backend name) — lets
    /// the widget render the right icon tint without importing the full
    /// `RGBackend` enum (extension target can't import DesignSystem).
    let backendKind: String
    let startedAt: Date

    /// Frequently mutated content shipped with each `Activity.update`.
    /// 4 KB hard limit total — keep currentFilename truncated to ≤64 chars.
    struct ContentState: Codable, Hashable {
        var completed: Int
        var total: Int
        var currentFilename: String?
        var speedBytesPerSec: Double
        var etaSeconds: Double?
        var bytesTransferred: Int64
        var bytesTotal: Int64
        var isPaused: Bool
        var phase: Phase

        enum Phase: String, Codable, Hashable {
            case preparing
            case uploading
            case verifying
            case completed
            case paused
            case failed

            /// SF Symbol used in the compact/minimal Dynamic Island regions.
            var icon: String {
                switch self {
                case .preparing: return "hourglass"
                case .uploading: return "arrow.up.circle.fill"
                case .verifying: return "checkmark.shield"
                case .completed: return "checkmark.circle.fill"
                case .paused:    return "pause.circle.fill"
                case .failed:    return "exclamationmark.triangle.fill"
                }
            }
        }

        /// Monotonic 0..1 progress. Computed from `completed/total` and
        /// clamped — the widget never sees a ratio outside [0,1].
        var progress: Double {
            guard total > 0 else { return 0 }
            return min(1.0, max(0, Double(completed) / Double(total)))
        }

        /// 4KB hard limit on the ActivityKit payload. Truncate filename
        /// to its lastPathComponent + 64 chars max before storing.
        static func sanitize(filename: String?) -> String? {
            guard let raw = filename, !raw.isEmpty else { return nil }
            let last = (raw as NSString).lastPathComponent
            if last.count <= 64 { return last }
            return String(last.prefix(60)) + "…"
        }
    }

    static let name = "PhotoSync"
}
#endif
