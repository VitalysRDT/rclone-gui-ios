//
//  FileDetailView.swift
//  Rclone GUI — Views/Files
//
//  Crypt-forward file detail screen (artboard "06 · Fichier" of the
//  walkthrough handoff). Hero gradient + 4-column action grid + Info /
//  Security / Hash sections. Used by `RemotePreviewHost` as the landing
//  surface before launching QuickLook for non-media files.
//

import SwiftUI

struct FileDetailView: View {
    let entry: RemoteEntryDTO
    let remote: String
    /// Whether this file lives inside a `crypt` remote — drives the
    /// "CRYPT" badge in the hero and the Encryption row in the security
    /// section. Defaults to false; toggle when you know.
    var isInsideCrypt: Bool = false

    var onPlay: (() -> Void)? = nil
    var onDownload: (() -> Void)? = nil
    var onShare: (() -> Void)? = nil
    var onPin: (() -> Void)? = nil

    var body: some View {
        Form {
            Section {
                heroPreview
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
            }

            Section {
                titleBlock
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
            }

            Section {
                actionGrid
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
            }

            Section("Informations") {
                infoRow(title: "Type", value: kindLabel)
                infoRow(title: "Taille", value: sizeLabel)
                infoRow(title: "Modifié", value: dateLabel)
                infoRow(title: "Chemin", value: entry.pathInRemote.isEmpty ? "—" : entry.pathInRemote)
            }

            Section("Sécurité") {
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isInsideCrypt ? RG.accentSoft : Color.secondary.opacity(0.16))
                        .frame(width: 28, height: 28)
                        .overlay {
                            Image(systemName: isInsideCrypt ? "lock.fill" : "lock.open")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(isInsideCrypt ? RG.accent : .secondary)
                        }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Chiffrement")
                            .font(.system(size: 16))
                        Text(isInsideCrypt ? "rclone crypt · AES-256-GCM" : "Aucun (remote en clair)")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 4)

                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.secondary.opacity(0.16))
                        .frame(width: 28, height: 28)
                        .overlay {
                            Image(systemName: "key")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Nom déchiffré")
                            .font(.system(size: 16))
                        Text(entry.name)
                            .font(RG.mono)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 4)
            }

            if entry.hashMD5 != nil || entry.hashSHA1 != nil {
                Section("Hash") {
                    if let md5 = entry.hashMD5 {
                        infoRow(title: "MD5", value: md5)
                    }
                    if let sha = entry.hashSHA1 {
                        infoRow(title: "SHA-1", value: sha)
                    }
                }
            }
        }
    }

    private var heroPreview: some View {
        ZStack {
            // Brand gradient backdrop, mirroring the design's
            // `linear-gradient(135deg, #1a1a2e 0%, #2d1b4e 50%, #5b21b6 100%)`.
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.10, green: 0.10, blue: 0.18),
                            Color(red: 0.18, green: 0.11, blue: 0.31),
                            RG.accentDeep,
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            // Faint film grid (matches the design's repeating-line overlay)
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.04), lineWidth: 18)
                .blendMode(.overlay)

            // Big play / open glyph
            Circle()
                .fill(.white.opacity(0.95))
                .frame(width: 64, height: 64)
                .overlay {
                    Image(systemName: isMedia ? "play.fill" : kindGlyph)
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.black)
                }

            // Top-left badges
            VStack {
                HStack(spacing: 6) {
                    if isInsideCrypt { CryptBadge(compact: true) }
                    if !codecBadge.isEmpty {
                        Text(codecBadge)
                            .font(.system(size: 10, weight: .bold))
                            .tracking(0.5)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    }
                    Spacer()
                }
                Spacer()
                HStack {
                    Spacer()
                    Text(sizeLabel)
                        .font(RG.mono)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                }
            }
            .padding(10)
        }
        .frame(height: 200)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(entry.name)
                .font(.system(size: 22, weight: .bold))
                .lineLimit(2)
            HStack(spacing: 6) {
                if isInsideCrypt {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(RG.accent)
                }
                Text("\(remote)\(entry.pathInRemote.isEmpty ? "" : " · /\(entry.pathInRemote)")")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var actionGrid: some View {
        HStack(spacing: 8) {
            RGActionTile(
                title: "Aperçu",
                systemImage: isMedia ? "play.fill" : "doc.text.magnifyingglass",
                primary: true,
                action: { onPlay?() }
            )
            RGActionTile(
                title: "Charger",
                systemImage: "arrow.down.circle",
                action: { onDownload?() }
            )
            RGActionTile(
                title: "Partager",
                systemImage: "square.and.arrow.up",
                action: { onShare?() }
            )
            RGActionTile(
                title: "Hors-ligne",
                systemImage: "star",
                action: { onPin?() }
            )
        }
    }

    private func infoRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.primary)
            Spacer(minLength: 8)
            Text(value)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Derived display values

    private var kindLabel: String {
        if entry.isDirectory { return "Dossier" }
        let ext = (entry.name as NSString).pathExtension.uppercased()
        return ext.isEmpty ? "Fichier" : "Fichier \(ext)"
    }

    private var sizeLabel: String {
        if entry.isDirectory { return "—" }
        return ByteCountFormatter.string(fromByteCount: entry.size, countStyle: .file)
    }

    private var dateLabel: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return entry.modTime == .distantPast ? "—" : formatter.string(from: entry.modTime)
    }

    private var isMedia: Bool {
        let ext = (entry.name as NSString).pathExtension.lowercased()
        return ["mp4", "mkv", "mov", "m4v", "avi", "webm", "ts", "mp3", "m4a", "wav", "flac", "ogg", "aac"].contains(ext)
    }

    private var kindGlyph: String {
        let ext = (entry.name as NSString).pathExtension.lowercased()
        switch ext {
        case "pdf":         return "doc.text.fill"
        case "zip", "tar", "gz", "tgz", "7z", "rar", "xz", "bz2": return "archivebox.fill"
        case "jpg", "jpeg", "png", "heic", "gif", "webp": return "photo.fill"
        default:            return "doc.fill"
        }
    }

    private var codecBadge: String {
        let ext = (entry.name as NSString).pathExtension.lowercased()
        switch ext {
        case "mp4", "mkv", "mov", "m4v": return "VIDEO"
        case "flac", "wav":              return "LOSSLESS"
        case "mp3", "m4a", "aac", "ogg": return "AUDIO"
        case "heic":                     return "HEIC"
        case "pdf":                      return "PDF"
        default:                         return ""
        }
    }
}
