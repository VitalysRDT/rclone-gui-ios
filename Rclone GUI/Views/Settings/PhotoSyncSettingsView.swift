//
//  PhotoSyncSettingsView.swift
//  Rclone GUI — Views/Settings
//
//  Controls opportunistic Photo Library backup to a selected rclone remote.
//

import SwiftData
import SwiftUI
#if os(iOS)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct PhotoSyncSettingsView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var remotes: [String] = []
    @State private var enabled = false
    @State private var selectedRemote = ""
    @State private var folder = "Photothèque"
    @State private var requiresPower = true
    @State private var allowsCellular = false
    @State private var isSyncing = false
    @State private var message: String?
    @State private var stats = PhotoSyncStats()
    @State private var recentAssets: [PhotoSyncAsset] = []
    @State private var selectedAlbumCount = 0
    @State private var suspensionReason: String?
    @State private var verifyProgress: PhotoSyncVerifyProgress?
    @State private var activeFilterCount = 0

    @AppStorage("photosync.notificationsEnabled") private var notificationsEnabled = false
    @AppStorage("photoSync.autoSyncOnImport") private var autoSyncOnImport = true

    var body: some View {
        Form {
            Section {
                AppHeroCard(
                    title: "Synchro Photos",
                    subtitle: "Backup opportuniste de ta photothèque vers un remote rclone.",
                    systemImage: "photo.stack",
                    tint: RG.photoSync.accent
                ) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 10)], spacing: 10) {
                        AppMetricPill(value: "\(stats.pending)", label: "attente", systemImage: "clock", tint: .orange)
                        AppMetricPill(value: "\(stats.active)", label: "actifs", systemImage: "bolt.fill", tint: .blue)
                        AppMetricPill(value: "\(stats.completed)", label: "terminés", systemImage: "checkmark.circle", tint: .green)
                        if stats.skipped > 0 {
                            AppMetricPill(value: "\(stats.skipped)", label: "ignorées", systemImage: "minus.circle", tint: .gray)
                        }
                    }

                    if shouldShowProgressBar {
                        progressBar
                            .padding(.top, 4)
                    }
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
            }

            Section {
                Toggle("Activer la synchro Photos", isOn: $enabled)
                Picker("Remote", selection: $selectedRemote) {
                    Text("Choisir…").tag("")
                    if !selectedRemote.isEmpty && !remotes.contains(selectedRemote) {
                        Text("\(selectedRemote) (configuré)").tag(selectedRemote)
                    }
                    ForEach(remotes, id: \.self) { remote in
                        Text(remote).tag(remote)
                    }
                }
                TextField("Dossier distant", text: $folder)
                    .autocorrectionDisabled(true)
                    #if os(iOS)
                    .rgNoAutocap()
                    #endif
            } footer: {
                Text("Backup de ta photothèque vers rclone uniquement. Les originaux HEIC/MOV sont conservés, aucune suppression locale automatique.")
            }

            Section {
                Toggle("Exiger la charge", isOn: $requiresPower)
                Toggle("Autoriser le cellulaire", isOn: $allowsCellular)
            } header: {
                Text("Politique")
            } footer: {
                Text("Par défaut, les gros uploads attendent Wi-Fi + charge. iOS décide quand les tâches arrière-plan peuvent reprendre.")
            }

            #if os(iOS) || os(macOS)
            Section {
                NavigationLink {
                    PhotoSyncAlbumPicker()
                } label: {
                    HStack {
                        Text("Albums à sauvegarder")
                        Spacer()
                        Text(selectedAlbumCount == 0 ? "Tous" : "\(selectedAlbumCount)")
                            .foregroundStyle(.secondary)
                    }
                }
                NavigationLink {
                    PhotoSyncFiltersView()
                } label: {
                    HStack {
                        Text("Filtres média")
                        Spacer()
                        Text(activeFilterCount == 0 ? "Aucun" : "\(activeFilterCount)")
                            .foregroundStyle(.secondary)
                    }
                }
                NavigationLink {
                    PhotoSyncStatsView()
                } label: {
                    Label("Statistiques détaillées", systemImage: "chart.line.uptrend.xyaxis")
                }
                Toggle("Notifications après sync", isOn: $notificationsEnabled)
                    .onChange(of: notificationsEnabled) { _, newValue in
                        if newValue { Task { await PhotoSyncService.shared.requestNotificationAuthorization() } }
                    }
                Toggle("Synchro auto à l'import", isOn: $autoSyncOnImport)
                    .onChange(of: autoSyncOnImport) { _, newValue in
                        PhotoSyncService.shared.autoSyncOnImport = newValue
                    }
            } header: {
                Text("Filtres et notifications")
            } footer: {
                Text("Sans album sélectionné, toutes les photos visibles sont sauvegardées. Une notification locale signalera la fin de chaque cycle de sync si vous l'autorisez.")
            }
            #endif

            #if os(iOS) || os(macOS)
            if let suspensionReason {
                Section {
                    Label {
                        Text(suspensionReason)
                            .font(.subheadline)
                    } icon: {
                        Image(systemName: "pause.circle.fill")
                            .foregroundStyle(.orange)
                    }
                } header: {
                    Text("Synchro en pause")
                } footer: {
                    Text("Le pipeline reprend automatiquement dès que la condition est levée — vous n'avez rien à faire.")
                }
            }
            #endif

            Section {
                Button {
                    save()
                    Task { await syncNow() }
                } label: {
                    if isSyncing {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Synchronisation…")
                        }
                    } else {
                        Label("Synchroniser maintenant", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                .disabled(selectedRemote.isEmpty || isSyncing || stats.pausedByUser)

                Button("Enregistrer la configuration") {
                    save()
                }
                .disabled(selectedRemote.isEmpty && enabled)
            } footer: {
                if let message {
                    Text(message)
                }
            }

            Section {
                Button {
                    Task { await togglePause() }
                } label: {
                    if stats.pausedByUser {
                        Label("Reprendre la synchro", systemImage: "play.fill")
                    } else {
                        Label("Mettre en pause", systemImage: "pause.fill")
                    }
                }
                .disabled(selectedRemote.isEmpty)

                if stats.failed > 0 {
                    Button {
                        Task { await retryFailed() }
                    } label: {
                        Label("Réessayer les échecs (\(stats.failed))", systemImage: "arrow.clockwise.circle")
                    }
                    .disabled(stats.pausedByUser)

                    Button(role: .destructive) {
                        Task { await clearFailed() }
                    } label: {
                        Label("Vider les échecs", systemImage: "trash")
                    }
                }

                if stats.skipped > 0 {
                    Button {
                        Task { await retrySkipped() }
                    } label: {
                        Label("Réessayer les ignorées (\(stats.skipped))", systemImage: "arrow.clockwise.circle")
                    }
                    .disabled(stats.pausedByUser || selectedRemote.isEmpty)
                }

                Button {
                    Task { await verifyIntegrity() }
                } label: {
                    if let vp = verifyProgress, vp.isRunning {
                        Label("Vérification : \(vp.checked) / \(vp.totalToCheck)", systemImage: "checkmark.shield")
                    } else {
                        Label("Vérifier l'intégrité sur le remote", systemImage: "checkmark.shield")
                    }
                }
                .disabled(selectedRemote.isEmpty || verifyProgress?.isRunning == true)

                if let vp = verifyProgress {
                    VStack(alignment: .leading, spacing: 4) {
                        if vp.totalToCheck > 0 {
                            ProgressView(value: vp.percentage)
                                .tint(.blue)
                                .animation(.spring(duration: 0.35, bounce: 0.15), value: vp.percentage)
                        }
                        HStack(spacing: 12) {
                            Label("\(vp.verified)", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                            Label("\(vp.missing)", systemImage: "questionmark.circle.fill").foregroundStyle(.orange)
                            if vp.mismatch > 0 {
                                Label("\(vp.mismatch)", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
                            }
                            if vp.unsupported > 0 {
                                Label("\(vp.unsupported)", systemImage: "info.circle").foregroundStyle(.secondary)
                            }
                        }
                        .font(.caption.monospacedDigit())
                    }
                    .padding(.vertical, 4)
                    // D7 : a11y unifiée sur le bloc verify
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(
                        "Vérification d'intégrité, \(vp.verified) vérifiés, \(vp.missing) manquants, \(vp.mismatch) hash différents, \(vp.unsupported) non vérifiables sur \(vp.totalToCheck) au total"
                    )
                }
            } header: {
                Text("Contrôles")
            } footer: {
                if stats.pausedByUser {
                    Text("La synchro est en pause. Aucun nouveau transfert ne sera lancé jusqu'à la reprise manuelle.")
                } else if stats.failed > 0 {
                    Text("\(stats.failed) photo(s) en échec. Réessayer remet à zéro le compteur de tentatives.")
                } else if stats.skipped > 0 {
                    Text("\(stats.skipped) photo(s) ignorée(s) : supprimées/déplacées dans Photos, accès partiel, ou originaux illisibles. « Réessayer les ignorées » les recycle — utile après avoir re-accordé « Toutes les photos ».")
                }
            }

            if stats.authorization == .limited || stats.authorization == .denied || stats.authorization == .restricted {
                Section {
                    Label(authorizationTitle, systemImage: authorizationIcon)
                        .foregroundStyle(authorizationTint)
                    Button("Modifier l'accès aux Photos") {
                        openPhotoSettings()
                    }
                } footer: {
                    Text(authorizationFooter)
                }
            }

            Section {
                LabeledContent("Photos visibles", value: "\(stats.visible)")
                LabeledContent("Indexés", value: "\(stats.indexed)")
                LabeledContent("En attente", value: "\(stats.pending)")
                LabeledContent("En cours/en file", value: "\(stats.active)")
                LabeledContent("Terminés", value: "\(stats.completed)")
                LabeledContent("Échecs", value: "\(stats.failed)")
                if stats.skipped > 0 {
                    LabeledContent("Ignorées", value: "\(stats.skipped)")
                }
            } header: {
                Text("État")
            }

            if !recentAssets.isEmpty {
                Section {
                    ForEach(recentAssets) { asset in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(asset.mediaType.capitalized)
                                    .font(.body.weight(.medium))
                                Spacer()
                                AppStatusBadge(title: statusLabel(asset.status), tint: statusColor(asset.status))
                            }
                            Text(asset.localIdentifier)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            if let error = asset.lastError, asset.status == .failed {
                                Text(error)
                                    .font(.caption2)
                                    .foregroundStyle(.red)
                                    .lineLimit(2)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Historique récent")
                }
            }
        }
        .navigationTitle("Synchro Photos")
        #if os(iOS)
        .rgInlineNavTitle()
        #endif
        .task {
            await load()
            await reloadStats()
            #if os(iOS) || os(macOS)
            selectedAlbumCount = PhotoSyncAlbumStore.load().count
            activeFilterCount = PhotoSyncService.shared.filters.activeCount
            suspensionReason = PhotoSyncService.shared.suspensionReason
            #endif
            // Live refresh while the view is on screen. Cadence adaptative :
            // 1 s pendant un batch rclone copy actif (pour voir la barre
            // avancer en temps réel), 4 s sinon (économie batterie quand
            // rien ne bouge). SwiftUI cancels la .task à disappear donc
            // pas de timer manuel à libérer.
            while !Task.isCancelled {
                let interval: Duration
                if PhotoSyncService.shared.liveBatchProgress != nil
                    || PhotoSyncService.shared.verifyProgress?.isRunning == true {
                    interval = .seconds(1)
                } else {
                    interval = .seconds(4)
                }
                try? await Task.sleep(for: interval)
                await reloadStats()
                verifyProgress = PhotoSyncService.shared.verifyProgress
                #if os(iOS) || os(macOS)
                suspensionReason = PhotoSyncService.shared.suspensionReason
                #endif
            }
        }
        .onAppear {
            // Refresh count when returning from the album picker.
            // Reste séparé du .task pour capter le retour depuis NavigationLink
            // (l'album picker pop ne re-déclenche pas le .task).
            #if os(iOS) || os(macOS)
            selectedAlbumCount = PhotoSyncAlbumStore.load().count
            activeFilterCount = PhotoSyncService.shared.filters.activeCount
            #endif
        }
    }

    private func load() async {
        let service = PhotoSyncService.shared
        enabled = service.isEnabled
        selectedRemote = service.configuredRemote ?? ""
        folder = service.configuredFolder
        requiresPower = service.requiresExternalPower
        allowsCellular = service.allowsCellular
        let loadedRemotes = (try? await RemoteService.shared.listRemoteNames()) ?? []
        if !selectedRemote.isEmpty && !loadedRemotes.contains(selectedRemote) {
            remotes = [selectedRemote] + loadedRemotes
        } else {
            remotes = loadedRemotes
        }
    }

    private func save() {
        PhotoSyncService.shared.configure(
            enabled: enabled,
            remote: selectedRemote.isEmpty ? nil : selectedRemote,
            folder: folder,
            requiresPower: requiresPower,
            allowsCellular: allowsCellular
        )
        message = "Configuration enregistrée."
    }

    private func syncNow() async {
        isSyncing = true
        defer { isSyncing = false }
        let summary = await PhotoSyncService.shared.startFullSync()
        applySummary(summary)
        reloadRecentAssets()
        if summary.isLimitedAccess {
            message = "Synchro lancée pour les \(summary.visibleAssetCount) photos autorisées. L'accès Photos est limité."
        } else {
            message = "Synchro complète lancée. \(summary.enqueuedCount) ajoutés à la file, \(summary.pendingCount) en attente."
        }
    }

    private func reloadStats() async {
        let summary = await PhotoSyncService.shared.currentSummary()
        applySummary(summary)
        reloadRecentAssets()
    }

    private func applySummary(_ summary: PhotoSyncRunSummary) {
        // Note : on copie les compteurs ratchet-adjusted depuis le summary
        // (countsPending/countsCompleted/indexedCount sont déjà passés à
        // travers le ratchet côté `statusSnapshot`), donc l'affichage
        // X/Y reste monotone.
        stats = PhotoSyncStats(
            authorization: summary.authorization,
            visible: summary.visibleAssetCount,
            indexed: summary.indexedCount,
            pending: summary.pendingCount,
            active: summary.activeCount,
            completed: summary.completedCount,
            failed: summary.failedCount,
            skipped: summary.skippedCount,
            totalBytes: summary.totalBytes,
            transferredBytes: summary.transferredBytes,
            averageBytesPerSecond: summary.averageBytesPerSecond,
            estimatedTimeRemaining: summary.estimatedTimeRemaining,
            pausedByUser: summary.pausedByUser
        )
    }

    private func togglePause() async {
        if stats.pausedByUser {
            await PhotoSyncService.shared.resumePhotoSync()
        } else {
            await PhotoSyncService.shared.pausePhotoSync()
        }
        await reloadStats()
    }

    private func retryFailed() async {
        let recycled = await PhotoSyncService.shared.retryFailedAssets()
        if recycled > 0 {
            message = "\(recycled) photo(s) remise(s) en file."
        }
        await reloadStats()
    }

    private func retrySkipped() async {
        let recycled = await PhotoSyncService.shared.retrySkippedAssets()
        if recycled > 0 {
            message = "\(recycled) photo(s) ignorée(s) remise(s) en file."
        }
        await reloadStats()
    }

    private func clearFailed() async {
        let removed = PhotoSyncService.shared.clearFailedAssets()
        if removed > 0 {
            message = "\(removed) échec(s) supprimé(s) de l'historique."
        }
        await reloadStats()
    }

    /// Bouton « Vérifier l'intégrité sur le remote » : re-stat tous les
    /// assets déjà completed/skipped et reset en .pending ceux qui sont
    /// manquants côté serveur. Les ré-uploads partent automatiquement
    /// au prochain cycle du pipeline.
    private func verifyIntegrity() async {
        await PhotoSyncService.shared.verifyAllUploadedAssets()
        // Sync final du progress (la closure ci-dessous le tient à jour)
        verifyProgress = PhotoSyncService.shared.verifyProgress
        if let vp = verifyProgress, !vp.isRunning {
            var parts: [String] = []
            if vp.verified > 0 { parts.append("\(vp.verified) OK") }
            if vp.missing > 0 { parts.append("\(vp.missing) manquantes (re-upload programmé)") }
            if vp.mismatch > 0 { parts.append("\(vp.mismatch) hash différents") }
            if vp.unsupported > 0 { parts.append("\(vp.unsupported) non vérifiables") }
            message = "Vérification : " + parts.joined(separator: " · ")
            await reloadStats()
        }
    }

    private func formatBytes(_ bytes: Int64) -> String { PhotoSyncFormat.bytes(bytes) }
    private func formatThroughput(_ bps: Double) -> String { PhotoSyncFormat.throughput(bps) }
    private func formatETA(_ seconds: TimeInterval) -> String { PhotoSyncFormat.eta(seconds) }

    /// Total unifié X/Y : `effectiveTotal` du summary, qui inclut les
    /// failed pour rester aligné avec la bannière Transferts (les
    /// échecs comptent dans le dénominateur — sinon la barre saute
    /// quand on bascule entre les deux écrans).
    private var totalItemCount: Int {
        stats.effectiveTotal
    }

    private var shouldShowProgressBar: Bool {
        totalItemCount > 0 && (isSyncing || stats.active > 0 || stats.pending > 0)
    }

    private var itemProgressRatio: Double {
        stats.displayProgress
    }

    @ViewBuilder
    private var progressBar: some View {
        let total = totalItemCount
        let ratio = itemProgressRatio
        let percent = Int((ratio * 100).rounded())
        VStack(alignment: .leading, spacing: 6) {
            ProgressView(value: ratio)
                .progressViewStyle(.linear)
                .tint(stats.pausedByUser ? .gray : RG.photoSync.accent)
                .animation(.spring(duration: 0.4, bounce: 0.15), value: ratio)
            HStack {
                Text(String(localized: "\(stats.completed) / \(total) photos et vidéos"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(percent)%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if stats.totalBytes > 0 {
                HStack(spacing: 6) {
                    if stats.pausedByUser {
                        Label("En pause", systemImage: "pause.fill")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.orange)
                    } else if stats.averageBytesPerSecond > 1 {
                        Label(formatThroughput(stats.averageBytesPerSecond), systemImage: "speedometer")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let eta = stats.estimatedTimeRemaining, !stats.pausedByUser, eta > 0 {
                        Label("≈ \(formatETA(eta))", systemImage: "hourglass")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                Text("\(formatBytes(stats.transferredBytes)) / \(formatBytes(stats.totalBytes))")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Progression : \(stats.completed) sur \(total) photos et vidéos, \(percent) pour cent")
    }

private func reloadRecentAssets() {
        var descriptor = FetchDescriptor<PhotoSyncAsset>(
            sortBy: [SortDescriptor(\.discoveredAt, order: .reverse)]
        )
        descriptor.fetchLimit = 20
        recentAssets = (try? modelContext.fetch(descriptor)) ?? []
    }

    private var authorizationTitle: String {
        switch stats.authorization {
        case .limited:
            return String(localized: "Accès Photos limité")
        case .denied, .restricted:
            return String(localized: "Accès Photos indisponible")
        case .authorized, .notDetermined, .unknown:
            return String(localized: "Accès Photos")
        }
    }

    private var authorizationFooter: String {
        switch stats.authorization {
        case .limited:
            return String(localized: "iOS ne donne accès qu’à la sélection actuelle. Les autres photos ne peuvent pas être indexées ni synchronisées.")
        case .denied, .restricted:
            return String(localized: "Autorise l’accès Photos dans Réglages pour synchroniser la photothèque.")
        case .authorized, .notDetermined, .unknown:
            return ""
        }
    }

    private var authorizationIcon: String {
        stats.authorization == .limited ? "photo.badge.exclamationmark" : "lock.slash"
    }

    private var authorizationTint: Color {
        stats.authorization == .limited ? .orange : .red
    }

    private func openPhotoSettings() {
        #if os(iOS)
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
        #elseif os(macOS)
        // Ouvre directement le volet Confidentialité → Photos des Réglages Système.
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Photos") else { return }
        NSWorkspace.shared.open(url)
        #endif
    }

    private func statusLabel(_ status: PhotoSyncStatus) -> String {
        switch status {
        case .pending: return String(localized: "Attente")
        case .exporting: return String(localized: "Export")
        case .enqueued: return String(localized: "En file")
        case .completed: return String(localized: "Terminé")
        case .failed: return String(localized: "Échec")
        case .skipped: return String(localized: "Ignoré")
        }
    }

    private func statusColor(_ status: PhotoSyncStatus) -> Color {
        switch status {
        case .pending: return .gray
        case .exporting: return .orange
        case .enqueued: return .blue
        case .completed: return .green
        case .failed: return .red
        case .skipped: return .gray
        }
    }
}

private struct PhotoSyncStats {
    var authorization = PhotoSyncAuthorizationState.notDetermined
    var visible = 0
    var indexed = 0
    var pending = 0
    var active = 0
    var completed = 0
    var failed = 0
    var skipped = 0
    var totalBytes: Int64 = 0
    var transferredBytes: Int64 = 0
    var averageBytesPerSecond: Double = 0
    var estimatedTimeRemaining: TimeInterval?
    var pausedByUser = false

    /// Effective total used for the X/Y display. Mirrors
    /// `PhotoSyncRunSummary.effectiveTotal` so both screens agree on
    /// the denominator (includes failed, ratchet-aware).
    var effectiveTotal: Int {
        max(completed + active + pending + failed + skipped, indexed)
    }

    /// Monotonic 0..1 ratio sourced from the service-side ratchet.
    var displayProgress: Double {
        guard effectiveTotal > 0 else { return 0 }
        return min(1.0, Double(completed) / Double(effectiveTotal))
    }
}
