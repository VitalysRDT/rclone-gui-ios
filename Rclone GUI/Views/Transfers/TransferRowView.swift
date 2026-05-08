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
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: kindIcon)
                    .foregroundStyle(kindColor)
                    .font(.title3)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(displayTitle)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .font(.body)
                    Text(displaySubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                statusView
            }

            if transfer.status == .running, transfer.bytesTotal > 0 {
                ProgressView(value: Double(transfer.bytesTransferred), total: Double(transfer.bytesTotal))
                    .progressViewStyle(.linear)
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
    private var statusView: some View {
        switch transfer.status {
        case .running:
            ProgressView()
                .controlSize(.small)
        case .pending:
            Image(systemName: "hourglass")
                .foregroundStyle(.secondary)
        case .paused:
            Image(systemName: "pause.circle")
                .foregroundStyle(.orange)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
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
        let basename = (transfer.destinationPath.isEmpty ? transfer.sourcePath : transfer.destinationPath) as NSString
        return basename.lastPathComponent
    }

    private var displaySubtitle: String {
        switch transfer.kind {
        case .download:
            return "\(transfer.sourceRemote ?? "?") → local"
        case .upload:
            return "local → \(transfer.destinationRemote ?? "?")"
        case .move, .copy, .sync:
            let src = transfer.sourceRemote ?? "?"
            let dst = transfer.destinationRemote ?? "?"
            return "\(src) → \(dst)"
        case .delete:
            return "Supprimer dans \(transfer.sourceRemote ?? "?")"
        }
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
}
