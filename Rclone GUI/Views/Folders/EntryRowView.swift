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
    /// True when this row sits inside a `crypt` remote. Surfaces a small
    /// purple lock glyph next to the filename — mirrors the design's
    /// `<lock>` prefix that signals "decrypted on the fly".
    var isInsideCrypt: Bool = false
    /// Optional file-state pill rendered on the trailing edge:
    /// cloud / local / syncing / downloading. Falls back to a kind badge
    /// or a transfer spinner when nil.
    var fileState: RGFileState? = nil

    // Formatters partagés : évitent ~200 allocations inutiles par re-render
    // d'une liste de 100 fichiers (RelativeDateTimeFormatter + DateFormatter
    // étaient créés par row).
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        f.dateTimeStyle = .named
        return f
    }()
    private static let absoluteFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    var body: some View {
        HStack(spacing: 14) {
            AppIconTile(systemImage: iconName, tint: iconColor, size: 44)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    if isInsideCrypt {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(RG.accent)
                            .accessibilityHidden(true)
                    }
                    Text(entry.name)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                if let active = activeTransfer {
                    transferProgressLine(for: active)
                } else {
                    HStack(spacing: 7) {
                        Text(secondaryLine)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        if !entry.isDirectory {
                            AppStatusBadge(title: fileKindLabel, tint: iconColor)
                        }
                    }
                }
            }

            Spacer(minLength: 4)

            if let activeTransfer {
                if activeTransfer.bytesTotal > 0 {
                    let p = Double(activeTransfer.bytesTransferred) / Double(max(activeTransfer.bytesTotal, 1))
                    FileStateGlyph(state: .downloading(progress: p))
                } else {
                    FileStateGlyph(state: .syncing)
                }
            } else if let fileState {
                FileStateGlyph(state: fileState)
            }
        }
        .padding(.vertical, 6)
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
                    value: progressValue(for: transfer),
                    total: progressTotal(for: transfer)
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
            let pct = Int(progressValue(for: transfer) / progressTotal(for: transfer) * 100)
            return "\(action) — \(pct)% · \(formatBytes(clampedBytesTransferred(for: transfer))) / \(formatBytes(transfer.bytesTotal))"
        }
        return "\(action) en cours…"
    }

    private func clampedBytesTransferred(for transfer: Transfer) -> Int64 {
        min(max(transfer.bytesTransferred, 0), max(transfer.bytesTotal, 0))
    }

    private func progressValue(for transfer: Transfer) -> Double {
        Double(clampedBytesTransferred(for: transfer))
    }

    private func progressTotal(for transfer: Transfer) -> Double {
        Double(max(transfer.bytesTotal, 1))
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
            return .gray
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

    private var fileKindLabel: String {
        let ext = (entry.name as NSString).pathExtension.uppercased()
        return ext.isEmpty ? "Fichier" : ext
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func formatDate(_ date: Date) -> String {
        if date == .distantPast { return "—" }
        let interval = abs(date.timeIntervalSinceNow)
        if interval < 60 * 60 * 24 * 7 {
            return Self.relativeFormatter.localizedString(for: date, relativeTo: .now)
        }
        return Self.absoluteFormatter.string(from: date)
    }

    private var accessibilityText: String {
        if entry.isDirectory {
            return String(localized: "Dossier \(entry.name), modifié \(formatDate(entry.modTime))")
        }
        return String(localized: "Fichier \(entry.name), \(formatBytes(entry.size)), modifié \(formatDate(entry.modTime))")
    }
}
