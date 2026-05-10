//
//  TransferRowView.swift
//  Rclone GUI — Views/Transfers
//
//  One row per Transfer. Shows kind icon, source → destination,
//  progress bar (running) or status badge (terminal).
//

import SwiftUI

struct TransferRowView: View {
    let transfer: Transfer

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 14) {
                AppIconTile(systemImage: kindIcon, tint: kindColor, size: 44)

                VStack(alignment: .leading, spacing: 4) {
                    Text(displayTitle)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    HStack(spacing: 6) {
                        Text(displaySubtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        // Class badge — Class 1 = URLSession transport
                        // (survives a kill); Class 2 = in-process librclone
                        // job (resumed on cold start via the manifest).
                        // Mirrors the design's "CLS 1" / "CLS 2" pill.
                        Text("CLS \(transportClass)")
                            .font(.system(size: 9, weight: .bold))
                            .tracking(0.4)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.15),
                                        in: RoundedRectangle(cornerRadius: 3, style: .continuous))
                    }
                }

                Spacer(minLength: 8)

                statusBadge
            }

            if transfer.status == .running, transfer.bytesTotal > 0 {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(progressText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(progressPercent)
                            .font(.caption2.monospacedDigit().weight(.semibold))
                            .foregroundStyle(kindColor)
                    }
                    ProgressView(value: progressValue, total: progressTotal)
                        .progressViewStyle(.linear)
                        .tint(kindColor)
                }
            }

            if let error = transfer.lastError, transfer.status == .failed {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    // MARK: - Status badge

    @ViewBuilder
    private var statusBadge: some View {
        switch transfer.status {
        case .running:
            AppStatusBadge(title: "En cours", systemImage: "bolt.fill", tint: .blue)
        case .enqueued:
            AppStatusBadge(title: "En file", systemImage: "tray.and.arrow.up.fill", tint: .indigo)
        case .pending:
            AppStatusBadge(title: "Attente", systemImage: "hourglass", tint: .gray)
        case .paused:
            AppStatusBadge(title: "Pause", systemImage: "pause.fill", tint: .orange)
        case .completed:
            AppStatusBadge(title: "Terminé", systemImage: "checkmark", tint: .green)
        case .failed:
            AppStatusBadge(title: "Échec", systemImage: "exclamationmark", tint: .red)
        }
    }

    /// Surfaces the transport "class" used by the design's
    /// `CLS 1` / `CLS 2` pill — a small visual cue about
    /// what survives an app kill.
    private var transportClass: Int {
        switch transfer.kind {
        case .download, .upload: return 1
        case .copy, .move, .sync, .delete: return 2
        }
    }

    private var kindIcon: String {
        switch transfer.kind {
        case .download: return "arrow.down.circle.fill"
        case .upload:   return "arrow.up.circle.fill"
        case .move:     return "arrow.left.arrow.right.circle.fill"
        case .copy:     return "doc.on.doc.fill"
        case .sync:     return "arrow.triangle.2.circlepath.circle.fill"
        case .delete:   return "trash.circle.fill"
        }
    }

    private var kindColor: Color {
        switch transfer.kind {
        case .download: return .blue
        case .upload:   return .indigo
        case .move:     return .orange
        case .copy:     return .teal
        case .sync:     return .purple
        case .delete:   return .red
        }
    }

    private var displayTitle: String {
        if let displayName = transfer.displayName, !displayName.isEmpty {
            return displayName
        }
        let basename = (transfer.destinationPath.isEmpty ? transfer.sourcePath : transfer.destinationPath) as NSString
        let title = basename.lastPathComponent
        return title.isEmpty ? "Transfert" : title
    }

    private var displaySubtitle: String {
        let route: String
        switch transfer.kind {
        case .download:
            route = "\(transfer.sourceRemote ?? "?") → local"
        case .upload:
            route = "\(sourceLabel) → \(transfer.destinationRemote ?? "?")"
        case .move, .copy, .sync:
            let src = transfer.sourceRemote ?? "?"
            let dst = transfer.destinationRemote ?? "?"
            route = "\(src) → \(dst)"
        case .delete:
            route = "Supprimer dans \(transfer.sourceRemote ?? "?")"
        }
        return "\(route) · \(relativeDate(transfer.startedAt))"
    }

    private var progressPercent: String {
        guard transfer.bytesTotal > 0 else { return "" }
        let pct = Int(progressValue / progressTotal * 100)
        return "\(pct)%"
    }

    private var progressText: String {
        "\(formatBytes(clampedBytesTransferred)) sur \(formatBytes(transfer.bytesTotal))"
    }

    private var clampedBytesTransferred: Int64 {
        min(max(transfer.bytesTransferred, 0), max(transfer.bytesTotal, 0))
    }

    private var progressValue: Double {
        Double(clampedBytesTransferred)
    }

    private var progressTotal: Double {
        Double(max(transfer.bytesTotal, 1))
    }

    private var accessibilityText: String {
        let action: String
        switch transfer.kind {
        case .download: action = "Téléchargement"
        case .upload: action = "Upload"
        case .move: action = "Déplacement"
        case .copy: action = "Copie"
        case .sync: action = "Synchronisation"
        case .delete: action = "Suppression"
        }
        return "\(action) de \(displayTitle), \(transfer.status.rawValue)"
    }

    private var sourceLabel: String {
        switch transfer.sourceKind {
        case .remote:
            return "remote"
        case .localFile:
            return "fichier local"
        case .localFolder:
            return "dossier local"
        case .photoLibrary:
            return "photothèque"
        case .fileProvider:
            return "Files"
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        formatter.dateTimeStyle = .named
        return formatter.localizedString(for: date, relativeTo: .now)
    }
}
