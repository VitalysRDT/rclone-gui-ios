//
//  PhotoSyncStatsView.swift
//  Rclone GUI — Views/Settings
//
//  Vue dédiée aux statistiques détaillées de la sync photo : graphique débit
//  en temps réel, distribution des statuts, compteurs d'intégrité.
//

import Charts
import SwiftData
import SwiftUI

struct PhotoSyncStatsView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var summary: PhotoSyncRunSummary?
    @State private var throughputPoints: [ThroughputPoint] = []
    @State private var hashCounts = HashCounts()

    var body: some View {
        Form {
            Section {
                if let summary {
                    LabeledContent("Total à transférer", value: formatBytes(summary.totalBytes))
                    LabeledContent("Déjà transféré", value: formatBytes(summary.transferredBytes))
                    LabeledContent("Débit instantané", value: formatThroughput(summary.averageBytesPerSecond))
                    if let eta = summary.estimatedTimeRemaining, eta > 0 {
                        LabeledContent("Temps estimé", value: formatETA(eta))
                    }
                } else {
                    Text("Aucune donnée pour l'instant.")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("État global")
            }

            Section {
                if throughputPoints.count >= 2 {
                    Chart(throughputPoints) { point in
                        LineMark(
                            x: .value("Temps", point.date),
                            y: .value("Débit", point.bytesPerSecond / 1024)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(RG.photoSync.accent)
                        // Aire = accent doux pour cohérence avec le reste de l'app
                        AreaMark(
                            x: .value("Temps", point.date),
                            y: .value("Débit", point.bytesPerSecond / 1024)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(.pink.opacity(0.15))
                    }
                    .chartYAxisLabel("KB/s")
                    .frame(height: 180)
                } else {
                    Text("Le graphique apparaîtra dès que le débit sera mesuré.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Débit (fenêtre 30 s)")
            }

            if let summary {
                Section {
                    Chart {
                        BarMark(
                            x: .value("État", "Attente"),
                            y: .value("Count", summary.pendingCount)
                        )
                        .foregroundStyle(.orange)
                        BarMark(
                            x: .value("État", "En cours"),
                            y: .value("Count", summary.activeCount)
                        )
                        .foregroundStyle(.blue)
                        BarMark(
                            x: .value("État", "Terminés"),
                            y: .value("Count", summary.completedCount)
                        )
                        .foregroundStyle(.green)
                        BarMark(
                            x: .value("État", "Échecs"),
                            y: .value("Count", summary.failedCount)
                        )
                        .foregroundStyle(.red)
                        BarMark(
                            x: .value("État", "Ignorés"),
                            y: .value("Count", summary.skippedCount)
                        )
                        .foregroundStyle(.gray)
                    }
                    .frame(height: 180)
                } header: {
                    Text("Distribution par statut")
                }
            }

            Section {
                LabeledContent("Vérifiés", value: "\(hashCounts.verified)")
                LabeledContent("Hash distant manquant", value: "\(hashCounts.unsupported)")
                LabeledContent("Discordances", value: "\(hashCounts.mismatch)")
                LabeledContent("Introuvables côté remote", value: "\(hashCounts.missing)")
            } header: {
                Text("Intégrité (MD5)")
            } footer: {
                Text("La vérification est lancée automatiquement après chaque upload réussi. Une discordance indique une corruption pendant le transfert — l'asset reste marqué terminé, mais devrait être ré-uploadé manuellement.")
            }
        }
        .navigationTitle("Statistiques")
        #if os(iOS)
        .rgInlineNavTitle()
        #endif
        .task {
            await reload()
            // Live refresh tant que la vue est affichée.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(4))
                await reload()
            }
        }
    }

    private func reload() async {
        summary = await PhotoSyncService.shared.currentSummary()
        throughputPoints = PhotoSyncService.shared.throughputHistory()
            .map { ThroughputPoint(date: $0.date, bytesPerSecond: $0.bytesPerSecond) }
        hashCounts = HashCounts(modelContext: modelContext)
    }

    private func formatBytes(_ bytes: Int64) -> String { PhotoSyncFormat.bytes(bytes) }
    private func formatThroughput(_ bps: Double) -> String { PhotoSyncFormat.throughput(bps) }
    private func formatETA(_ seconds: TimeInterval) -> String { PhotoSyncFormat.eta(seconds) }
}

private struct ThroughputPoint: Identifiable {
    let date: Date
    let bytesPerSecond: Double
    var id: Date { date }
}

private struct HashCounts {
    var verified = 0
    var mismatch = 0
    var missing = 0
    var unsupported = 0

    init() {}

    init(modelContext: ModelContext) {
        verified = Self.count(in: modelContext, status: "verified")
        mismatch = Self.count(in: modelContext, status: "mismatch")
        missing = Self.count(in: modelContext, status: "missing")
        unsupported = Self.count(in: modelContext, status: "unsupported")
    }

    private static func count(in modelContext: ModelContext, status: String) -> Int {
        let descriptor = FetchDescriptor<PhotoSyncAsset>(
            predicate: #Predicate { $0.verificationStatus == status }
        )
        return (try? modelContext.fetchCount(descriptor)) ?? 0
    }
}

#Preview {
    NavigationStack {
        PhotoSyncStatsView()
    }
}
