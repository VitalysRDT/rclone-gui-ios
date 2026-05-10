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

    var body: some View {
        Group {
            if transfers.isEmpty {
                ContentUnavailableView(
                    "Aucun transfert",
                    systemImage: "arrow.up.arrow.down",
                    description: Text("Lance un téléchargement ou un upload depuis un dossier.")
                )
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
                        ForEach(group.items) { transfer in
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
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                AppIconTile(systemImage: "arrow.up.arrow.down.circle.fill", tint: .indigo, size: 52)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Activité des transferts")
                        .font(.headline)
                    Text(summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 10)], spacing: 10) {
                AppMetricPill(value: "\(activeCount)", label: "actifs", systemImage: "bolt.fill", tint: .blue)
                AppMetricPill(value: "\(completedCount)", label: "terminés", systemImage: "checkmark.circle", tint: .green)
                AppMetricPill(value: "\(failedCount)", label: "échecs", systemImage: "exclamationmark.triangle", tint: .red)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: .rect(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.quaternary)
        }
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
