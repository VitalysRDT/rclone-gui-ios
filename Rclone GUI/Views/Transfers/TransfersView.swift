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

    var body: some View {
        Group {
            if transfers.isEmpty {
                ContentUnavailableView(
                    "Aucun transfert",
                    systemImage: "arrow.up.arrow.down",
                    description: Text("Lance un téléchargement ou un upload depuis un dossier.")
                )
            } else {
                List {
                    let groups = TransferGroup.organize(transfers)
                    ForEach(groups, id: \.title) { group in
                        Section(group.title) {
                            ForEach(group.items) { transfer in
                                TransferRowView(transfer: transfer)
                                    .swipeActions(edge: .trailing) {
                                        if transfer.status == .running || transfer.status == .pending {
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
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Transferts")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button(role: .destructive) {
                        clearCompleted()
                    } label: {
                        Label("Effacer les transferts terminés", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
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
