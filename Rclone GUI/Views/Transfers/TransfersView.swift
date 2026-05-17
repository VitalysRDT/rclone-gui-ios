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

    /// Synthèse agrégée du pipeline PhotoSync. C'est la source de vérité de
    /// l'écran Transferts: les photos ne sont plus représentées comme une
    /// ligne Transfer par asset, mais comme une activité rclone batchée.
    @State private var photoSyncSummary: PhotoSyncRunSummary?
    @State private var photoSyncIsEnabled = false
    @State private var photoSyncRemote: String?
    @State private var photoSyncFolder = "Phototheque"
    @State private var photoSyncActionInProgress = false
    /// Progression live du batch rclone copy en cours, uniquement utilisée
    /// pour le fichier courant et l'état inter-batch.
    @State private var photoSyncProgress: PhotoBatchLiveProgress?
    /// True tant qu'une session de sync photo tourne.
    @State private var photoSyncIsRunning = false

    var body: some View {
        Group {
            if transfers.isEmpty && !shouldShowPhotoSyncCard {
                VStack {
                    AppEmptyStateView(
                        title: "Aucun transfert",
                        message: "Lance un téléchargement, un upload ou active PhotoSync depuis les réglages.",
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
            await refreshPhotoSyncState()
            while !Task.isCancelled {
                let interval = photoSyncPollingInterval
                try? await Task.sleep(for: interval)
                await refreshPhotoSyncState()
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

    private func togglePhotoSyncPause() async {
        guard let summary = photoSyncSummary else { return }
        photoSyncActionInProgress = true
        defer { photoSyncActionInProgress = false }

        if summary.pausedByUser {
            await PhotoSyncService.shared.resumePhotoSync()
            transientMessage = "Synchro Photos reprise."
        } else {
            await PhotoSyncService.shared.pausePhotoSync()
            transientMessage = "Synchro Photos en pause."
        }
        hapticTrigger &+= 1
        await refreshPhotoSyncState()
    }

    private func retryFailedPhotoSync() async {
        photoSyncActionInProgress = true
        defer { photoSyncActionInProgress = false }

        let recycled = await PhotoSyncService.shared.retryFailedAssets()
        transientMessage = recycled > 0
            ? "\(recycled) photo(s) remise(s) en file."
            : "Aucun échec PhotoSync à réessayer."
        hapticTrigger &+= 1
        await refreshPhotoSyncState()
    }

    private func refreshPhotoSyncState() async {
        let service = PhotoSyncService.shared
        photoSyncIsEnabled = service.isEnabled
        photoSyncRemote = service.configuredRemote
        photoSyncFolder = service.configuredFolder
        photoSyncIsRunning = service.isSyncingPublic
        photoSyncProgress = service.liveBatchProgress
        photoSyncSummary = await service.currentSummary()
        photoSyncIsRunning = service.isSyncingPublic
        photoSyncProgress = service.liveBatchProgress
    }

    @ViewBuilder
    private var transfersList: some View {
        let list = List {
            if shouldShowPhotoSyncCard {
                Section {
                    PhotoSyncActivityCard(
                        summary: photoSyncSummary,
                        liveProgress: photoSyncProgress,
                        isRunning: photoSyncIsRunning,
                        isEnabled: photoSyncIsEnabled,
                        remote: photoSyncRemote,
                        folder: photoSyncFolder,
                        isActionInProgress: photoSyncActionInProgress,
                        onTogglePause: {
                            Task { await togglePhotoSyncPause() }
                        },
                        onRetryFailed: {
                            Task { await retryFailedPhotoSync() }
                        }
                    )
                    .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
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

    private var shouldShowPhotoSyncCard: Bool {
        photoSyncIsEnabled
            || photoSyncIsRunning
            || photoSyncProgress != nil
            || (photoSyncSummary?.hasTrackedPhotoSyncWork ?? false)
    }

    private var photoSyncPollingInterval: Duration {
        if photoSyncIsRunning || photoSyncProgress != nil {
            return .seconds(1)
        }
        if shouldShowPhotoSyncCard {
            return .seconds(4)
        }
        return .seconds(6)
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

    // MARK: - PhotoSync helpers
}

private extension PhotoSyncRunSummary {
    var hasTrackedPhotoSyncWork: Bool {
        indexedCount > 0
            || pendingCount > 0
            || activeCount > 0
            || completedCount > 0
            || failedCount > 0
            || totalBytes > 0
            || transferredBytes > 0
            || pausedByUser
    }
}

private struct PhotoSyncActivityCard: View {
    let summary: PhotoSyncRunSummary?
    let liveProgress: PhotoBatchLiveProgress?
    let isRunning: Bool
    let isEnabled: Bool
    let remote: String?
    let folder: String
    let isActionInProgress: Bool
    let onTogglePause: () -> Void
    let onRetryFailed: () -> Void

    var body: some View {
        AppHeroCard(
            title: "PhotoSync rclone",
            subtitle: subtitle,
            systemImage: "photo.stack",
            tint: .pink
        ) {
            VStack(alignment: .leading, spacing: 14) {
                statusLine
                progressBlock
                metricsGrid
                if let currentFilename {
                    Label {
                        Text(currentFilename)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } icon: {
                        Image(systemName: "doc")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                if summary?.isLimitedAccess == true {
                    Label("Accès Photos limité: seule la sélection autorisée est synchronisée.", systemImage: "photo.badge.exclamationmark")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.orange)
                }
                actions
            }
        }
    }

    private var subtitle: String {
        if let remote, isEnabled {
            return "Pipeline batché vers \(remote):\(folder)"
        }
        if isEnabled {
            return "Destination rclone à finaliser avant le prochain batch."
        }
        if summary?.hasTrackedPhotoSyncWork == true {
            return "Historique PhotoSync conservé, synchro actuellement inactive."
        }
        return "Sauvegarde agrégée de la photothèque via rclone copy."
    }

    private var statusLine: some View {
        HStack(spacing: 10) {
            AppStatusBadge(title: statusTitle, systemImage: statusIcon, tint: statusTint)
            if let summary, summary.averageBytesPerSecond > 1, !summary.pausedByUser {
                Label(formatThroughput(summary.averageBytesPerSecond), systemImage: "speedometer")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if let summary, let eta = summary.estimatedTimeRemaining, eta > 0, !summary.pausedByUser {
                Label("≈ \(formatETA(eta))", systemImage: "hourglass")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var progressBlock: some View {
        if let summary {
            VStack(alignment: .leading, spacing: 7) {
                ProgressView(value: progressRatio)
                    .progressViewStyle(.linear)
                    .tint(summary.pausedByUser ? .gray : .pink)
                HStack {
                    Text(progressLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int((progressRatio * 100).rounded()))%")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(summary.pausedByUser ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.pink))
                }
                if summary.totalBytes > 0 {
                    Text("\(formatBytes(summary.transferredBytes)) / \(formatBytes(summary.totalBytes))")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("PhotoSync, \(progressLabel)")
        } else {
            HStack(spacing: 10) {
                ProgressView()
                Text("Chargement de l'état PhotoSync…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var metricsGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 10)], spacing: 10) {
            PhotoSyncMetric(value: "\(summary?.pendingCount ?? 0)", label: "attente", systemImage: "clock", tint: .orange)
            PhotoSyncMetric(value: "\(summary?.activeCount ?? 0)", label: "actifs", systemImage: "bolt.fill", tint: .blue)
            PhotoSyncMetric(value: "\(summary?.completedCount ?? 0)", label: "terminés", systemImage: "checkmark.circle", tint: .green)
            PhotoSyncMetric(value: "\(summary?.failedCount ?? 0)", label: "échecs", systemImage: "exclamationmark.triangle", tint: .red)
        }
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button(action: onTogglePause) {
                Label(summary?.pausedByUser == true ? "Reprendre" : "Pause", systemImage: summary?.pausedByUser == true ? "play.fill" : "pause.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(summary?.pausedByUser == true ? .green : .pink)
            .disabled(!hasConfiguredDestination || summary == nil || isActionInProgress)

            Button(action: onRetryFailed) {
                Label("Réessayer", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .disabled((summary?.failedCount ?? 0) == 0 || summary?.pausedByUser == true || !hasConfiguredDestination || isActionInProgress)

            Spacer(minLength: 0)

            NavigationLink {
                PhotoSyncStatsView()
            } label: {
                Image(systemName: "chart.line.uptrend.xyaxis")
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Ouvrir les statistiques PhotoSync")

            NavigationLink {
                PhotoSyncSettingsView()
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Ouvrir la configuration PhotoSync")
        }
    }

    private var statusTitle: String {
        guard let summary else { return "Chargement" }
        if !isEnabled { return "Inactif" }
        if summary.pausedByUser { return "Pause" }
        if isRunning, liveProgress != nil { return "rclone copy" }
        if isRunning { return "Préparation" }
        if summary.activeCount > 0 { return "En cours" }
        if summary.pendingCount > 0 { return "En attente" }
        if summary.failedCount > 0 { return "À vérifier" }
        if summary.completedCount > 0 { return "À jour" }
        return "Prêt"
    }

    private var statusIcon: String {
        guard let summary else { return "hourglass" }
        if !isEnabled { return "power" }
        if summary.pausedByUser { return "pause.fill" }
        if isRunning, liveProgress != nil { return "arrow.triangle.2.circlepath" }
        if isRunning { return "hourglass" }
        if summary.failedCount > 0, summary.pendingCount == 0, summary.activeCount == 0 { return "exclamationmark.triangle.fill" }
        if summary.completedCount > 0, summary.pendingCount == 0, summary.activeCount == 0 { return "checkmark" }
        return "photo.stack"
    }

    private var statusTint: Color {
        guard let summary else { return .secondary }
        if !isEnabled { return .secondary }
        if summary.pausedByUser { return .orange }
        if summary.failedCount > 0, summary.pendingCount == 0, summary.activeCount == 0, !isRunning { return .red }
        if isRunning || summary.activeCount > 0 || summary.pendingCount > 0 { return .pink }
        return .green
    }

    private var progressRatio: Double {
        guard let summary else { return 0 }
        // Compteur cumulatif persistent (style `rclone copy -P`) :
        // completed / (completed + active + pending + failed). Ne
        // dépend ni de la session courante ni du byte progress du
        // batch — la barre ne reset jamais entre 2 sessions.
        let total = summary.completedCount
            + summary.activeCount
            + summary.pendingCount
            + summary.failedCount
        guard total > 0 else { return 0 }
        return min(1.0, Double(summary.completedCount) / Double(total))
    }

    private var progressLabel: String {
        guard let summary else { return "Chargement" }
        // Compteur cumulatif global X/Y, comme `rclone copy -P`.
        // Inclut les failed dans le dénominateur pour ne pas perdre
        // les échecs (qui restent à retraiter).
        let total = summary.completedCount
            + summary.activeCount
            + summary.pendingCount
            + summary.failedCount
        if total > 0 {
            let remaining = max(0, total - summary.completedCount)
            return "\(summary.completedCount) / \(total) photos uploadées · \(remaining) restantes"
        }
        if summary.indexedCount > 0 {
            return "\(summary.indexedCount) élément(s) indexé(s)"
        }
        if isRunning {
            return "Préparation du prochain batch rclone"
        }
        return isEnabled ? "Aucun élément en attente" : "PhotoSync désactivé"
    }

    private var itemTotal: Int {
        guard let summary else { return 0 }
        return summary.completedCount + summary.activeCount + summary.pendingCount
    }

    private var currentFilename: String? {
        guard let name = liveProgress?.currentFilename, !name.isEmpty else { return nil }
        return name
    }

    private var hasConfiguredDestination: Bool {
        isEnabled && remote != nil
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: max(0, bytes), countStyle: .file)
    }

    private func formatThroughput(_ bps: Double) -> String {
        "\(ByteCountFormatter.string(fromByteCount: Int64(bps), countStyle: .file))/s"
    }

    private func formatETA(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded())
        if s < 60 { return "\(s) s" }
        if s < 3600 { return "\(s / 60) min \(s % 60) s" }
        return "\(s / 3600) h \((s % 3600) / 60) min"
    }
}

private struct PhotoSyncMetric: View {
    let value: String
    let label: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 34, alignment: .leading)
        .accessibilityElement(children: .combine)
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
        if n == 0 { return "Transferts fichiers/rclone" }
        return n == 1 ? "1 transfert individuel en cours" : "\(n) transferts individuels en cours"
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
        return "\(total) opération\(total > 1 ? "s" : "") individuelle\(total > 1 ? "s" : "") dans l'historique"
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
