//
//  TrashView.swift
//  Rclone GUI — Views/Settings
//
//  Lists soft-deleted files and folders awaiting auto-purge. Per-item
//  actions: restore to original location, or permanently delete now.
//  Global action: empty the trash.
//

import SwiftData
import SwiftUI

struct TrashView: View {
    @Query(sort: \TrashEntry.trashedAt, order: .reverse)
    private var entries: [TrashEntry]

    @State private var pendingRestore: TrashEntry?
    @State private var pendingPermanentDelete: TrashEntry?
    @State private var showingEmptyConfirm = false
    @State private var transientMessage: String?
    @State private var workingEntryID: String?

    @State private var hapticSuccessTrigger = 0
    @State private var hapticWarningTrigger = 0

    var body: some View {
        Group {
            if entries.isEmpty {
                ContentUnavailableView(
                    "Corbeille vide",
                    systemImage: "trash",
                    description: Text("Les fichiers supprimés apparaîtront ici. Ils sont restaurables pendant 30 jours.")
                )
            } else {
                List {
                    Section {
                        TrashHeaderCard(count: entries.count, totalBytes: entries.reduce(into: Int64(0)) { $0 += max(0, $1.sizeBytes) })
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                            .listRowBackground(Color.clear)
                    }

                    Section {
                        ForEach(entries) { entry in
                            TrashRow(entry: entry, isWorking: workingEntryID == entry.id)
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        pendingPermanentDelete = entry
                                    } label: {
                                        Label("Supprimer", systemImage: "trash.slash")
                                    }
                                    Button {
                                        pendingRestore = entry
                                    } label: {
                                        Label("Restaurer", systemImage: "arrow.uturn.backward")
                                    }
                                    .tint(.blue)
                                }
                                .contextMenu {
                                    Button {
                                        pendingRestore = entry
                                    } label: {
                                        Label("Restaurer à l'emplacement d'origine", systemImage: "arrow.uturn.backward")
                                    }
                                    Button(role: .destructive) {
                                        pendingPermanentDelete = entry
                                    } label: {
                                        Label("Supprimer définitivement", systemImage: "trash.slash")
                                    }
                                }
                        }
                    } header: {
                        Text("\(entries.count) élément\(entries.count > 1 ? "s" : "")")
                    }
                }
            }
        }
        .navigationTitle("Corbeille")
        .toolbar {
            if !entries.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button(role: .destructive) {
                        showingEmptyConfirm = true
                    } label: {
                        Label("Vider", systemImage: "trash.slash")
                    }
                }
            }
        }
        .confirmationDialog(
            "Restaurer cet élément ?",
            isPresented: Binding(
                get: { pendingRestore != nil },
                set: { if !$0 { pendingRestore = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Restaurer") {
                if let entry = pendingRestore { Task { await restore(entry) } }
                pendingRestore = nil
            }
            Button("Annuler", role: .cancel) { pendingRestore = nil }
        } message: {
            if let entry = pendingRestore {
                Text("« \(entry.originalName) » sera replacé dans \(entry.originalRemote):\(entry.originalParentPath).")
            }
        }
        .confirmationDialog(
            "Supprimer définitivement ?",
            isPresented: Binding(
                get: { pendingPermanentDelete != nil },
                set: { if !$0 { pendingPermanentDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Supprimer définitivement", role: .destructive) {
                if let entry = pendingPermanentDelete { Task { await permanentlyDelete(entry) } }
                pendingPermanentDelete = nil
            }
            Button("Annuler", role: .cancel) { pendingPermanentDelete = nil }
        } message: {
            if let entry = pendingPermanentDelete {
                Text("« \(entry.originalName) » sera supprimé du remote sans possibilité de restauration.")
            }
        }
        .confirmationDialog(
            "Vider la corbeille ?",
            isPresented: $showingEmptyConfirm,
            titleVisibility: .visible
        ) {
            Button("Tout supprimer définitivement", role: .destructive) {
                Task { await emptyAll() }
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Les \(entries.count) élément\(entries.count > 1 ? "s seront supprimés" : " sera supprimé") sans possibilité de restauration.")
        }
        .alert("Info", isPresented: Binding(
            get: { transientMessage != nil },
            set: { if !$0 { transientMessage = nil } }
        )) {
            Button("OK", role: .cancel) { transientMessage = nil }
        } message: {
            Text(transientMessage ?? "")
        }
        .sensoryFeedback(.success, trigger: hapticSuccessTrigger)
        .sensoryFeedback(.warning, trigger: hapticWarningTrigger)
    }

    // MARK: - Actions

    private func restore(_ entry: TrashEntry) async {
        workingEntryID = entry.id
        defer { workingEntryID = nil }
        do {
            try await TrashService.shared.restore(entry)
            transientMessage = "« \(entry.originalName) » restauré."
            hapticSuccessTrigger &+= 1
        } catch {
            transientMessage = "Échec de restauration : \(error.localizedDescription)"
            hapticWarningTrigger &+= 1
        }
    }

    private func permanentlyDelete(_ entry: TrashEntry) async {
        workingEntryID = entry.id
        defer { workingEntryID = nil }
        do {
            try await TrashService.shared.permanentlyDelete(entry)
            hapticWarningTrigger &+= 1
        } catch {
            transientMessage = "Échec de suppression : \(error.localizedDescription)"
            hapticWarningTrigger &+= 1
        }
    }

    private func emptyAll() async {
        let purged = await TrashService.shared.emptyAll()
        transientMessage = purged > 0
            ? "\(purged) élément\(purged > 1 ? "s" : "") supprimé\(purged > 1 ? "s" : "") définitivement."
            : "Aucun élément n'a pu être supprimé."
        hapticWarningTrigger &+= 1
    }
}

private extension TrashEntry {
    /// Original parent folder path. Empty string means the item lived at remote root.
    var originalParentPath: String {
        let parent = (originalPath as NSString).deletingLastPathComponent
        return parent.isEmpty ? "racine" : parent
    }
}

// MARK: - Subviews

private struct TrashHeaderCard: View {
    let count: Int
    let totalBytes: Int64

    var body: some View {
        HStack(spacing: 14) {
            AppIconTile(systemImage: "trash", tint: .red, size: 54, iconSize: .title2)
            VStack(alignment: .leading, spacing: 4) {
                Text(count == 1 ? "1 élément" : "\(count) éléments")
                    .font(.headline)
                Text("Total : \(formattedBytes) — Auto-purge après 30 jours.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: .rect(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.quaternary)
        }
    }

    private var formattedBytes: String {
        guard totalBytes > 0 else { return "taille inconnue" }
        return ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
    }
}

private struct TrashRow: View {
    let entry: TrashEntry
    let isWorking: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: entry.isDirectory ? "folder.fill" : "doc.fill")
                .foregroundStyle(entry.isDirectory ? .blue : .secondary)
                .frame(width: 28)
                .font(.title3)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.originalName)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(originPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(retentionLine)
                    .font(.caption2)
                    .foregroundStyle(retentionColor)
            }
            Spacer(minLength: 6)
            if isWorking {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var originPath: String {
        let parent = (entry.originalPath as NSString).deletingLastPathComponent
        let scope = parent.isEmpty ? "racine" : parent
        return "\(entry.originalRemote):\(scope)"
    }

    private var retentionLine: String {
        let remaining = entry.expiresAt.timeIntervalSince(.now)
        if remaining <= 0 { return "Expire à la prochaine purge" }
        let days = Int(remaining / 86_400)
        switch days {
        case 0: return "Expire aujourd'hui"
        case 1: return "Expire demain"
        default: return "Expire dans \(days) jours"
        }
    }

    private var retentionColor: Color {
        let remaining = entry.expiresAt.timeIntervalSince(.now)
        let days = remaining / 86_400
        if days <= 1 { return .red }
        if days <= 7 { return .orange }
        return .secondary
    }
}
