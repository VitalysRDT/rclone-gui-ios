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
    /// C3 : remplace l'ancien `transientMessage` + `.alert` bloquant
    /// par un toast non-bloquant qui se dismiss tout seul.
    @State private var toast: AppToast?
    @State private var hapticTrigger = 0
    /// Export des logs de transfert (catégorie "transfer") → ShareSheet.
    @State private var logExportURL: URL?
    @State private var showLogShare = false

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
    @State private var photoSyncFolder = "Photothèque"
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
            ToolbarItem(placement: .navigation) {
                Button {
                    Task { await toggleGlobalPause() }
                } label: {
                    Label(
                        globalPauseShowsResume ? "Reprendre" : "Pause",
                        systemImage: globalPauseShowsResume ? "play.fill" : "pause.fill"
                    )
                }
                .disabled(!hasActivePausable && !hasPausedResumable)
                .accessibilityLabel(globalPauseShowsResume ? "Reprendre tous les transferts" : "Mettre tous les transferts en pause")
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        Task { await exportTransferLogs() }
                    } label: {
                        Label("Exporter les logs de transfert", systemImage: "square.and.arrow.up")
                    }
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
            #if os(iOS)
            // Mode édition : permet de réordonner la file « En attente » par
            // glisser-déposer (handles de déplacement). Affiché seulement s'il
            // y a une file.
            if hasQueuedItems {
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                }
            }
            #endif
        }
        .sheet(isPresented: $showLogShare) {
            if let url = logExportURL {
                ShareLink(item: url) {
                    Label("Partager le fichier de logs", systemImage: "square.and.arrow.up")
                        .padding()
                }
            }
        }
        .appToast($toast)
        .sensoryFeedback(.selection, trigger: hapticTrigger)
        .task {
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

    /// Le bouton global est piloté par l'état RÉEL des transferts (et non par
    /// un flag local qui pouvait désynchroniser des pauses par-ligne) : s'il
    /// reste des transferts actifs on propose « Pause », sinon « Reprendre ».
    private func isActivePausable(_ t: Transfer) -> Bool {
        let isActive: Bool = t.status == .running || t.status == .pending || t.status == .enqueued
        return isActive && t.sourceKind != .photoLibrary && t.kind != .delete
    }

    private func isPausedResumable(_ t: Transfer) -> Bool {
        t.status == .paused && t.sourceKind != .photoLibrary
    }

    private var hasActivePausable: Bool {
        transfers.contains(where: isActivePausable)
    }

    private var hasPausedResumable: Bool {
        transfers.contains(where: isPausedResumable)
    }

    private var globalPauseShowsResume: Bool {
        !hasActivePausable && hasPausedResumable
    }

    /// Y a-t-il des transferts en file d'attente (réordonnables) ?
    private var hasQueuedItems: Bool {
        transfers.contains { $0.status == .enqueued || $0.status == .pending }
    }

    private func toggleGlobalPause() async {
        do {
            if globalPauseShowsResume {
                let bytesPerSecond = Int64(bandwidthLimitMBps * 1024 * 1024)
                try await TransferQueue.shared.resumeAllTransfers(bytesPerSecond: bytesPerSecond)
                toast = AppToast(title: String(localized: "Transferts repris"), severity: .success)
            } else {
                try await TransferQueue.shared.pauseAllTransfers()
                toast = AppToast(title: String(localized: "Tous les transferts sont en pause"), severity: .info)
            }
            hapticTrigger &+= 1
        } catch {
            toast = AppToast(title: String(localized: "Échec"), message: error.localizedDescription, severity: .error)
        }
    }

    private func pauseTransfer(_ transfer: Transfer) async {
        await TransferQueue.shared.pause(transfer)
        toast = AppToast(title: String(localized: "Transfert en pause"), severity: .info)
        hapticTrigger &+= 1
    }

    private func resumeTransfer(_ transfer: Transfer) async {
        do {
            try await TransferQueue.shared.resume(transfer)
            toast = AppToast(title: String(localized: "Transfert repris"), severity: .success)
            hapticTrigger &+= 1
        } catch {
            toast = AppToast(title: String(localized: "Reprise impossible"), message: error.localizedDescription, severity: .error)
        }
    }

    /// Menu contextuel (appui long / clic droit) — mêmes actions que les
    /// swipe gauche/droite, mais robuste au rafraîchissement continu de la
    /// liste pendant un transfert long (le swipe se referme tout seul quand
    /// les stats live re-render la ligne) et bien plus naturel sur macOS.
    @ViewBuilder
    private func transferRowMenu(_ transfer: Transfer) -> some View {
        switch transfer.status {
        case .running, .pending, .enqueued:
            if transfer.status == .enqueued {
                Button {
                    TransferQueue.shared.prioritize(transfer)
                    hapticTrigger &+= 1
                } label: {
                    Label("Prioriser", systemImage: "arrow.up.to.line")
                }
            }
            if transfer.kind != .delete {
                Button {
                    Task { await pauseTransfer(transfer) }
                } label: {
                    Label("Pause", systemImage: "pause.fill")
                }
            }
            Button(role: .destructive) {
                Task { await TransferQueue.shared.cancel(transfer) }
            } label: {
                Label("Annuler", systemImage: "xmark.circle")
            }
        case .paused:
            Button {
                Task { await resumeTransfer(transfer) }
            } label: {
                Label("Reprendre", systemImage: "play.fill")
            }
            Button(role: .destructive) {
                deleteTransfer(transfer)
            } label: {
                Label("Supprimer", systemImage: "trash")
            }
        case .failed:
            Button {
                Task { await retry(transfer) }
            } label: {
                Label("Réessayer", systemImage: "arrow.clockwise")
            }
            Button(role: .destructive) {
                deleteTransfer(transfer)
            } label: {
                Label("Supprimer", systemImage: "trash")
            }
        case .completed:
            Button(role: .destructive) {
                deleteTransfer(transfer)
            } label: {
                Label("Supprimer", systemImage: "trash")
            }
        }
    }

    private func deleteTransfer(_ transfer: Transfer) {
        modelContext.delete(transfer)
        try? modelContext.save()
    }

    private func exportTransferLogs() async {
        do {
            let url = try await LogService.shared.exportAsFile(category: "transfer")
            logExportURL = url
            showLogShare = true
        } catch {
            toast = AppToast(title: String(localized: "Export échoué"), message: error.localizedDescription, severity: .error)
        }
    }

    // MARK: - Lignes & en-têtes

    /// Une ligne de transfert + ses swipes + son menu contextuel. `position`
    /// est le rang dans la file (#n), affiché uniquement pour les `.enqueued`.
    @ViewBuilder
    private func transferRow(_ transfer: Transfer, position: Int?) -> some View {
        TransferRowView(transfer: transfer, queuePosition: position)
            .swipeActions(edge: .trailing) {
                if transfer.status == .running || transfer.status == .pending || transfer.status == .enqueued {
                    Button(role: .destructive) {
                        Task { await TransferQueue.shared.cancel(transfer) }
                    } label: {
                        Label("Annuler", systemImage: "xmark.circle")
                    }
                    if transfer.kind != .delete {
                        Button {
                            Task { await pauseTransfer(transfer) }
                        } label: {
                            Label("Pause", systemImage: "pause.fill")
                        }
                        .tint(.orange)
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
                if transfer.status == .paused {
                    Button {
                        Task { await resumeTransfer(transfer) }
                    } label: {
                        Label("Reprendre", systemImage: "play.fill")
                    }
                    .tint(.green)
                } else if transfer.status == .failed {
                    Button {
                        Task { await retry(transfer) }
                    } label: {
                        Label("Réessayer", systemImage: "arrow.clockwise")
                    }
                    .tint(.blue)
                }
            }
            .contextMenu {
                transferRowMenu(transfer)
            }
    }

    @ViewBuilder
    private func groupHeader(_ group: TransferGroup) -> some View {
        HStack {
            Text(group.title)
            Spacer()
            if let detail = headerDetail(group) {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    /// Indicateur de file : slots utilisés/max sur « En cours », nombre en
    /// attente sur « En attente ».
    private func headerDetail(_ group: TransferGroup) -> String? {
        switch group.role {
        case .running:
            return "\(runningQueuedCount)/\(TransferQueue.shared.maxConcurrent) actifs"
        case .pending:
            let n = group.items.count
            return n > 1 ? "\(n) en file" : "1 en file"
        default:
            return nil
        }
    }

    /// Transferts download/upload réellement en cours (ceux bornés par la file).
    private var runningQueuedCount: Int {
        transfers.filter {
            $0.status == .running && ($0.kind == .download || $0.kind == .upload)
        }.count
    }

    /// Glisser-déposer dans la file : renumérote `queueOrder` selon le nouvel
    /// ordre affiché, puis relance le scheduler.
    private func moveInQueue(_ items: [Transfer], from source: IndexSet, to destination: Int) {
        var reordered = items
        reordered.move(fromOffsets: source, toOffset: destination)
        for (index, transfer) in reordered.enumerated() {
            transfer.queueOrder = index
        }
        try? modelContext.save()
        TransferQueue.shared.scheduleNext()
        hapticTrigger &+= 1
    }

    private func retry(_ transfer: Transfer) async {
        do {
            try await TransferQueue.shared.retry(transfer)
            toast = AppToast(title: String(localized: "Retry lancé"), severity: .success)
            hapticTrigger &+= 1
        } catch {
            toast = AppToast(title: String(localized: "Échec retry"), message: error.localizedDescription, severity: .error)
        }
    }

    private func togglePhotoSyncPause() async {
        guard let summary = photoSyncSummary else { return }
        photoSyncActionInProgress = true
        defer { photoSyncActionInProgress = false }

        if summary.pausedByUser {
            await PhotoSyncService.shared.resumePhotoSync()
            toast = AppToast(title: String(localized: "Synchro Photos reprise"), severity: .success)
        } else {
            await PhotoSyncService.shared.pausePhotoSync()
            toast = AppToast(title: String(localized: "Synchro Photos en pause"), severity: .info)
        }
        hapticTrigger &+= 1
        await refreshPhotoSyncState()
    }

    private func retryFailedPhotoSync() async {
        photoSyncActionInProgress = true
        defer { photoSyncActionInProgress = false }

        let recycled = await PhotoSyncService.shared.retryFailedAssets()
        if recycled > 0 {
            toast = AppToast(
                title: "\(recycled) photo(s) remise(s) en file",
                severity: .success
            )
        } else {
            toast = AppToast(
                title: "Aucun échec PhotoSync à réessayer",
                severity: .info
            )
        }
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
                    Section {
                        // Cap les sections terminales (Terminés/Échoués) qui
                        // peuvent gonfler à plusieurs centaines d'éléments.
                        let isTerminal = group.role == .completed || group.role == .failed
                        let visibleItems = isTerminal
                            ? Array(group.items.prefix(terminalDisplayLimit))
                            : group.items
                        if group.reorderable {
                            // File d'attente : réordonnable par glisser-déposer.
                            // L'ordre affiché = ordre du scheduler (queueOrder).
                            ForEach(Array(visibleItems.enumerated()), id: \.element.id) { index, transfer in
                                transferRow(transfer, position: transfer.status == .enqueued ? index + 1 : nil)
                            }
                            .onMove { source, destination in
                                moveInQueue(visibleItems, from: source, to: destination)
                            }
                        } else {
                            ForEach(visibleItems) { transfer in
                                transferRow(transfer, position: nil)
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
                    } header: {
                        groupHeader(group)
                    }
                }
            }
        }
        #if os(iOS)
        list.rgInsetGroupedList()
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

// `hasTrackedPhotoSyncWork` is now a computed property on
// `PhotoSyncRunSummary` itself (see PhotoSyncService.swift), so every
// PhotoSync surface (Transfers, Settings, Home mini-card) sees the
// same definition.

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
            subtitle: LocalizedStringKey(subtitle),
            systemImage: "photo.stack",
            tint: RG.photoSync.accent
        ) {
            VStack(alignment: .leading, spacing: 14) {
                statusLine
                progressBlock
                metricsGrid
                transferringFilesList
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
            return String(localized: "Pipeline batché vers \(remote):\(folder)")
        }
        if isEnabled {
            return String(localized: "Destination rclone à finaliser avant le prochain batch.")
        }
        if summary?.hasTrackedPhotoSyncWork == true {
            return String(localized: "Historique PhotoSync conservé, synchro actuellement inactive.")
        }
        return String(localized: "Sauvegarde agrégée de la photothèque via rclone copy.")
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
                    .tint(summary.pausedByUser ? .gray : RG.photoSync.accent)
                    .animation(.spring(duration: 0.4, bounce: 0.15), value: progressRatio)
                HStack {
                    Text(progressLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                    Spacer()
                    Text("\(PhotoSyncFormat.percent(progressRatio))%")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(summary.pausedByUser ? AnyShapeStyle(.secondary) : AnyShapeStyle(RG.photoSync.accent))
                        .contentTransition(.numericText(value: progressRatio))
                }
                if summary.totalBytes > 0 {
                    Text("\(formatBytes(summary.transferredBytes)) / \(formatBytes(summary.totalBytes))")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                        .contentTransition(.numericText())
                }
                if let sessionETA = summary.sessionEstimatedRemaining,
                   sessionETA > 0,
                   !summary.pausedByUser {
                    Text("≈ \(formatETA(sessionETA)) restant(e)s")
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
        // D3 : `AppMetricPill` partagé (au lieu du `PhotoSyncMetric`
        // local dupliqué). Aligne le rendu Transferts avec PhotoSyncSettings
        // qui utilise déjà `AppMetricPill`. Grille éagère obligatoire : cette
        // card vit dans une row de la List et se re-rend chaque seconde
        // pendant une sync (cf. AppMetricPillGrid).
        AppMetricPillGrid(items: [
            .init(value: "\(summary?.pendingCount ?? 0)", label: "attente", systemImage: "clock", tint: .orange),
            .init(value: "\(summary?.activeCount ?? 0)", label: "actifs", systemImage: "bolt.fill", tint: .blue),
            .init(value: "\(summary?.completedCount ?? 0)", label: "terminés", systemImage: "checkmark.circle", tint: .green),
            .init(value: "\(summary?.failedCount ?? 0)", label: "échecs", systemImage: "exclamationmark.triangle", tint: .red),
        ])
        .animation(.spring(duration: 0.35, bounce: 0.18), value: summary?.completedCount)
        .animation(.spring(duration: 0.35, bounce: 0.18), value: summary?.failedCount)
    }

    /// Affichage des fichiers actuellement en cours de transfert (rclone
    /// `core/stats.transferring`). Reproduit le comportement de la sortie
    /// `rclone copy --progress` qui liste fichier par fichier avec son
    /// avancement et son débit. Limité à 5 lignes pour ne pas envahir
    /// la card. Caché si rien en cours.
    @ViewBuilder
    private var transferringFilesList: some View {
        if let files = liveProgress?.transferringFiles, !files.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label("Transferts en cours", systemImage: "arrow.up.doc.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(files.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                ForEach(files.prefix(5)) { file in
                    TransferringFileRow(file: file)
                }
                if files.count > 5 {
                    Text("+\(files.count - 5) autre(s)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.top, 4)
        }
    }

    private var actions: some View {
        HStack(spacing: 12) {
            Button(action: onTogglePause) {
                actionIcon(
                    summary?.pausedByUser == true ? "play.fill" : "pause.fill",
                    tint: summary?.pausedByUser == true ? .green : RG.photoSync.accent,
                    filled: true
                )
            }
            .buttonStyle(.plain)
            .disabled(!hasConfiguredDestination || summary == nil || isActionInProgress)
            .accessibilityLabel(summary?.pausedByUser == true ? "Reprendre PhotoSync" : "Mettre PhotoSync en pause")

            Button(action: onRetryFailed) {
                actionIcon("arrow.clockwise", tint: .purple)
            }
            .buttonStyle(.plain)
            .disabled((summary?.failedCount ?? 0) == 0 || summary?.pausedByUser == true || !hasConfiguredDestination || isActionInProgress)
            .accessibilityLabel("Réessayer les échecs PhotoSync")

            Spacer(minLength: 0)

            NavigationLink {
                PhotoSyncStatsView()
            } label: {
                actionIcon("chart.line.uptrend.xyaxis", tint: .primary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Ouvrir les statistiques PhotoSync")

            NavigationLink {
                PhotoSyncSettingsView()
            } label: {
                actionIcon("gearshape", tint: .primary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Ouvrir la configuration PhotoSync")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 2)
    }

    private func actionIcon(_ systemImage: String, tint: Color, filled: Bool = false) -> some View {
        Image(systemName: systemImage)
            .font(.title3.weight(.semibold))
            .foregroundStyle(filled ? Color.white : tint)
            .frame(width: 48, height: 48)
            .background(
                filled ? tint : tint.opacity(0.10),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay {
                if !filled {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(.quaternary)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var statusTitle: String {
        guard let summary else { return String(localized: "Chargement") }
        if !isEnabled { return String(localized: "Inactif") }
        if summary.pausedByUser { return String(localized: "Pause") }
        if isRunning, liveProgress != nil { return "rclone copy" }
        if isRunning { return String(localized: "Préparation") }
        if summary.activeCount > 0 { return String(localized: "En cours") }
        if summary.pendingCount > 0 { return String(localized: "En attente") }
        if summary.failedCount > 0 { return String(localized: "À vérifier") }
        if summary.completedCount > 0 { return String(localized: "À jour") }
        return String(localized: "Prêt")
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
        if isRunning || summary.activeCount > 0 || summary.pendingCount > 0 { return RG.photoSync.accent }
        return .green
    }

    private var progressRatio: Double {
        // Source unique : `displayProgress` (ratchet monotone côté
        // service). Ne descend jamais, même si l'indexer découvre
        // soudainement de nouvelles photos en cours de session.
        summary?.displayProgress ?? 0
    }

    private var progressLabel: String {
        guard let summary else { return String(localized: "Chargement") }
        if summary.effectiveTotal == 0 {
            if isRunning { return String(localized: "Préparation du prochain batch rclone") }
            return isEnabled ? String(localized: "Aucun élément en attente") : String(localized: "PhotoSync désactivé")
        }
        return summary.displayLabel
    }

    private var itemTotal: Int {
        summary?.effectiveTotal ?? 0
    }

    private var currentFilename: String? {
        guard let name = liveProgress?.currentFilename, !name.isEmpty else { return nil }
        return name
    }

    private var hasConfiguredDestination: Bool {
        isEnabled && remote != nil
    }

    private func formatBytes(_ bytes: Int64) -> String { PhotoSyncFormat.bytes(bytes) }
    private func formatThroughput(_ bps: Double) -> String { PhotoSyncFormat.throughput(bps) }
    private func formatETA(_ seconds: TimeInterval) -> String { PhotoSyncFormat.eta(seconds) }
}

// D3 : `PhotoSyncMetric` supprimé au profit d'`AppMetricPill` (partagé,
// voir AppUIComponents.swift). Le design en pill avec glass surface
// s'aligne sur le reste de l'app.

private enum TransferFilter: String, CaseIterable, Identifiable {
    case all
    case active
    case completed
    case failed

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return String(localized: "Tous")
        case .active: return String(localized: "Actifs")
        case .completed: return String(localized: "Terminés")
        case .failed: return String(localized: "Échecs")
        }
    }
}

private struct TransferGroup {
    enum Role { case running, paused, pending, completed, failed }
    let title: String
    let items: [Transfer]
    let role: Role
    /// Seule la file « En attente » est réordonnable par glisser-déposer.
    var reorderable: Bool { role == .pending }

    static func organize(_ all: [Transfer]) -> [TransferGroup] {
        var running: [Transfer] = []
        var paused: [Transfer] = []
        var pending: [Transfer] = []
        var completed: [Transfer] = []
        var failed: [Transfer] = []
        for t in all {
            switch t.status {
            case .running: running.append(t)
            case .pending: pending.append(t)
            case .enqueued: pending.append(t)
            case .paused:  paused.append(t)
            case .completed: completed.append(t)
            case .failed: failed.append(t)
            }
        }
        // La file affichée suit l'ordre du scheduler (queueOrder asc, puis
        // ancienneté) pour que le rang #n et le glisser-déposer soient cohérents.
        pending.sort { ($0.queueOrder, $0.startedAt) < ($1.queueOrder, $1.startedAt) }
        var groups: [TransferGroup] = []
        if !running.isEmpty { groups.append(.init(title: String(localized: "En cours"), items: running, role: .running)) }
        if !paused.isEmpty { groups.append(.init(title: String(localized: "En pause"), items: paused, role: .paused)) }
        if !pending.isEmpty { groups.append(.init(title: String(localized: "En attente"), items: pending, role: .pending)) }
        if !completed.isEmpty { groups.append(.init(title: String(localized: "Terminés"), items: completed, role: .completed)) }
        if !failed.isEmpty { groups.append(.init(title: String(localized: "Échec"), items: failed, role: .failed)) }
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
        if n == 0 { return String(localized: "Transferts fichiers/rclone") }
        return n == 1 ? String(localized: "1 transfert individuel en cours") : String(localized: "\(n) transferts individuels en cours")
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
            String(localized: "\(activeCount) actif\(activeCount > 1 ? "s" : "")"),
            String(localized: "\(completedCount) terminé\(completedCount > 1 ? "s" : "")"),
            String(localized: "\(failedCount) échec\(failedCount > 1 ? "s" : "")"),
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
        return String(localized: "\(total) opération\(total > 1 ? "s" : "") individuelle\(total > 1 ? "s" : "") dans l'historique")
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
            return String(localized: "Aucun transfert")
        case .active:
            return String(localized: "Aucun transfert actif")
        case .completed:
            return String(localized: "Aucun transfert terminé")
        case .failed:
            return String(localized: "Aucun transfert échoué")
        }
    }
}

/// Ligne d'un fichier en cours de transfert (style « rclone copy --progress »).
/// Affiche le nom (tronqué), une mini-barre de progression et le débit/ETA.
private struct TransferringFileRow: View {
    let file: PhotoBatchLiveProgress.TransferringFile

    var body: some View {
        accessibilityWrapped
    }

    @ViewBuilder
    private var accessibilityWrapped: some View {
        coreBody
            .accessibilityElement(children: .combine)
            .accessibilityLabel(a11yLabel)
    }

    /// D7 : compose une description complète pour VoiceOver — nom de
    /// fichier + pourcentage + débit + ETA si dispo. Évite que les
    /// éléments enfants soient lus individuellement.
    private var a11yLabel: String {
        var parts: [String] = [displayName]
        if file.bytesTotal > 0 {
            let pct = Int((Double(file.bytesTransferred) / Double(file.bytesTotal) * 100).rounded())
            parts.append("\(pct) pour cent")
        }
        if file.speedBytesPerSec > 1 {
            parts.append("débit \(PhotoSyncFormat.throughput(file.speedBytesPerSec))")
        }
        if let eta = file.etaSeconds, eta > 0 {
            parts.append("ETA \(eta) secondes")
        }
        return parts.joined(separator: ", ")
    }

    @ViewBuilder
    private var coreBody: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: "doc")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text(displayName)
                    .font(.caption.monospacedDigit())
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                if file.speedBytesPerSec > 1 {
                    Text(ByteCountFormatter.string(fromByteCount: Int64(file.speedBytesPerSec), countStyle: .file) + "/s")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            if file.bytesTotal > 0 {
                let clamped = min(Double(file.bytesTransferred), Double(file.bytesTotal))
                ProgressView(value: clamped, total: Double(file.bytesTotal))
                    .progressViewStyle(.linear)
                    .tint(RG.photoSync.accent.opacity(0.7))
                    .frame(height: 3)
                HStack {
                    Text("\(ByteCountFormatter.string(fromByteCount: file.bytesTransferred, countStyle: .file)) / \(ByteCountFormatter.string(fromByteCount: file.bytesTotal, countStyle: .file))")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                    Spacer()
                    if let eta = file.etaSeconds, eta > 0 {
                        Text("≈ \(eta)s")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    /// Affiche juste le nom de fichier (sans le chemin parent) pour
    /// économiser de l'espace horizontal.
    private var displayName: String {
        (file.name as NSString).lastPathComponent
    }
}
