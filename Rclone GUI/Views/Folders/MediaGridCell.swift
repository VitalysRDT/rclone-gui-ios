//
//  MediaGridCell.swift
//  Rclone GUI — Views/Folders
//
//  Cellule de la vue grille / galerie. Charge sa vignette de façon paresseuse
//  via ThumbnailService (cellule visible uniquement), avec placeholder icône,
//  badge de lecture pour les vidéos, et libellé tronqué.
//

import SwiftUI

struct MediaGridCell: View {
    let entry: RemoteEntryDTO
    let remote: String

    @State private var thumb: CGImageBox?
    @State private var loading = false

    private var isVisual: Bool { MediaFormat.isVisualMedia(entry.name) }
    private var isVideo: Bool { MediaFormat.isVideo(entry.name) }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.secondary.opacity(0.12))

                if let thumb {
                    Image(decorative: thumb.image, scale: 1)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: placeholderIcon)
                        .font(.system(size: 28))
                        .foregroundStyle(placeholderColor)
                    if loading {
                        ProgressView()
                            .controlSize(.small)
                            .padding(6)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    }
                }

                if isVideo {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.white)
                        .shadow(radius: 3)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                        .padding(6)
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(.quaternary, lineWidth: 0.5)
            }

            Text(entry.name)
                .font(.caption2)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)
        }
        .contentShape(Rectangle())
        .task(id: entry.id) {
            guard isVisual, thumb == nil else { return }
            loading = true
            defer { loading = false }
            thumb = await ThumbnailService.shared.thumbnail(for: entry, remote: remote)
        }
    }

    private var placeholderIcon: String {
        if entry.isDirectory { return "folder.fill" }
        if MediaFormat.isImage(entry.name) { return "photo" }
        if MediaFormat.isVideo(entry.name) { return "film" }
        if MediaFormat.isAudio(entry.name) { return "music.note" }
        return "doc"
    }

    private var placeholderColor: Color {
        if entry.isDirectory { return .blue }
        if MediaFormat.isImage(entry.name) { return .green }
        if MediaFormat.isVideo(entry.name) { return .purple }
        if MediaFormat.isAudio(entry.name) { return .pink }
        return .gray
    }
}
