//
//  PerformanceSettingsView.swift
//  Rclone GUI — Views/Settings
//
//  User-tunable bandwidth ceiling and global pause for the transfer queue.
//  The persisted value is in MB/s (Double, 0 = unlimited). The view applies
//  it through TransferQueue.applyBandwidthLimit on every change so the
//  setting takes effect immediately without app restart.
//

import Combine
import SwiftUI

struct PerformanceSettingsView: View {
    /// Bandwidth ceiling stored in MB/s. 0 means "no limit" (rclone rate "off").
    /// Granularity 0.5 MB/s — fine enough for cellular tuning, coarse enough
    /// to keep the slider readable.
    @AppStorage("transfer.bandwidthLimitMBps") private var bandwidthLimitMBps: Double = 0
    /// File d'attente (Transferts Pro) : nb max de transferts simultanés.
    @AppStorage("transfer.maxConcurrentTransfers") private var maxConcurrent: Int = 3
    /// Suspend les transferts en cellulaire (et Wi-Fi bridé).
    @AppStorage("transfer.pauseOnCellular") private var pauseOnCellular: Bool = false
    /// Limite de bande passante distincte appliquée en cellulaire (0 = illimité).
    @AppStorage("transfer.cellularLimitMBps") private var cellularLimitMBps: Double = 0
    /// Mode Auto : la concurrence de la file est décidée automatiquement selon
    /// le réseau et l'énergie (AutoTransferPolicy). OFF → le Stepper manuel
    /// et sa clé reprennent la main à l'identique.
    @AppStorage(AutoTransferPolicy.autoModeEnabledKey) private var autoMode: Bool = true

    @State private var isPaused = false
    @State private var transientMessage: String?
    @State private var isApplying = false
    /// Résumé affiché en mode Auto (« 4 · connexion rapide »). Rafraîchi sur
    /// les mêmes évènements que la décision (réseau, thermique, mode éco).
    @State private var autoSummary = ""

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
                    .accessibilityValue(rateLabel)
                    .accessibilityHint("Faites glisser pour ajuster la limite globale de bande passante en MB/s. Zéro signifie pas de limite.")
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
                             ? "Les jobs en cours conservent leurs slots et reprendront à la reprise."
                             : "Mettre en pause stoppe immédiatement le débit sans annuler les jobs.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(isApplying)
            }

            Section {
                Toggle(isOn: Binding(
                    get: { autoMode },
                    set: { newValue in
                        autoMode = newValue
                        // Réévalue immédiatement : la décision Auto (ou le
                        // réglage manuel restauré) s'applique sans redémarrage.
                        TransferQueue.shared.refreshAutoPolicy()
                        TransferQueue.shared.scheduleNext()
                        refreshAutoSummary()
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Gestion automatique")
                            .font(.body.weight(.medium))
                        Text("Ajuste le nombre de transferts simultanés selon le réseau, la chauffe et la batterie.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if autoMode {
                    HStack {
                        Text("Transferts simultanés")
                        Spacer()
                        // verbatim : nombre + libellé déjà localisé, pas de clé à
                        // extraire. @State (et non lecture directe du singleton) :
                        // TransferQueue n'est pas Observable — sans ça la ligne
                        // resterait figée quand la décision change écran ouvert.
                        Text(verbatim: autoSummary)
                            .font(.body.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Stepper(value: Binding(
                        get: { maxConcurrent },
                        set: { newValue in
                            maxConcurrent = newValue
                            TransferQueue.shared.setMaxConcurrent(newValue)
                        }
                    ), in: 1...8) {
                        HStack {
                            Text("Transferts simultanés")
                            Spacer()
                            Text("\(maxConcurrent)")
                                .font(.body.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("File d'attente")
            } footer: {
                // Deux Text littéraux distincts (pas un ternaire de String) pour
                // rester sur LocalizedStringKey → clés extraites dans le catalogue.
                if autoMode {
                    Text("Wi-Fi : 4 · Cellulaire : 2 · Économie d'énergie ou chauffe : 1-2 · Surchauffe critique : 1. Les petits fichiers passent en premier et un échec hors-ligne reprend tout seul au retour du réseau. Vos réglages manuels sont conservés et restaurés si vous désactivez le mode automatique.")
                } else {
                    Text("Nombre maximum de téléchargements/envois actifs en même temps. Les suivants patientent dans la file et démarrent automatiquement dès qu'un slot se libère.")
                }
            }

            Section {
                Toggle(isOn: Binding(
                    get: { pauseOnCellular },
                    set: { newValue in
                        pauseOnCellular = newValue
                        Task { await TransferQueue.shared.applyNetworkPolicy() }
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Pause en cellulaire")
                            .font(.body.weight(.medium))
                        Text("Suspend les transferts sur données cellulaires (et Wi-Fi en mode données réduites). Ils reprennent automatiquement en Wi-Fi.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if !pauseOnCellular {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Limite cellulaire")
                                .font(.subheadline)
                            Spacer()
                            Text(cellularRateLabel)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: Binding(
                            get: { cellularLimitMBps },
                            set: { newValue in
                                cellularLimitMBps = newValue
                                Task { await TransferQueue.shared.applyNetworkPolicy() }
                            }
                        ), in: 0...Self.maxMBps, step: 0.5)
                        .accessibilityValue(cellularRateLabel)
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Text("Réseau cellulaire")
            } footer: {
                Text("Limite distincte appliquée quand l'appareil est en cellulaire. 0 MB/s = sans limite.")
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
            refreshAutoSummary()
        }
        // Suit les mêmes évènements que refreshAutoPolicy pour que la ligne
        // « Transferts simultanés » reste juste écran ouvert (bascule Wi-Fi →
        // cellulaire, chauffe…). receive(on:) : les notifications thermique/
        // énergie peuvent arriver hors main thread.
        .onReceive(NotificationCenter.default.publisher(for: .networkPathDidChange).receive(on: RunLoop.main)) { _ in
            refreshAutoSummary()
        }
        .onReceive(NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification).receive(on: RunLoop.main)) { _ in
            refreshAutoSummary()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange).receive(on: RunLoop.main)) { _ in
            refreshAutoSummary()
        }
    }

    /// Réévalue la décision Auto (idempotente) puis recopie le résumé dans le
    /// @State — TransferQueue n'est pas Observable, c'est ce @State qui rend
    /// la ligne réactive.
    private func refreshAutoSummary() {
        TransferQueue.shared.refreshAutoPolicy()
        autoSummary = "\(TransferQueue.shared.maxConcurrent) · \(TransferQueue.shared.currentAutoDecision.reason.localizedLabel)"
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
        if bandwidthLimitMBps <= 0 { return String(localized: "Illimité") }
        if bandwidthLimitMBps < 1 {
            return "\(Int(bandwidthLimitMBps * 1024)) KB/s"
        }
        return String(format: "%.1f MB/s", bandwidthLimitMBps)
    }

    private var cellularRateLabel: String {
        if cellularLimitMBps <= 0 { return String(localized: "Illimité") }
        if cellularLimitMBps < 1 {
            return "\(Int(cellularLimitMBps * 1024)) KB/s"
        }
        return String(format: "%.1f MB/s", cellularLimitMBps)
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
