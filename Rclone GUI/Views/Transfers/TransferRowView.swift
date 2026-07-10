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
    /// Rang dans la file d'attente (#n), affiché pour les transferts en attente.
    var queuePosition: Int? = nil

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
                        Text(transportBadgeTitle)
                            .font(.system(size: 9, weight: .bold))
                            .tracking(0.4)
                            .foregroundStyle(transportBadgeTint)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(transportBadgeTint.opacity(0.14),
                                        in: RoundedRectangle(cornerRadius: 3, style: .continuous))
                    }
                }

                Spacer(minLength: 8)

                if let queuePosition {
                    Text("#\(queuePosition)")
                        .font(.caption2.monospacedDigit().weight(.bold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                        .accessibilityLabel("Position \(queuePosition) dans la file")
                }

                statusBadge
            }

            if transfer.status == .running, transfer.bytesTotal > 0 {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(progressText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        if showsFileCount {
                            Text("·")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            Text(fileCountText)
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(progressPercent)
                            .font(.caption2.monospacedDigit().weight(.semibold))
                            .foregroundStyle(kindColor)
                    }
                    ProgressView(value: progressValue, total: progressTotal)
                        .progressViewStyle(.linear)
                        .tint(kindColor)
                    if let current = currentFileLabel {
                        Text(current)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            } else if transfer.status == .running, (transfer.isDirectoryTransfer ?? false) {
                // Dossier running sans bytesTotal (operations/size a échoué ou
                // n'a pas encore retourné) → barre indéterminée plutôt que rien.
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        ProgressView()
                            .progressViewStyle(.linear)
                            .tint(kindColor)
                        if showsFileCount {
                            Text(fileCountText)
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        } else {
                            Text(String(localized: "Calcul de la taille\u{2026}"))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let current = currentFileLabel {
                        Text(current)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            } else if showsFileCount, transfer.status == .completed || transfer.status == .failed {
                // Affiche un récap fichiers pour les dossiers terminés/échoués
                VStack(alignment: .leading, spacing: 2) {
                    Text(fileCountText)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
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
            AppStatusBadge(title: String(localized: "En cours"), systemImage: "bolt.fill", tint: kindColor)
        case .enqueued:
            AppStatusBadge(title: String(localized: "En file"), systemImage: "tray.and.arrow.up.fill", tint: transfer.sourceKind == .photoLibrary ? .pink : .indigo)
        case .pending:
            AppStatusBadge(title: String(localized: "Attente"), systemImage: "hourglass", tint: .gray)
        case .paused:
            AppStatusBadge(title: String(localized: "Pause"), systemImage: "pause.fill", tint: .orange)
        case .completed:
            AppStatusBadge(title: String(localized: "Terminé"), systemImage: "checkmark", tint: .green)
        case .failed:
            AppStatusBadge(title: String(localized: "Échec"), systemImage: "exclamationmark", tint: .red)
        }
    }

    private var transportBadgeTitle: String {
        switch transfer.sourceKind {
        case .photoLibrary:
            return "PHOTOSYNC"
        case .fileProvider:
            return "FILES"
        case .localFile, .localFolder:
            return "LOCAL"
        case .remote:
            switch transfer.kind {
            case .download, .upload:
                return "URLSESSION"
            case .copy, .move, .sync, .delete:
                return "RCLONE"
            }
        }
    }

    private var transportBadgeTint: Color {
        switch transfer.sourceKind {
        case .photoLibrary:
            return RG.photoSync.accent
        case .fileProvider:
            return .blue
        case .localFile, .localFolder:
            return .indigo
        case .remote:
            return .secondary
        }
    }

    private var kindIcon: String {
        if transfer.sourceKind == .photoLibrary {
            return "photo.on.rectangle.angled"
        }
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
        if transfer.sourceKind == .photoLibrary {
            return RG.photoSync.accent
        }
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
        if transfer.sourceKind == .photoLibrary {
            route = "photothèque → \(photoDestinationLabel)"
        } else {
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

    /// Affiche le compteur de fichiers uniquement pour les downloads de
    /// dossier lancés via BridgeFolderDownloader (fileCount > 0). Les
    /// transferts sync/copy classiques n'ont pas cette info (le sync ne
    /// sait pas combien de fichiers il contient a priori).
    private var showsFileCount: Bool {
        (transfer.isDirectoryTransfer ?? false) && transfer.fileCount > 0
    }

    /// Texte « X/Y fichiers » avec fallback singulier/pluriel localisé.
    private var fileCountText: String {
        let completed = max(0, min(transfer.fileCount, totalFileCompleted))
        let total = transfer.fileCount
        if total == 1 {
            return String(localized: "1 fichier")
        }
        return String(localized: "\(completed)/\(total) fichiers")
    }

    /// Nombre de fichiers terminés (bytesTotal - bytesRestants) approximé.
    /// BridgeFolderDownloader met à jour `bytesTransferred` au niveau fichier
    /// donc on peut dériver le nombre de fichiers terminés depuis le ratio
    /// bytesTransferred/bytesTotal * fileCount. Plus simple : on regarde la
    /// dernière snapshot publique via un fallback à `bytesTotal` quand
    /// bytesTransferred atteint la taille totale.
    private var totalFileCompleted: Int {
        guard transfer.fileCount > 0, transfer.bytesTotal > 0 else { return 0 }
        let ratio = Double(clampedBytesTransferred) / Double(transfer.bytesTotal)
        return Int((Double(transfer.fileCount) * ratio).rounded())
    }

    /// Label « Téléchargement : <fichier> » pour les dossiers bridge folder en
    /// cours. Le nom est tronqué au basename (chemin potentiellement long dans
    /// le remote). Nil si pas de fichier courant.
    private var currentFileLabel: String? {
        guard transfer.status == .running,
              let name = transfer.currentFilename, !name.isEmpty else { return nil }
        let basename = (name as NSString).lastPathComponent
        return String(localized: "En cours : ") + basename
    }

    private var progressValue: Double {
        Double(clampedBytesTransferred)
    }

    private var progressTotal: Double {
        Double(max(transfer.bytesTotal, 1))
    }

    private var accessibilityText: String {
        let action: String
        if transfer.sourceKind == .photoLibrary {
            action = "Synchronisation PhotoSync"
        } else {
            switch transfer.kind {
            case .download: action = "Téléchargement"
            case .upload: action = "Upload"
            case .move: action = "Déplacement"
            case .copy: action = "Copie"
            case .sync: action = "Synchronisation"
            case .delete: action = "Suppression"
            }
        }
        return "\(action) de \(displayTitle), \(transfer.status.rawValue)"
    }

    private var photoDestinationLabel: String {
        let remote = transfer.destinationRemote ?? transfer.sourceRemote ?? "cloud"
        let directory = destinationDirectory
        return directory.isEmpty ? remote : "\(remote):\(directory)"
    }

    private var destinationDirectory: String {
        let path = transfer.destinationPath as NSString
        let directory = path.deletingLastPathComponent
        if directory == "." || directory == "/" {
            return ""
        }
        return directory
    }

    private var sourceLabel: String {
        switch transfer.sourceKind {
        case .remote:
            return String(localized: "remote")
        case .localFile:
            return String(localized: "fichier local")
        case .localFolder:
            return String(localized: "dossier local")
        case .photoLibrary:
            return String(localized: "photothèque")
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
