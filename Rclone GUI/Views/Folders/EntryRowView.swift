//
//  EntryRowView.swift
//  Rclone GUI — Views/Folders
//
//  Single row inside FolderView. Shows icon, name, secondary line
//  (size + date for files; just date for directories).
//

import SwiftUI

struct EntryRowView: View {
    let entry: RemoteEntryDTO
    var activeTransfer: Transfer? = nil

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.title3)
                .foregroundStyle(iconColor)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if let active = activeTransfer {
                    transferProgressLine(for: active)
                } else {
                    Text(secondaryLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            if activeTransfer != nil {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder
    private func transferProgressLine(for transfer: Transfer) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: transferIcon(for: transfer.kind))
                    .foregroundStyle(transferColor(for: transfer.kind))
                Text(transferLabel(for: transfer))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(transferColor(for: transfer.kind))
            }
            if transfer.bytesTotal > 0 {
                ProgressView(
                    value: Double(transfer.bytesTransferred),
                    total: Double(transfer.bytesTotal)
                )
                .progressViewStyle(.linear)
                .tint(transferColor(for: transfer.kind))
            } else {
                ProgressView()
                    .progressViewStyle(.linear)
                    .tint(transferColor(for: transfer.kind))
            }
        }
        .padding(.top, 2)
    }

    private func transferIcon(for kind: TransferKind) -> String {
        switch kind {
        case .download: return "arrow.down.circle.fill"
        case .upload:   return "arrow.up.circle.fill"
        case .move:     return "arrow.left.arrow.right.circle.fill"
        case .copy:     return "doc.on.doc.fill"
        case .sync:     return "arrow.triangle.2.circlepath.circle.fill"
        case .delete:   return "trash.circle.fill"
        }
    }

    private func transferColor(for kind: TransferKind) -> Color {
        switch kind {
        case .download: return .blue
        case .upload:   return .indigo
        case .move:     return .orange
        case .copy:     return .teal
        case .sync:     return .purple
        case .delete:   return .red
        }
    }

    private func transferLabel(for transfer: Transfer) -> String {
        let action: String
        switch transfer.kind {
        case .download: action = "Téléchargement"
        case .upload:   action = "Envoi"
        case .move:     action = "Déplacement"
        case .copy:     action = "Copie"
        case .sync:     action = "Sync"
        case .delete:   action = "Suppression"
        }
        if transfer.bytesTotal > 0 {
            let pct = Int(Double(transfer.bytesTransferred) / Double(transfer.bytesTotal) * 100)
            return "\(action) — \(pct)% · \(formatBytes(transfer.bytesTransferred)) / \(formatBytes(transfer.bytesTotal))"
        }
        return "\(action) en cours…"
    }

    // MARK: Icon

    private var iconName: String {
        if entry.isDirectory {
            return "folder.fill"
        }
        let ext = (entry.name as NSString).pathExtension.lowercased()
        switch ext {
        case "mp4", "mkv", "mov", "avi", "webm", "m4v", "ts":
            return "film.fill"
        case "mp3", "m4a", "wav", "flac", "ogg", "aac", "alac":
            return "music.note"
        case "jpg", "jpeg", "png", "heic", "heif", "gif", "webp", "bmp", "tiff":
            return "photo.fill"
        case "pdf":
            return "doc.fill"
        case "zip", "tar", "gz", "tgz", "7z", "rar", "xz", "bz2":
            return "archivebox.fill"
        case "txt", "md", "rtf", "log":
            return "doc.text.fill"
        case "vtt", "srt", "ass", "ssa", "sub":
            return "captions.bubble.fill"
        case "swift", "py", "go", "rs", "js", "json", "yml", "yaml", "toml":
            return "chevron.left.forwardslash.chevron.right"
        case "html", "htm", "css":
            return "globe"
        case "key", "pem", "crt", "p12":
            return "key.fill"
        default:
            return "doc"
        }
    }

    private var iconColor: Color {
        if entry.isDirectory { return .blue }
        let ext = (entry.name as NSString).pathExtension.lowercased()
        switch ext {
        case "mp4", "mkv", "mov", "avi", "webm", "m4v", "ts":
            return .purple
        case "mp3", "m4a", "wav", "flac", "ogg", "aac", "alac":
            return .pink
        case "jpg", "jpeg", "png", "heic", "heif", "gif", "webp", "bmp", "tiff":
            return .green
        case "pdf":
            return .red
        case "zip", "tar", "gz", "tgz", "7z", "rar", "xz", "bz2":
            return .orange
        default:
            return .secondary
        }
    }

    // MARK: Secondary line

    private var secondaryLine: String {
        let date = formatDate(entry.modTime)
        if entry.isDirectory {
            return date
        }
        return "\(formatBytes(entry.size)) · \(date)"
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func formatDate(_ date: Date) -> String {
        if date == .distantPast { return "—" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        formatter.dateTimeStyle = .named
        let interval = abs(date.timeIntervalSinceNow)
        if interval < 60 * 60 * 24 * 7 {
            return formatter.localizedString(for: date, relativeTo: .now)
        }
        let abs = DateFormatter()
        abs.dateStyle = .medium
        abs.timeStyle = .none
        return abs.string(from: date)
    }

    private var accessibilityText: String {
        if entry.isDirectory {
            return "Dossier \(entry.name), modifié \(formatDate(entry.modTime))"
        }
        return "Fichier \(entry.name), \(formatBytes(entry.size)), modifié \(formatDate(entry.modTime))"
    }
}
