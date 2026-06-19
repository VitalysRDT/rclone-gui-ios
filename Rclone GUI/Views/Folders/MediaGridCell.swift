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
            // La taille de la cellule est pilotée par une FORME flexible carrée
            // (elle prend la largeur de colonne puis impose un ratio 1:1). La
            // vignette, le placeholder et les badges sont posés en `.overlay` :
            // un overlay est dimensionné PAR le parent et n'influence JAMAIS sa
            // taille. Sans ça, l'image `scaledToFill` (qui peut rapporter une
            // taille > cellule selon son ratio) faisait déborder la cellule de
            // son slot de grille → vignettes de tailles inégales qui se
            // chevauchaient (bug iPhone Mini, pire en paysage).
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(0.12))
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    if let thumb {
                        Image(decorative: thumb.image, scale: 1)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Image(systemName: placeholderIcon)
                            .font(.system(size: 28))
                            .foregroundStyle(placeholderColor)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if thumb == nil, loading {
                        ProgressView()
                            .controlSize(.small)
                            .padding(6)
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    if isVideo {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(.white)
                            .shadow(radius: 3)
                            .padding(6)
                    }
                }
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
