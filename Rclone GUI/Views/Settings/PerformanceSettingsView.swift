//
//  PerformanceSettingsView.swift
//  Rclone GUI — Views/Settings
//
//  User-tunable bandwidth ceiling and global pause for the transfer queue.
//  The persisted value is in MB/s (Double, 0 = unlimited). The view applies
//  it through TransferQueue.applyBandwidthLimit on every change so the
//  setting takes effect immediately without app restart.
//

import SwiftUI

struct PerformanceSettingsView: View {
    /// Bandwidth ceiling stored in MB/s. 0 means "no limit" (rclone rate "off").
    /// Granularity 0.5 MB/s — fine enough for cellular tuning, coarse enough
    /// to keep the slider readable.
    @AppStorage("transfer.bandwidthLimitMBps") private var bandwidthLimitMBps: Double = 0

    @State private var isPaused = false
    @State private var transientMessage: String?
    @State private var isApplying = false

    static let maxMBps: Double = 100  // 100 MB/s ≈ Gigabit ceiling — beyond user's
                                      // realistic LTE/Wi-Fi needs without making
                                      // the slider unreadable.

    var body: some View {
        Form {
            Section {
                bandwidthCard
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
            }

            Section {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("Limite")
                            .font(.subheadline)
                        Spacer()
                        Text(rateLabel)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(
                        value: $bandwidthLimitMBps,
                        in: 0...Self.maxMBps,
                        step: 0.5
                    ) {
                        Text("Limite de bande passante")
                    } minimumValueLabel: {
                        Text("0").font(.caption2).foregroundStyle(.tertiary)
                    } maximumValueLabel: {
                        Text("\(Int(Self.maxMBps))").font(.caption2).foregroundStyle(.tertiary)
                    }
                    .onChange(of: bandwidthLimitMBps) { _, newValue in
                        Task { await applyBandwidthLimit(mbps: newValue) }
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Limite globale")
            } footer: {
                Text("0 MB/s = sans limite. La limite s'applique à toutes les opérations rclone (upload + download). Idéal pour préserver la batterie ou éviter de saturer une connexion cellulaire.")
            }

            Section("Pause globale") {
                Toggle(isOn: Binding(
                    get: { isPaused },
                    set: { newValue in
                        Task { await togglePause(to: newValue) }
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(isPaused ? "Tous les transferts en pause" : "Transferts actifs")
                            .font(.body.weight(.medium))
                        Text(isPaused
                             ? "Les jobs en cours conservent leurs slots et reprendront au resume."
                             : "Mettre en pause stoppe immédiatement le débit sans annuler les jobs.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(isApplying)
            }
        }
        .navigationTitle("Performance")
        .alert("Info", isPresented: Binding(
            get: { transientMessage != nil },
            set: { if !$0 { transientMessage = nil } }
        )) {
            Button("OK", role: .cancel) { transientMessage = nil }
        } message: {
            Text(transientMessage ?? "")
        }
        .task {
            // Reflect the live queue state on appearance. The launch task in
            // Rclone_GUIApp already replayed the persisted pause/bwlimit state
            // through restoreFromPersistedState; we just mirror the resulting
            // isPausedGlobally into the local Toggle binding.
            isPaused = TransferQueue.shared.isPausedGlobally
        }
    }

    // MARK: - Actions

    private func applyBandwidthLimit(mbps: Double) async {
        isApplying = true
        defer { isApplying = false }
        let bytesPerSecond = Int64(mbps * 1024 * 1024)
        do {
            try await TransferQueue.shared.applyBandwidthLimit(bytesPerSecond: bytesPerSecond)
        } catch {
            transientMessage = "Échec de l'application de la limite : \(error.localizedDescription)"
        }
    }

    private func togglePause(to newValue: Bool) async {
        isApplying = true
        defer { isApplying = false }
        do {
            if newValue {
                try await TransferQueue.shared.pauseAllTransfers()
            } else {
                let bytesPerSecond = Int64(bandwidthLimitMBps * 1024 * 1024)
                try await TransferQueue.shared.resumeAllTransfers(bytesPerSecond: bytesPerSecond)
            }
            isPaused = newValue
        } catch {
            transientMessage = "Échec : \(error.localizedDescription)"
            // Don't flip the toggle — leave it in the previous position so
            // the user knows the action didn't go through.
            isPaused = TransferQueue.shared.isPausedGlobally
        }
    }

    // MARK: - Derived

    private var rateLabel: String {
        if bandwidthLimitMBps <= 0 { return "Illimité" }
        if bandwidthLimitMBps < 1 {
            return "\(Int(bandwidthLimitMBps * 1024)) KB/s"
        }
        return String(format: "%.1f MB/s", bandwidthLimitMBps)
    }

    @ViewBuilder
    private var bandwidthCard: some View {
        HStack(spacing: 14) {
            AppIconTile(systemImage: "speedometer", tint: .indigo, size: 54, iconSize: .title2)
            VStack(alignment: .leading, spacing: 4) {
                Text(isPaused ? "En pause" : rateLabel)
                    .font(.headline)
                Text("Limite globale appliquée à toutes les opérations rclone (upload + download).")
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
}
