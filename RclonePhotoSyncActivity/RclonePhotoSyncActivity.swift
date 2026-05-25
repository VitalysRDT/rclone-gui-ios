//
//  RclonePhotoSyncActivity.swift
//  RclonePhotoSyncActivity
//
//  Idle Lock Screen / Home Screen widget surfacing PhotoSync state
//  even outside an active sync. Data flows through App Group UserDefaults
//  under key `photosync.widgetSnapshot`, written by the main app's
//  `PhotoSyncService.publishWidgetSnapshot` at every status update.
//

import SwiftUI
import WidgetKit

struct PhotoSyncStatusWidget: Widget {
    let kind: String = "PhotoSyncStatus"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PhotoSyncStatusProvider()) { entry in
            PhotoSyncStatusEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryRectangular,
            .accessoryCircular
        ])
        .configurationDisplayName("Synchro Photos")
        .description("État de la sauvegarde de ta photothèque.")
    }
}

struct PhotoSyncStatusEntry: TimelineEntry {
    let date: Date
    let completed: Int
    let pending: Int
    let isSyncing: Bool
    let lastSyncAt: Date?
    let remoteLabel: String
}

struct PhotoSyncStatusProvider: TimelineProvider {
    func placeholder(in context: Context) -> PhotoSyncStatusEntry {
        PhotoSyncStatusEntry(
            date: Date(),
            completed: 0,
            pending: 0,
            isSyncing: false,
            lastSyncAt: nil,
            remoteLabel: "—"
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (PhotoSyncStatusEntry) -> Void) {
        completion(readSnapshot() ?? placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PhotoSyncStatusEntry>) -> Void) {
        let entry = readSnapshot() ?? placeholder(in: context)
        let nextRefresh = entry.isSyncing
            ? Date().addingTimeInterval(60)
            : Date().addingTimeInterval(15 * 60)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }

    /// Lit le snapshot publié par le main app dans le App Group. Doit
    /// rester synchronisé avec `PhotoSyncWidgetSnapshot` (mêmes clés
    /// JSON). Hardcodé sur `group.com.rougetet.rclone-gui` — le widget
    /// extension n'importe pas AppGroup.swift.
    private func readSnapshot() -> PhotoSyncStatusEntry? {
        guard let defaults = UserDefaults(suiteName: "group.com.rougetet.rclone-gui"),
              let data = defaults.data(forKey: "photosync.widgetSnapshot"),
              let snap = try? JSONDecoder().decode(PhotoSyncWidgetSnapshot.self, from: data) else {
            return nil
        }
        return PhotoSyncStatusEntry(
            date: snap.updatedAt,
            completed: snap.completed,
            pending: snap.pending,
            isSyncing: snap.isSyncing,
            lastSyncAt: snap.lastSyncAt,
            remoteLabel: snap.remoteLabel
        )
    }
}

struct PhotoSyncWidgetSnapshot: Codable {
    let completed: Int
    let pending: Int
    let isSyncing: Bool
    let lastSyncAt: Date?
    let remoteLabel: String
    let updatedAt: Date
}

struct PhotoSyncStatusEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PhotoSyncStatusEntry

    var body: some View {
        switch family {
        case .accessoryCircular: circular
        case .accessoryRectangular: accessoryRect
        case .systemSmall: small
        case .systemMedium: medium
        default: small
        }
    }

    private var circular: some View {
        ZStack {
            Image(systemName: "photo.stack.fill")
                .font(.system(size: 14))
            Text("\(entry.completed)")
                .font(.system(.caption2, design: .monospaced).weight(.semibold))
                .offset(y: 18)
        }
    }

    private var accessoryRect: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "photo.stack.fill")
                Text("PhotoSync")
            }
            .font(.caption.weight(.semibold))
            Text("\(entry.completed) sauvegardées")
                .font(.system(.caption2, design: .monospaced))
            if entry.pending > 0 {
                Text("\(entry.pending) en attente")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: entry.isSyncing ? "arrow.up.circle.fill" : "photo.stack.fill")
                    .foregroundStyle(Color("AccentColor"))
                Text("PhotoSync")
                    .font(.headline)
            }
            Text("\(entry.completed)")
                .font(.system(.title, design: .monospaced).weight(.bold))
                .contentTransition(.numericText())
            Text("photos sauvegardées")
                .font(.caption2)
                .foregroundStyle(.secondary)
            if entry.pending > 0 {
                Text("\(entry.pending) en attente")
                    .font(.caption2)
                    .foregroundStyle(Color("AccentColor"))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(12)
    }

    private var medium: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: entry.isSyncing ? "arrow.up.circle.fill" : "photo.stack.fill")
                        .foregroundStyle(Color("AccentColor"))
                    Text("PhotoSync")
                        .font(.headline)
                }
                Text("\(entry.completed)")
                    .font(.system(.title, design: .monospaced).weight(.bold))
                Text("photos sauvegardées")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 4) {
                Text(entry.remoteLabel)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                if entry.pending > 0 {
                    Text("\(entry.pending) en attente")
                        .font(.caption2)
                        .foregroundStyle(Color("AccentColor"))
                }
                if let last = entry.lastSyncAt {
                    Text(relative(last))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
    }

    private func relative(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: .now)
    }
}

// Preview disabled — Xcode tries to instantiate `PhotoSyncStatusProvider`
// which reads App Group UserDefaults; in preview mode the group container
// is unavailable and we'd see only the placeholder.
