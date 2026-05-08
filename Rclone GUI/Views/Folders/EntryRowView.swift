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

                Text(secondaryLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
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
