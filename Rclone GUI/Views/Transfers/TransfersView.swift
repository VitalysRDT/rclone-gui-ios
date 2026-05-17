//
//  TransfersView.swift
//  Rclone GUI — Views/Transfers
//
//  Lists every Transfer ever started. Grouped by status (running first,
//  then pending, then completed, then failed). Pull-to-refresh re-fetches.
//

import SwiftUI
import SwiftData

struct TransfersView: View {
    @Query(sort: \Transfer.startedAt, order: .reverse) private var transfers: [Transfer]
    @Environment(\.modelContext) private var modelContext
    @State private var filter: TransferFilter = .all

    @AppStorage("transfer.bandwidthLimitMBps") private var bandwidthLimitMBps: Double = 0
    @State private var isPausedGlobally = false
    @State private var transientMessage: String?
    @State private var hapticTrigger = 0

    // Pagination des sections Terminés/Échoués : un historique de plusieurs
    // centaines de transferts faisait freezer la liste (pas de virtualisation
    // par défaut sur des Sections imbriquées). On affiche 50 par défaut + un
    // bouton "Afficher plus" qui en débloque 50 supplémentaires.
    @State private var terminalDisplayLimit: Int = 50
    private static let terminalPageSize = 50

    /// Progression live du batch rclone copy PhotoSync en cours. Mise à
    /// jour par un poll 500ms tant que la vue est à l'écran.
    @State private var photoSyncProgress: PhotoBatchLiveProgress?

    var body: some View {
        Group {
            if transfers.isEmpty && photoSyncProgress == nil {
                VStack {
                    AppEmptyStateView(
                        title: "Aucun transfert",
                        message: "Lance un téléchargement, un upload ou une sync depuis un dossier.",
                        systemImage: "arrow.up.arrow.down",
                        tint: .indigo
                    )
                    .padding()
                    Spacer(minLength: 0)
                }
            } else {
                transfersList
            }
        }
        .navigationTitle("Transferts")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    Task { await toggleGlobalPause() }
                } label: {
                    Label(
                        isPausedGlobally ? "Reprendre" : "Pause",
                        systemImage: isPausedGlobally ? "play.fill" : "pause.fill"
                    )
                }
                .accessibilityLabel(isPausedGlobally ? "Reprendre tous les transferts" : "Mettre tous les transferts en pause")
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button(role: .destructive) {
                        clearCompleted()
                    } label: {
                        Label("Effacer les transferts terminés", systemImage: "trash")
                    }
                    .disabled(!hasTerminalTransfers)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Plus d'actions de transferts")
            }
        }
        .alert("Info", isPresented: Binding(
            get: { transientMessage != nil },
            set: { if !$0 { transientMessage = nil } }
        )) {
            Button("OK", role: .cancel) { transientMessage = nil }
        } message: {
            Text(transientMessage ?? "")
        }
        .sensoryFeedback(.selection, trigger: hapticTrigger)
        .task {
            isPausedGlobally = TransferQueue.shared.isPausedGlobally
            // Poll live de la progression PhotoSync. Cadence adaptative :
            // 500ms tant qu'un batch tourne, 2s sinon (économie batterie).
            // SwiftUI cancel la closure à disappear.
            while !Task.isCancelled {
                photoSyncProgress = PhotoSyncService.shared.liveBatchProgress
                try? await Task.sleep(for: photoSyncProgress != nil ? .milliseconds(500) : .seconds(2))
            }
        }
        .onAppear {
            // L'utilisateur regarde l'écran Transferts pour voir le débit
            // réel — on désactive le throttling automatique pendant qu'il
            // est ici. Restauré quand il quitte la vue.
            TransferQueue.shared.incrementActivityBypass()
        }
        .onDisappear {
            TransferQueue.shared.decrementActivityBypass()
        }
    }

    // MARK: - Actions

    private func toggleGlobalPause() async {
        do {
            if isPausedGlobally {
                let bytesPerSecond = Int64(bandwidthLimitMBps * 1024 * 1024)
                try await TransferQueue.shared.resumeAllTransfers(bytesPerSecond: bytesPerSecond)
                isPausedGlobally = false
                transientMessage = "Transferts repris."
            } else {
                try await TransferQueue.shared.pauseAllTransfers()
                isPausedGlobally = true
                transientMessage = "Tous les transferts sont en pause."
            }
            hapticTrigger &+= 1
        } catch {
            transientMessage = "Échec : \(error.localizedDescription)"
        }
    }

    private func retry(_ transfer: Transfer) async {
        do {
            try await TransferQueue.shared.retry(transfer)
            transientMessage = "Retry lancé."
            hapticTrigger &+= 1
        } catch {
            transientMessage = error.localizedDescription
        }
    }

    @ViewBuilder
    private var transfersList: some View {
        let list = List {
            if let progress = photoSyncProgress {
                Section("Sync photos en cours") {
                    photoSyncProgressRow(progress)
                }
            }
            Section {
                TransferOverviewCard(transfers: transfers)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
            }

            Section {
                Picker("Filtre", selection: $filter) {
                    ForEach(TransferFilter.allCases) { filter in
                        Text(filter.label).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
            }

            if filteredTransfers.isEmpty {
                Section {
                    FilterEmptyRow(filter: filter)
                }
            } else {
                let groups = TransferGroup.organize(filteredTransfers)
                ForEach(groups, id: \.title) { group in
                    Section(group.title) {
                        // Cap les sections terminales (Terminés/Échoués) qui
                        // peuvent gonfler à plusieurs centaines d'éléments.
                        let isTerminal = group.title == "Terminés" || group.title == "Échoués"
                        let visibleItems = isTerminal
                            ? Array(group.items.prefix(terminalDisplayLimit))
                            : group.items
                        ForEach(visibleItems) { transfer in
                            TransferRowView(transfer: transfer)
                                .swipeActions(edge: .trailing) {
                                    if transfer.status == .running || transfer.status == .pending || transfer.status == .enqueued {
                                        Button(role: .destructive) {
                                            Task {
                                                await TransferQueue.shared.cancel(transfer)
                                            }
                                        } label: {
                                            Label("Annuler", systemImage: "xmark.circle")
                                        }
                                    } else {
                                        Button(role: .destructive) {
                                            modelContext.delete(transfer)
                                            try? modelContext.save()
                                        } label: {
                                            Label("Supprimer", systemImage: "trash")
                                        }
                                    }
                                }
                                .swipeActions(edge: .leading) {
                                    if transfer.status == .failed {
                                        Button {
                                            Task { await retry(transfer) }
                                        } label: {
                                            Label("Réessayer", systemImage: "arrow.clockwise")
                                        }
                                        .tint(.blue)
                                    }
                                }
                        }
                        if isTerminal && group.items.count > visibleItems.count {
                            Button {
                                terminalDisplayLimit += Self.terminalPageSize
                                hapticTrigger &+= 1
                            } label: {
                                HStack {
                                    Spacer()
                                    Text("Afficher \(min(Self.terminalPageSize, group.items.count - visibleItems.count)) de plus (\(group.items.count - visibleItems.count) restants)")
                                        .font(.subheadline.weight(.medium))
                                    Spacer()
                                }
                            }
                            .foregroundStyle(.tint)
                        }
                    }
                }
            }
        }
        #if os(iOS)
        list.listStyle(.insetGrouped)
        #else
        list
        #endif
    }

    private var filteredTransfers: [Transfer] {
        transfers.filter { transfer in
            switch filter {
            case .all:
                return true
            case .active:
                return transfer.status == .running || transfer.status == .pending || transfer.status == .paused || transfer.status == .enqueued
            case .completed:
                return transfer.status == .completed
            case .failed:
                return transfer.status == .failed
            }
        }
    }

    private var hasTerminalTransfers: Bool {
        transfers.contains { $0.status == .completed || $0.status == .failed }
    }

    private func clearCompleted() {
        let descriptor = FetchDescriptor<Transfer>(
            predicate: #Predicate { $0.statusRaw == "completed" || $0.statusRaw == "failed" }
        )
        guard let toDelete = try? modelContext.fetch(descriptor) else { return }
        for transfer in toDelete {
            modelContext.delete(transfer)
        }
        try? modelContext.save()
    }

    // MARK: - PhotoSync live progress row

    @ViewBuilder
    private func photoSyncProgressRow(_ progress: PhotoBatchLiveProgress) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("rclone copy → cloud", systemImage: "photo.on.rectangle.angled")
                    .font(.subheadline)
                    .foregroundStyle(.pink)
                Spacer()
                if progress.speedBytesPerSec > 1 {
                    Label(ByteCountFormatter.string(fromByteCount: Int64(progress.speedBytesPerSec), countStyle: .file) + "/s", systemImage: "speedometer")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            if progress.bytesTotal > 0 {
                ProgressView(value: Double(progress.bytesTransferred), total: Double(progress.bytesTotal))
                    .tint(.pink)
            } else {
                ProgressView()
            }
            HStack {
                Text("\(ByteCountFormatter.string(fromByteCount: progress.bytesTransferred, countStyle: .file)) / \(ByteCountFormatter.string(fromByteCount: progress.bytesTotal, countStyle: .file))")
                Spacer()
                if let etaSeconds = progress.etaSeconds, etaSeconds > 0 {
                    Text("≈ " + formatETA(seconds: etaSeconds))
                }
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            if let filename = progress.currentFilename, !filename.isEmpty {
                Text(filename)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.vertical, 4)
    }

    private func formatETA(seconds: Int64) -> String {
        let s = Int(seconds)
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(s/60)m \(s%60)s" }
        return "\(s/3600)h \((s%3600)/60)m"
    }
}

private enum TransferFilter: String, CaseIterable, Identifiable {
    case all
    case active
    case completed
    case failed

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "Tous"
        case .active: return "Actifs"
        case .completed: return "Terminés"
        case .failed: return "Échecs"
        }
    }
}

private struct TransferGroup {
    let title: String
    let items: [Transfer]

    static func organize(_ all: [Transfer]) -> [TransferGroup] {
        var running: [Transfer] = []
        var pending: [Transfer] = []
        var completed: [Transfer] = []
        var failed: [Transfer] = []
        for t in all {
            switch t.status {
            case .running: running.append(t)
            case .pending: pending.append(t)
            case .enqueued: pending.append(t)
            case .paused:  pending.append(t)
            case .completed: completed.append(t)
            case .failed: failed.append(t)
            }
        }
        var groups: [TransferGroup] = []
        if !running.isEmpty { groups.append(.init(title: "En cours", items: running)) }
        if !pending.isEmpty { groups.append(.init(title: "En attente", items: pending)) }
        if !completed.isEmpty { groups.append(.init(title: "Terminés", items: completed)) }
        if !failed.isEmpty { groups.append(.init(title: "Échoués", items: failed)) }
        return groups
    }
}

private struct TransferOverviewCard: View {
    let transfers: [Transfer]

    var body: some View {
        HStack(spacing: 14) {
            // Aggregate progress ring — same shape as the design's
            // "58%" purple ring on the Transfers artboard.
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.20), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: aggregateProgress)
                    .stroke(RG.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(percentLabel)
                    .font(.system(size: 13, weight: .bold))
                    .monospacedDigit()
            }
            .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 4) {
                Text(headlineText)
                    .font(.system(size: 15, weight: .semibold))
                Text(byteText)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(metaText)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.rgGroupedRowBackground,
                    in: RoundedRectangle(cornerRadius: RG.Radius.card, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var aggregateProgress: Double {
        let active = transfers.filter { $0.status == .running || $0.status == .paused }
        let totalDone = active.reduce(Int64(0)) { $0 + max($1.bytesTransferred, 0) }
        let totalAll = active.reduce(Int64(0)) { $0 + max($1.bytesTotal, 0) }
        guard totalAll > 0 else { return 0 }
        return Double(totalDone) / Double(totalAll)
    }

    private var percentLabel: String {
        "\(Int(aggregateProgress * 100))%"
    }

    private var headlineText: String {
        let n = activeCount
        if n == 0 { return summary }
        return n == 1 ? "1 transfert en cours" : "\(n) transferts en cours"
    }

    private var byteText: String {
        let active = transfers.filter { $0.status == .running || $0.status == .paused }
        let totalDone = active.reduce(Int64(0)) { $0 + max($1.bytesTransferred, 0) }
        let totalAll = active.reduce(Int64(0)) { $0 + max($1.bytesTotal, 0) }
        if totalAll == 0 { return summary }
        return "\(format(totalDone)) / \(format(totalAll))"
    }

    private var metaText: String {
        let parts = [
            "\(activeCount) actif\(activeCount > 1 ? "s" : "")",
            "\(completedCount) terminé\(completedCount > 1 ? "s" : "")",
            "\(failedCount) échec\(failedCount > 1 ? "s" : "")",
        ]
        return parts.joined(separator: " · ")
    }

    private func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private var activeCount: Int {
        transfers.filter { $0.status == .running || $0.status == .pending || $0.status == .paused || $0.status == .enqueued }.count
    }

    private var completedCount: Int {
        transfers.filter { $0.status == .completed }.count
    }

    private var failedCount: Int {
        transfers.filter { $0.status == .failed }.count
    }

    private var summary: String {
        let total = transfers.count
        return "\(total) transfert\(total > 1 ? "s" : "") dans l'historique"
    }
}

private struct FilterEmptyRow: View {
    let filter: TransferFilter

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(emptyMessage)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    private var emptyMessage: String {
        switch filter {
        case .all:
            return "Aucun transfert"
        case .active:
            return "Aucun transfert actif"
        case .completed:
            return "Aucun transfert terminé"
        case .failed:
            return "Aucun transfert échoué"
        }
    }
}
