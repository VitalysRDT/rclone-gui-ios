//
//  PhotoSyncService.swift
//  Rclone GUI — Services
//
//  Opportunistic Photo Library backup. iOS decides when background work
//  actually runs, so this service is designed around idempotent scans and
//  resumable enqueueing rather than a permanent daemon.
//

import BackgroundTasks
import CryptoKit
import Foundation
import Photos
import SwiftData
import UIKit

public enum PhotoSyncAuthorizationState: String, Sendable, Equatable {
    case authorized
    case limited
    case denied
    case restricted
    case notDetermined
    case unknown

    public var isUsable: Bool {
        self == .authorized || self == .limited
    }
}

public struct PhotoSyncFilters: Codable, Sendable, Equatable {
    public var includePhotos: Bool
    public var includeVideos: Bool
    public var includeLivePhotos: Bool
    public var includeScreenshots: Bool
    public var includeSlowMo: Bool
    public var includePanoramas: Bool
    public var dateRangeStart: Date?
    public var dateRangeEnd: Date?
    /// `nil` ou ≤ 0 = pas de limite. Sert à exclure les vidéos plus longues
    /// que ce seuil — proxy pratique pour la taille (les vidéos longues sont
    /// les seuls fichiers vraiment lourds en pratique).
    public var maxVideoDurationSeconds: Double?

    public init(
        includePhotos: Bool = true,
        includeVideos: Bool = true,
        includeLivePhotos: Bool = true,
        includeScreenshots: Bool = true,
        includeSlowMo: Bool = true,
        includePanoramas: Bool = true,
        dateRangeStart: Date? = nil,
        dateRangeEnd: Date? = nil,
        maxVideoDurationSeconds: Double? = nil
    ) {
        self.includePhotos = includePhotos
        self.includeVideos = includeVideos
        self.includeLivePhotos = includeLivePhotos
        self.includeScreenshots = includeScreenshots
        self.includeSlowMo = includeSlowMo
        self.includePanoramas = includePanoramas
        self.dateRangeStart = dateRangeStart
        self.dateRangeEnd = dateRangeEnd
        self.maxVideoDurationSeconds = maxVideoDurationSeconds
    }

    public static let allEnabled = PhotoSyncFilters()

    public var isDefault: Bool {
        self == .allEnabled
    }

    /// Compteur de filtres actifs (i.e. différents du défaut). Sert juste au
    /// libellé "Filtres (3)" dans le NavigationLink.
    public var activeCount: Int {
        var n = 0
        if !includePhotos { n += 1 }
        if !includeVideos { n += 1 }
        if !includeLivePhotos { n += 1 }
        if !includeScreenshots { n += 1 }
        if !includeSlowMo { n += 1 }
        if !includePanoramas { n += 1 }
        if dateRangeStart != nil || dateRangeEnd != nil { n += 1 }
        if let max = maxVideoDurationSeconds, max > 0 { n += 1 }
        return n
    }
}

public struct PhotoSyncRunSummary: Sendable, Equatable {
    public let authorization: PhotoSyncAuthorizationState
    public let visibleAssetCount: Int
    public let indexedCount: Int
    public let newlyIndexedCount: Int
    public let enqueuedCount: Int
    public let pendingCount: Int
    public let activeCount: Int
    public let completedCount: Int
    public let failedCount: Int
    public let totalBytes: Int64
    public let transferredBytes: Int64
    public let averageBytesPerSecond: Double
    public let estimatedTimeRemaining: TimeInterval?
    public let pausedByUser: Bool

    public var isLimitedAccess: Bool {
        authorization == .limited
    }

    public var byteProgress: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1.0, Double(transferredBytes) / Double(totalBytes))
    }
}

struct PhotoSyncLimits: Sendable, Equatable {
    var indexSaveBatchSize = 250
    /// How many records we enqueue per `runSync` pass. Réduit de 25 → 10
    /// pour borner la durée d'un cycle MainActor à ~700ms-1.5s max (vs
    /// 1.75-3.75s avant) : SwiftUI peut rendre les tabs entre deux batches.
    /// Throughput global préservé via `scheduleContinuationIfNeeded` qui
    /// chaîne les batches dès qu'un slot se libère côté maxActiveUploads.
    var enqueueBatchSize = 10
    /// How many TransferQueue jobs we want active in parallel for photo sync.
    /// rclone-bridge handles concurrent jobs fine; the cap exists mostly so
    /// the user's manual transfers don't get crowded out.
    var maxActiveUploads = 5
    var maxRetries = 3

    static let standard = PhotoSyncLimits()
}

struct PhotoSyncCandidate: Sendable, Equatable {
    let localIdentifier: String
    let mediaType: String
    let creationDate: Date?
}

private struct PhotoSyncIndexResult: Sendable {
    let visibleAssetCount: Int
    let newlyIndexedCount: Int
}

private struct PhotoSyncCounts {
    let indexed: Int
    let pending: Int
    let active: Int
    let completed: Int
    let failed: Int
    let totalBytes: Int64
    let transferredBytes: Int64
}

private struct PhotoSyncScanResult: Sendable {
    let visibleAssetCount: Int
    let candidates: [PhotoSyncCandidate]
}

@MainActor
public final class PhotoSyncService: NSObject, PHPhotoLibraryChangeObserver {
    public static let shared = PhotoSyncService()

    public nonisolated static let processingIdentifier = "com.rougetet.rclone-gui.photo-sync"

    private let limits = PhotoSyncLimits.standard
    private var modelContext: ModelContext?
    private var observerRegistered = false
    private var isSyncing = false
    private var observerSyncTask: Task<Void, Never>?
    private var continuationTask: Task<Void, Never>?
    /// Rolling sample of (timestamp, transferredBytes) used to compute the
    /// instantaneous throughput and ETA shown in the hero card. Capped to the
    /// last 30 s by pruning on each insert so it stays O(n) in time, not in
    /// session length. Lives in-memory only — restarted from zero on cold launch.
    private var throughputSamples: [(date: Date, bytes: Int64)] = []
    private let throughputWindow: TimeInterval = 30
    /// Periodic safety net that re-kicks the continuation if it ever stalls
    /// (e.g. transferDidFinish failed to match a remotePath because of a
    /// path-normalisation drift, or the queue dropped a callback). Set up
    /// once per attach() and torn down implicitly on app termination.
    private var heartbeatTask: Task<Void, Never>?

    private override init() {
        super.init()
    }

    // MARK: - Setup

    public func attach(modelContext: ModelContext) {
        guard self.modelContext !== modelContext else { return }
        self.modelContext = modelContext
        Task { await registerPhotoObserverIfNeeded() }
        startHeartbeatIfNeeded()
    }

    /// Start the recovery heartbeat. The loop wakes every 15s; if there are
    /// pending records, it reconciles orphans and relaunches the chain. This
    /// is the safety net for the case where `transferDidFinish` fails to match
    /// a record (path drift, queue glitch, app cold-start dropping poll tasks),
    /// which would otherwise leave the pipeline silently stuck — the exact
    /// symptom of "ça ne rajoute pas ceux en attente si je ne vais pas dans
    /// réglage".
    private func startHeartbeatIfNeeded() {
        guard heartbeatTask == nil else { return }
        heartbeatTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                guard let self else { return }
                await self.heartbeatTick()
            }
        }
    }

    private func heartbeatTick() async {
        guard isEnabled, configuredRemote != nil else { return }
        guard !isSyncing else { return }

        // First, recycle any asset whose Transfer counterpart is terminal or
        // missing — these would otherwise inflate `active` and block the
        // pipeline forever (the previous design's silent failure mode).
        let recycled = reconcileOrphanedAssets()
        if recycled > 0 {
            await LogService.shared.log(
                .info,
                category: "photos",
                message: "Heartbeat : \(recycled) asset(s) orphelin(s) repris."
            )
        }

        let pending = (try? pendingWorkCount(includeFailedRetries: true)) ?? 0
        // We deliberately don't gate on active==0. Even with N records still
        // genuinely active, if there's pending work and we're under the active
        // ceiling, we should be enqueuing more — the runSync internal cap does
        // the right thing. The previous gate was the bug that made the user
        // see "ne rajoute pas ceux en attente".
        guard pending > 0 else { return }

        await LogService.shared.log(
            .info,
            category: "photos",
            message: "Heartbeat photo sync : \(pending) en attente, relance auto."
        )
        shouldContinueUntilEmpty = true
        _ = await runSync(
            requestedLimit: limits.enqueueBatchSize,
            continueUntilEmpty: true,
            includeFailedRetries: true
        )
    }

    /// Resume an interrupted full sync if one was in flight when the app
    /// last quit. Reads the persisted `shouldContinueUntilEmpty` flag and the
    /// pending count from SwiftData; if there's still work to do, kick off a
    /// background `startFullSync()` so the user doesn't have to revisit
    /// Settings to tap "Synchroniser" every time.
    ///
    /// Idempotent and cheap: returns immediately when sync is disabled, no
    /// remote is configured, or no pending records remain.
    public func resumeIfNeeded() async {
        guard isEnabled, configuredRemote != nil else { return }
        // Critical: reconcile before counting. Records that were `.enqueued`
        // when the app quit are orphaned at launch — TransferQueue.pollLoop
        // doesn't survive a relaunch, so transferDidFinish was never called.
        // Without this remap, the orphan records would inflate `active` count
        // and prevent the heartbeat from re-kicking the pipeline forever.
        let recovered = reconcileOrphanedAssets()
        if recovered > 0 {
            await LogService.shared.log(
                .info,
                category: "photos",
                message: "Reconciliation au lancement : \(recovered) asset(s) orphelin(s) remis en file."
            )
        }
        let pending = (try? pendingWorkCount(includeFailedRetries: true)) ?? 0
        guard shouldContinueUntilEmpty || pending > 0 else { return }
        await LogService.shared.log(
            .info,
            category: "photos",
            message: "Reprise auto de la synchro photos au lancement (pending=\(pending))."
        )
        _ = await startFullSync()
    }

    /// Walk every `PhotoSyncAsset` whose status is `.enqueued` or `.exporting`
    /// and reconcile it with the matching `Transfer` record:
    ///
    ///  - Transfer is `.completed` → mark the asset `.completed` (the missed
    ///    callback we never got to deliver)
    ///  - Transfer is `.failed` → mark `.failed` + bump retryCount
    ///  - No Transfer found, or it's older than `staleAfter` and not `.running`
    ///    → reset asset to `.pending` so the next runSync picks it up
    ///  - Transfer is genuinely still `.running` with a recent attempt → leave it
    ///
    /// Returns the number of records that were moved back to `.pending`. The
    /// caller uses this as a signal that the pipeline can resume.
    @discardableResult
    private func reconcileOrphanedAssets() -> Int {
        guard let modelContext else { return 0 }

        // Anything still claiming to be active. We keep the fetchLimit high
        // because at relaunch every previously-active asset shows up here,
        // not just maxActiveUploads worth.
        let activeDescriptor = FetchDescriptor<PhotoSyncAsset>(
            predicate: #Predicate { $0.statusRaw == "enqueued" || $0.statusRaw == "exporting" }
        )
        guard let activeAssets = try? modelContext.fetch(activeDescriptor),
              !activeAssets.isEmpty else { return 0 }

        // Pull only photoLibrary Transfers in matching statuses; we filter
        // in memory because SwiftData #Predicate can't express
        // "destinationPath in [String]". On exclut .pending et .paused qui
        // ne matchent jamais le destinationPath d'un asset enqueued/exporting,
        // et on cape à 5000 pour éviter les scans pathologiques après des
        // semaines d'usage. Sort par startedAt desc pour que les plus récents
        // gagnent la collision sur destinationPath en cas de retry.
        var transferDescriptor = FetchDescriptor<Transfer>(
            predicate: #Predicate {
                $0.sourceKindRaw == "photoLibrary"
                && ($0.statusRaw == "running"
                    || $0.statusRaw == "completed"
                    || $0.statusRaw == "failed")
            },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        transferDescriptor.fetchLimit = 5000
        let allTransfers = (try? modelContext.fetch(transferDescriptor)) ?? []
        // Premier wins (sort desc → le plus récent), pas le dernier.
        let transfersByPath: [String: Transfer] = Dictionary(
            allTransfers.map { ($0.destinationPath, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        let staleAfter: TimeInterval = 3 * 60  // 3 minutes
        let now = Date()
        var resetCount = 0

        for asset in activeAssets {
            // No remote paths recorded yet (asset was claimed by enqueuePending
            // but the upload call threw before append) → safe to reset.
            guard !asset.remotePaths.isEmpty else {
                asset.status = .pending
                resetCount += 1
                continue
            }

            // For multi-resource assets (paired video + photo), all transfers
            // must be terminal for us to call the asset finished.
            let transfers = asset.remotePaths.compactMap { transfersByPath[$0] }

            // No matching Transfer found at all (purged, never enqueued) → recycle.
            if transfers.count != asset.remotePaths.count {
                asset.status = .pending
                asset.lastError = "Transfer correspondant introuvable, remis en file."
                resetCount += 1
                continue
            }

            let allCompleted = transfers.allSatisfy { $0.status == .completed }
            let anyFailed = transfers.contains { $0.status == .failed }
            let allTerminal = transfers.allSatisfy { $0.status == .completed || $0.status == .failed }
            let staleAttempt = (now.timeIntervalSince(asset.lastAttemptAt ?? .distantPast)) > staleAfter

            if allCompleted {
                asset.status = .completed
                asset.completedAt = .now
                asset.lastError = nil
            } else if anyFailed && allTerminal {
                asset.status = .failed
                asset.retryCount += 1
                asset.lastError = transfers.first { $0.status == .failed }?.lastError
                    ?? "Upload PhotoSync échoué"
            } else if staleAttempt {
                // Some transfers still .running but the last attempt is old —
                // most likely an orphan (poll task dropped at app relaunch).
                // Reset to .pending so the next pass re-enqueues fresh.
                asset.status = .pending
                asset.lastError = "Pipeline interrompu, repris automatiquement."
                resetCount += 1
            }
        }
        try? modelContext.save()
        return resetCount
    }

    public nonisolated func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.processingIdentifier,
            using: nil
        ) { task in
            guard let task = task as? BGProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor in
                await PhotoSyncService.shared.handleProcessingTask(task)
            }
        }
    }

    public func scheduleBackgroundProcessing() {
        guard isEnabled, configuredRemote != nil else { return }
        let request = BGProcessingTaskRequest(identifier: Self.processingIdentifier)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = requiresExternalPower
        request.earliestBeginDate = Date(timeIntervalSinceNow: 20 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    // MARK: - Settings

    public var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "photoSync.enabled") }
        set {
            UserDefaults.standard.set(newValue, forKey: "photoSync.enabled")
            if newValue {
                Task { await registerPhotoObserverIfNeeded() }
                scheduleBackgroundProcessing()
            }
        }
    }

    public var configuredRemote: String? {
        let value = UserDefaults.standard.string(forKey: "photoSync.remote") ?? ""
        return value.isEmpty ? nil : value
    }

    public var configuredFolder: String {
        UserDefaults.standard.string(forKey: "photoSync.folder") ?? "Phototheque"
    }

    public var requiresExternalPower: Bool {
        get {
            if UserDefaults.standard.object(forKey: "photoSync.requiresExternalPower") == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: "photoSync.requiresExternalPower")
        }
        set { UserDefaults.standard.set(newValue, forKey: "photoSync.requiresExternalPower") }
    }

    public var allowsCellular: Bool {
        get { UserDefaults.standard.bool(forKey: "photoSync.allowsCellular") }
        set { UserDefaults.standard.set(newValue, forKey: "photoSync.allowsCellular") }
    }

    private var shouldContinueUntilEmpty: Bool {
        get { UserDefaults.standard.bool(forKey: "photoSync.continueUntilEmpty") }
        set { UserDefaults.standard.set(newValue, forKey: "photoSync.continueUntilEmpty") }
    }

    /// Active media filters. Stored as JSON in `UserDefaults` so the scan
    /// task (nonisolated static) can load them without taking a MainActor hop.
    /// Modifying invalidates the next scan only — already-indexed assets keep
    /// their current status.
    public var filters: PhotoSyncFilters {
        get {
            guard let data = UserDefaults.standard.data(forKey: "photoSync.filters.v1"),
                  let decoded = try? JSONDecoder().decode(PhotoSyncFilters.self, from: data) else {
                return .allEnabled
            }
            return decoded
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: "photoSync.filters.v1")
            }
        }
    }

    nonisolated public static func loadFilters() -> PhotoSyncFilters {
        guard let data = UserDefaults.standard.data(forKey: "photoSync.filters.v1"),
              let decoded = try? JSONDecoder().decode(PhotoSyncFilters.self, from: data) else {
            return .allEnabled
        }
        return decoded
    }

    /// Persisted user-initiated pause. Distinct from the policy suspension
    /// (battery/network) so the pipeline doesn't auto-resume when the device
    /// is plugged in — only an explicit "Reprendre" tap lifts this.
    public var isPausedByUser: Bool {
        get { UserDefaults.standard.bool(forKey: "photoSync.pausedByUser") }
        set { UserDefaults.standard.set(newValue, forKey: "photoSync.pausedByUser") }
    }

    /// User-facing pause. Stops new work from being enqueued and halts any
    /// in-flight TransferQueue jobs. Idempotent.
    public func pausePhotoSync() async {
        isPausedByUser = true
        continuationTask?.cancel()
        continuationTask = nil
        do {
            try await TransferQueue.shared.pauseAllTransfers()
        } catch {
            await LogService.shared.log(.error, category: "photos", message: "Pause TransferQueue impossible : \(error.localizedDescription)")
        }
        await LogService.shared.log(.info, category: "photos", message: "Synchro photos en pause (utilisateur).")
    }

    /// Lift the user pause. Restores TransferQueue bandwidth from the user
    /// preference and re-kicks the pipeline if there's still work to do.
    public func resumePhotoSync() async {
        guard isPausedByUser else { return }
        isPausedByUser = false
        let mbps = UserDefaults.standard.double(forKey: "transfer.bandwidthLimitMBps")
        let bytesPerSecond = Int64(max(0, mbps) * 1024 * 1024)
        do {
            try await TransferQueue.shared.resumeAllTransfers(bytesPerSecond: bytesPerSecond)
        } catch {
            await LogService.shared.log(.error, category: "photos", message: "Reprise TransferQueue impossible : \(error.localizedDescription)")
        }
        await LogService.shared.log(.info, category: "photos", message: "Synchro photos reprise.")
        if isEnabled, configuredRemote != nil {
            shouldContinueUntilEmpty = true
            scheduleContinuationIfNeeded()
        }
    }

    /// Move every `.failed` asset back to `.pending` and reset attempt counters,
    /// then kick a full sync so they get re-tried right away. Returns the
    /// number of assets recycled.
    @discardableResult
    public func retryFailedAssets() async -> Int {
        guard let modelContext else { return 0 }
        let descriptor = FetchDescriptor<PhotoSyncAsset>(
            predicate: #Predicate { $0.statusRaw == "failed" }
        )
        let failed = (try? modelContext.fetch(descriptor)) ?? []
        guard !failed.isEmpty else { return 0 }
        for asset in failed {
            asset.status = .pending
            asset.retryCount = 0
            asset.lastError = nil
        }
        try? modelContext.save()
        await LogService.shared.log(.info, category: "photos", message: "Reprise de \(failed.count) asset(s) en échec.")
        if isEnabled, configuredRemote != nil, !isPausedByUser {
            shouldContinueUntilEmpty = true
            _ = await runSync(
                requestedLimit: limits.enqueueBatchSize,
                continueUntilEmpty: true,
                includeFailedRetries: true
            )
        }
        return failed.count
    }

    /// Permanently drop every `.failed` asset row so the historique stops
    /// reporting them. Does NOT re-enqueue them — use `retryFailedAssets` for
    /// that. Returns the number of rows deleted.
    @discardableResult
    public func clearFailedAssets() -> Int {
        guard let modelContext else { return 0 }
        let descriptor = FetchDescriptor<PhotoSyncAsset>(
            predicate: #Predicate { $0.statusRaw == "failed" }
        )
        let failed = (try? modelContext.fetch(descriptor)) ?? []
        for asset in failed {
            modelContext.delete(asset)
        }
        try? modelContext.save()
        return failed.count
    }

    public func configure(enabled: Bool, remote: String?, folder: String, requiresPower: Bool, allowsCellular: Bool) {
        UserDefaults.standard.set(enabled, forKey: "photoSync.enabled")
        UserDefaults.standard.set(remote ?? "", forKey: "photoSync.remote")
        UserDefaults.standard.set(folder.isEmpty ? "Phototheque" : folder, forKey: "photoSync.folder")
        self.requiresExternalPower = requiresPower
        self.allowsCellular = allowsCellular
        if !enabled {
            shouldContinueUntilEmpty = false
            continuationTask?.cancel()
            continuationTask = nil
        }
        if enabled {
            Task { await registerPhotoObserverIfNeeded() }
            scheduleBackgroundProcessing()
        }
    }

    // MARK: - Sync

    @discardableResult
    public func syncNow(limit: Int = 10) async -> PhotoSyncRunSummary {
        let summary = await runSync(requestedLimit: limit, continueUntilEmpty: false, includeFailedRetries: true)
        #if os(iOS)
        await postSyncCompleteNotification(uploaded: summary.completedCount, failed: summary.failedCount)
        #endif
        return summary
    }

    @discardableResult
    public func startFullSync() async -> PhotoSyncRunSummary {
        shouldContinueUntilEmpty = true
        let summary = await runSync(
            requestedLimit: limits.enqueueBatchSize,
            continueUntilEmpty: true,
            includeFailedRetries: true
        )
        #if os(iOS)
        await postSyncCompleteNotification(uploaded: summary.completedCount, failed: summary.failedCount)
        #endif
        return summary
    }

    public func currentSummary() async -> PhotoSyncRunSummary {
        await statusSnapshot()
    }

    private func runSync(
        requestedLimit: Int,
        continueUntilEmpty: Bool,
        includeFailedRetries: Bool
    ) async -> PhotoSyncRunSummary {
        guard !isSyncing else { return await statusSnapshot() }
        guard isEnabled, let remote = configuredRemote else { return await statusSnapshot() }
        guard !isPausedByUser else {
            await LogService.shared.log(.info, category: "photos", message: "Synchro photos ignorée : mise en pause par l'utilisateur.")
            return await statusSnapshot()
        }
        guard canStartNewWork else {
            await LogService.shared.log(.info, category: "photos", message: "Synchro photos suspendue par la politique energie/reseau.")
            scheduleBackgroundProcessing()
            return await statusSnapshot()
        }

        isSyncing = true
        defer {
            isSyncing = false
            scheduleBackgroundProcessing()
        }

        do {
            let authorizationStatus = try await ensurePhotoAuthorization()
            let indexResult = try await indexLibrary()
            let enqueuedCount = try await enqueuePending(
                remote: remote,
                folder: configuredFolder,
                requestedLimit: requestedLimit,
                includeFailedRetries: includeFailedRetries
            )
            let summary = await statusSnapshot(
                authorizationStatus: authorizationStatus,
                visibleAssetCount: indexResult.visibleAssetCount,
                newlyIndexedCount: indexResult.newlyIndexedCount,
                enqueuedCount: enqueuedCount
            )
            if continueUntilEmpty {
                finishFullSyncIfDrained(summary)
                scheduleContinuationIfNeeded()
            }
            return summary
        } catch is CancellationError {
            // Annulation coopérative (ex : photoLibraryDidChange redémarre la sync,
            // app passe en arrière-plan). Pas une vraie erreur — silence l'entrée
            // rouge dans les Logs et laisse la prochaine passe reprendre.
            return await statusSnapshot()
        } catch {
            await LogService.shared.log(.error, category: "photos", message: "Synchro photos impossible : \(error.localizedDescription)")
            return await statusSnapshot()
        }
    }

    private func handleProcessingTask(_ task: BGProcessingTask) async {
        var expired = false
        task.expirationHandler = {
            expired = true
        }
        if shouldContinueUntilEmpty {
            _ = await runSync(
                requestedLimit: limits.enqueueBatchSize,
                continueUntilEmpty: true,
                includeFailedRetries: false
            )
        } else {
            await syncNow(limit: limits.enqueueBatchSize)
        }
        task.setTaskCompleted(success: !expired)
    }

    private func ensurePhotoAuthorization() async throws -> PHAuthorizationStatus {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        switch status {
        case .authorized, .limited:
            return status
        case .notDetermined:
            let newStatus = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            if newStatus == .authorized || newStatus == .limited { return newStatus }
            throw PhotoSyncError.authorizationDenied
        default:
            throw PhotoSyncError.authorizationDenied
        }
    }

    private func registerPhotoObserverIfNeeded() async {
        guard isEnabled, !observerRegistered else { return }
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else { return }
        PHPhotoLibrary.shared().register(self)
        observerRegistered = true
    }

    /// Quand `false`, l'observation Photos reste active (pour qu'on puisse
    /// quand même afficher des compteurs à jour) mais n'auto-déclenche pas
    /// `startFullSync`. Le user lance lui-même via le bouton ou la prochaine
    /// fenêtre BG.
    public var autoSyncOnImport: Bool {
        get {
            if UserDefaults.standard.object(forKey: "photoSync.autoSyncOnImport") == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: "photoSync.autoSyncOnImport")
        }
        set { UserDefaults.standard.set(newValue, forKey: "photoSync.autoSyncOnImport") }
    }

    nonisolated public func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor in
            guard PhotoSyncService.shared.isEnabled else { return }
            guard PhotoSyncService.shared.autoSyncOnImport else { return }
            guard !PhotoSyncService.shared.isPausedByUser else { return }
            PhotoSyncService.shared.observerSyncTask?.cancel()
            PhotoSyncService.shared.observerSyncTask = Task { @MainActor in
                // Debounce so a Photos burst (10 photos imported at once)
                // doesn't kick off 10 separate full syncs racing each other.
                try? await Task.sleep(for: .seconds(3))
                // Use startFullSync() — not syncNow(limit:N) — so newly added
                // photos drain to the end without the user reopening Settings.
                // syncNow stops after one batch; startFullSync sets the
                // continueUntilEmpty flag and chains automatically.
                await PhotoSyncService.shared.startFullSync()
            }
        }
    }

    private func indexLibrary() async throws -> PhotoSyncIndexResult {
        guard let modelContext else {
            return PhotoSyncIndexResult(visibleAssetCount: 0, newlyIndexedCount: 0)
        }

        let existingIDs = try await indexedIdentifiers()
        let scan = try await Task.detached(priority: .utility) {
            try Task.checkCancellation()
            return Self.scanPhotoLibrary(excluding: existingIDs)
        }.value
        guard !scan.candidates.isEmpty else {
            return PhotoSyncIndexResult(visibleAssetCount: scan.visibleAssetCount, newlyIndexedCount: 0)
        }

        for batch in Self.batches(scan.candidates, size: limits.indexSaveBatchSize) {
            for candidate in batch {
                let record = PhotoSyncAsset(
                    localIdentifier: candidate.localIdentifier,
                    mediaType: candidate.mediaType,
                    creationDate: candidate.creationDate
                )
                modelContext.insert(record)
            }
            try modelContext.save()
            await Task.yield()
        }
        return PhotoSyncIndexResult(
            visibleAssetCount: scan.visibleAssetCount,
            newlyIndexedCount: scan.candidates.count
        )
    }

    private func indexedIdentifiers() async throws -> Set<String> {
        guard let modelContext else { return [] }
        var ids = Set<String>()
        var offset = 0
        let pageSize = 1_000

        while true {
            var descriptor = FetchDescriptor<PhotoSyncAsset>(
                sortBy: [SortDescriptor(\.localIdentifier, order: .forward)]
            )
            descriptor.fetchLimit = pageSize
            descriptor.fetchOffset = offset
            let records = try modelContext.fetch(descriptor)
            ids.formUnion(records.map(\.localIdentifier))
            guard records.count == pageSize else { break }
            offset += records.count
            await Task.yield()
        }

        return ids
    }

    private func enqueuePending(
        remote: String,
        folder: String,
        requestedLimit: Int,
        includeFailedRetries: Bool
    ) async throws -> Int {
        guard let modelContext else { return 0 }
        let activeCount = try activePhotoAssetCount()
        let limit = Self.enqueueCapacity(activeCount: activeCount, requestedLimit: requestedLimit, limits: limits)
        guard limit > 0 else { return 0 }

        var pendingDescriptor = FetchDescriptor<PhotoSyncAsset>(
            predicate: #Predicate { $0.statusRaw == "pending" },
            sortBy: [SortDescriptor(\.creationDate, order: .forward)]
        )
        pendingDescriptor.fetchLimit = limit
        var records = try modelContext.fetch(pendingDescriptor)

        if includeFailedRetries && records.count < limit {
            var failedDescriptor = FetchDescriptor<PhotoSyncAsset>(
                predicate: #Predicate { $0.statusRaw == "failed" },
                sortBy: [SortDescriptor(\.creationDate, order: .forward)]
            )
            failedDescriptor.fetchLimit = 500
            let retryableFailures = try modelContext.fetch(failedDescriptor)
                .filter { $0.retryCount < limits.maxRetries }
                .prefix(limit - records.count)
            records.append(contentsOf: retryableFailures)
        }

        // Privacy guard — apply the album filter to the upload queue, not just
        // the indexer. Without this check, pending records that were indexed
        // before the user narrowed their album selection would still be
        // uploaded, leaking photos outside the chosen scope. See Sprint 4
        // code review issue #1.
        #if os(iOS)
        if let eligibleIDs = Self.eligibleAssetIDs() {
            records = records.filter { eligibleIDs.contains($0.localIdentifier) }
        }
        #endif

        guard !records.isEmpty else { return 0 }

        var enqueuedCount = 0
        for record in records {
            try Task.checkCancellation()
            record.status = .exporting
            record.lastAttemptAt = .now
            record.lastError = nil
            try? modelContext.save()

            do {
                let localIdentifier = record.localIdentifier
                let creationDate = record.creationDate
                let exports = try await exportResources(forLocalIdentifier: localIdentifier)
                var remotePaths: [String] = []
                var bytes: Int64 = 0
                // Hash de la ressource principale (la 1re export). On l'utilise
                // pour comparer avec le hash distant après upload — c'est la
                // garantie d'intégrité bout-en-bout. Calculé une seule fois,
                // off-MainActor, donc transparent côté UI même pour de gros
                // fichiers. Échec de hash = log info, pas blocant.
                if let primary = exports.first, record.localHash == nil {
                    if let hash = try? await Self.computeMD5(url: primary.url) {
                        record.localHash = hash
                    }
                }
                // Déduplication par hash : si un autre asset déjà terminé a
                // le même MD5, on n'uploade pas une deuxième fois. On copie
                // ses `remotePaths` pour que verifyAsset ait un point d'ancrage
                // si l'utilisateur lance "Vérifier l'intégrité" plus tard, et
                // on bascule en `.skipped` (statut existant, exclu de pending/
                // active/completed dans le hero et des octets transférés). Si
                // le hash est nil (calcul échoué), on continue le flux normal.
                if let hash = record.localHash, !hash.isEmpty,
                   let duplicate = findUploadedDuplicate(hash: hash, excluding: record.localIdentifier) {
                    record.status = .skipped
                    record.remotePaths = duplicate.remotePaths
                    record.byteCount = duplicate.byteCount
                    record.completedAt = .now
                    record.lastError = nil
                    try? modelContext.save()
                    await LogService.shared.log(.info, category: "photos", message: "Doublon ignoré (\(hash.prefix(8))) : \(record.localIdentifier)")
                    await Task.yield()
                    continue
                }
                for exported in exports {
                    let remotePath = Self.remotePathForAsset(
                        baseFolder: folder,
                        localIdentifier: localIdentifier,
                        creationDate: creationDate,
                        filename: exported.url.lastPathComponent
                    )
                    try await TransferQueue.shared.enqueueUpload(
                        local: exported.url,
                        remote: remote,
                        path: remotePath,
                        sourceKind: .photoLibrary
                    )
                    remotePaths.append(remotePath)
                    bytes += exported.bytes
                    // Cède le MainActor entre chaque enqueueUpload : sans
                    // ça, 25 records × 1-2 fichiers × ~50ms d'enqueue MainActor
                    // = MainActor pinné 1-3s, UI complètement gelée (tab switch
                    // impossible, Remotes inaccessible).
                    await Task.yield()
                }
                record.remotePaths = remotePaths
                record.byteCount = bytes
                record.status = .enqueued
                record.lastError = nil
                try? modelContext.save()
                enqueuedCount += 1
            } catch {
                record.status = .failed
                record.retryCount += 1
                record.lastError = error.localizedDescription
                try? modelContext.save()
                await LogService.shared.log(.error, category: "photos", message: "Asset \(record.localIdentifier) non enqueue : \(error.localizedDescription)")
            }
            // Yield également entre records pour garantir qu'un tap
            // utilisateur (tab switch, NavigationLink) puisse être traité
            // entre deux exports — un export PhotoKit peut se terminer
            // instantanément si l'asset est déjà sur device, et la boucle
            // enchaînerait sans laisser SwiftUI rendre.
            await Task.yield()
        }
        return enqueuedCount
    }

    public func transferDidFinish(destinationPath: String, success: Bool, error: String?) {
        guard let modelContext else { return }

        var descriptor = FetchDescriptor<PhotoSyncAsset>(
            predicate: #Predicate {
                $0.statusRaw == "enqueued" || $0.statusRaw == "exporting" || $0.statusRaw == "failed"
            },
            sortBy: [SortDescriptor(\.lastAttemptAt, order: .reverse)]
        )
        descriptor.fetchLimit = 200
        guard let records = try? modelContext.fetch(descriptor),
              let record = records.first(where: { $0.remotePaths.contains(destinationPath) }) else {
            return
        }

        if !success {
            record.status = .failed
            record.retryCount += 1
            record.lastError = error ?? "Upload PhotoSync échoué"
            try? modelContext.save()
            scheduleContinuationIfNeeded()
            return
        }

        if areAllRemotePathsUploaded(for: record, in: modelContext) {
            record.status = .completed
            record.completedAt = .now
            record.lastError = nil
            try? modelContext.save()
            scheduleContinuationIfNeeded()
            // Best-effort post-upload verification : on interroge rclone pour
            // le hash MD5 du fichier distant et on compare au localHash. Non
            // bloquant — si rclone ne supporte pas le hash MD5 sur ce backend
            // (cas: certains S3 sans MD5 sur multipart), on marque "unsupported"
            // mais le fichier reste considéré comme uploadé avec succès.
            scheduleVerification(for: record.localIdentifier, paths: record.remotePaths)
        }
    }

    /// Kicks the best-effort verification of every remote path of the asset.
    /// Runs detached so the completion callback returns immediately — the
    /// caller (TransferQueue poll loop) doesn't wait for the verify result.
    private func scheduleVerification(for localIdentifier: String, paths: [String]) {
        guard let remote = configuredRemote, !paths.isEmpty else { return }
        Task { @MainActor [weak self] in
            await self?.verifyAsset(localIdentifier: localIdentifier, remote: remote, paths: paths)
        }
    }

    /// Fetches the MD5 of each `paths[]` from rclone via `operations/stat` and
    /// updates `remoteHash` + `verificationStatus` on the asset. The status is
    /// the worst of the per-path comparisons :
    /// - `"verified"` si tous les hashes correspondent
    /// - `"mismatch"` si au moins un hash diffère
    /// - `"missing"` si stat échoue / fichier introuvable
    /// - `"unsupported"` si rclone renvoie un hash vide (backend sans MD5)
    private func verifyAsset(localIdentifier: String, remote: String, paths: [String]) async {
        guard let modelContext else { return }
        let descriptor = FetchDescriptor<PhotoSyncAsset>(
            predicate: #Predicate { $0.localIdentifier == localIdentifier }
        )
        guard let record = try? modelContext.fetch(descriptor).first else { return }

        var aggregatedStatus = "verified"
        var remoteHashLog: String?
        for path in paths {
            let remoteHash: String?
            do {
                let entry = try await RemoteService.shared.stat(remote: remote, path: path)
                remoteHash = entry?.hashMD5
            } catch {
                aggregatedStatus = "missing"
                continue
            }
            guard let remoteHash, !remoteHash.isEmpty else {
                if aggregatedStatus == "verified" { aggregatedStatus = "unsupported" }
                continue
            }
            remoteHashLog = remoteHash
            if let local = record.localHash, !local.isEmpty {
                if local.lowercased() != remoteHash.lowercased() {
                    aggregatedStatus = "mismatch"
                    break
                }
            } else {
                // Pas de hash local (calcul échoué à l'enqueue) — on garde
                // le hash distant comme référence mais on marque "unsupported"
                // au lieu de "verified" puisqu'on ne peut pas affirmer l'intégrité.
                if aggregatedStatus == "verified" { aggregatedStatus = "unsupported" }
            }
        }
        record.remoteHash = remoteHashLog
        record.verificationStatus = aggregatedStatus
        try? modelContext.save()
        if aggregatedStatus == "mismatch" {
            await LogService.shared.log(.error, category: "photos", message: "Hash distant ne correspond pas pour \(localIdentifier).")
        }
    }

    /// Cherche un asset déjà uploadé qui partage exactement le même MD5.
    /// Inclut `.completed` ET `.skipped` (un doublon de doublon réutilise la
    /// même destination). Filtre `excluding` évite le faux-positif sur soi-
    /// même. Retourne `nil` si aucun match ou si modelContext non attaché.
    private func findUploadedDuplicate(hash: String, excluding localIdentifier: String) -> PhotoSyncAsset? {
        guard let modelContext else { return nil }
        // Predicate gardé minimal (hash + statut) pour ne pas surcharger le
        // type-checker SwiftData ; on filtre `localIdentifier` à la main.
        let descriptor = FetchDescriptor<PhotoSyncAsset>(
            predicate: #Predicate { asset in
                asset.localHash == hash && asset.statusRaw == "completed"
            }
        )
        let matches = (try? modelContext.fetch(descriptor)) ?? []
        return matches.first(where: { $0.localIdentifier != localIdentifier })
    }

    /// Snapshot du buffer de débit pour le graphique stats. Renvoie une liste
    /// de points `(date, bytesPerSecond)` calculés par différence entre samples
    /// consécutifs. Liste vide tant que < 2 samples accumulés.
    public func throughputHistory() -> [(date: Date, bytesPerSecond: Double)] {
        guard throughputSamples.count >= 2 else { return [] }
        var points: [(Date, Double)] = []
        for i in 1..<throughputSamples.count {
            let prev = throughputSamples[i - 1]
            let cur = throughputSamples[i]
            let dt = cur.date.timeIntervalSince(prev.date)
            guard dt > 0 else { continue }
            let bps = Double(max(0, cur.bytes - prev.bytes)) / dt
            points.append((cur.date, bps))
        }
        return points
    }

    /// MD5 streaming via `CryptoKit`. Lit le fichier par chunks de 1 MB pour
    /// ne pas charger un MOV 4 Go en RAM (`Data(contentsOf:)` mappe le fichier
    /// mais la digestion non chunked peut quand même peser sur la mémoire). Le
    /// calcul s'effectue sur une `Task.detached` pour libérer le MainActor.
    nonisolated static func computeMD5(url: URL) async throws -> String {
        try await Task.detached(priority: .utility) {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            var hasher = Insecure.MD5()
            let chunkSize = 1 << 20 // 1 MiB
            while autoreleasepool(invoking: { () -> Bool in
                let chunk = handle.readData(ofLength: chunkSize)
                if chunk.isEmpty { return false }
                hasher.update(data: chunk)
                return true
            }) {}
            let digest = hasher.finalize()
            return digest.map { String(format: "%02hhx", $0) }.joined()
        }.value
    }

    private func scheduleContinuationIfNeeded() {
        guard shouldContinueUntilEmpty else { return }
        continuationTask?.cancel()
        continuationTask = Task { @MainActor in
            // Délai allongé à 1s (vs 250ms) : laisse SwiftUI traiter les
            // taps utilisateur (tab switch, ouverture Remotes) entre deux
            // batches de sync. Throughput inchangé — la prochaine batch
            // démarre dès que le user est inactif 1s.
            try? await Task.sleep(for: .seconds(1))
            await PhotoSyncService.shared.continueFullSyncIfNeeded()
        }
    }

    private func continueFullSyncIfNeeded() async {
        guard shouldContinueUntilEmpty else { return }
        guard isEnabled, configuredRemote != nil else {
            shouldContinueUntilEmpty = false
            return
        }
        guard canStartNewWork else {
            scheduleBackgroundProcessing()
            return
        }

        let pendingCount = (try? pendingWorkCount(includeFailedRetries: false)) ?? 0
        let activeCount = (try? activePhotoAssetCount()) ?? 0
        guard Self.shouldContinueSync(
            continueUntilEmpty: shouldContinueUntilEmpty,
            pendingCount: pendingCount,
            activeCount: activeCount,
            limits: limits
        ) else {
            if pendingCount == 0 && activeCount == 0 {
                shouldContinueUntilEmpty = false
            }
            return
        }

        _ = await runSync(
            requestedLimit: limits.enqueueBatchSize,
            continueUntilEmpty: true,
            includeFailedRetries: false
        )
    }

    private func finishFullSyncIfDrained(_ summary: PhotoSyncRunSummary) {
        if summary.pendingCount == 0 && summary.activeCount == 0 {
            shouldContinueUntilEmpty = false
        }
    }

    private func areAllRemotePathsUploaded(for record: PhotoSyncAsset, in modelContext: ModelContext) -> Bool {
        let remotePaths = record.remotePaths
        guard !remotePaths.isEmpty else { return false }

        let descriptor = FetchDescriptor<Transfer>(
            predicate: #Predicate {
                $0.sourceKindRaw == "photoLibrary" && $0.statusRaw == "completed"
            }
        )
        guard let completedTransfers = try? modelContext.fetch(descriptor) else { return false }
        let completedPaths = Set(completedTransfers.map(\.destinationPath))
        return remotePaths.allSatisfy { completedPaths.contains($0) }
    }

    private func pendingWorkCount(includeFailedRetries: Bool) throws -> Int {
        guard let modelContext else { return 0 }
        let descriptor = FetchDescriptor<PhotoSyncAsset>(
            predicate: #Predicate { $0.statusRaw == "pending" || $0.statusRaw == "failed" }
        )
        let records = try modelContext.fetch(descriptor)
        return records.filter { record in
            record.status == .pending || (includeFailedRetries && record.retryCount < limits.maxRetries)
        }.count
    }

    private func activePhotoAssetCount() throws -> Int {
        guard let modelContext else { return 0 }
        let descriptor = FetchDescriptor<PhotoSyncAsset>(
            predicate: #Predicate { $0.statusRaw == "exporting" || $0.statusRaw == "enqueued" }
        )
        return try modelContext.fetchCount(descriptor)
    }

    private func statusSnapshot(
        authorizationStatus: PHAuthorizationStatus? = nil,
        visibleAssetCount: Int? = nil,
        newlyIndexedCount: Int = 0,
        enqueuedCount: Int = 0
    ) async -> PhotoSyncRunSummary {
        let rawStatus = authorizationStatus ?? PHPhotoLibrary.authorizationStatus(for: .readWrite)
        let authorization = Self.authorizationState(from: rawStatus)
        let visibleCount: Int
        if let visibleAssetCount {
            visibleCount = visibleAssetCount
        } else if authorization.isUsable {
            visibleCount = await Self.visiblePhotoAssetCount()
        } else {
            visibleCount = 0
        }
        let counts = photoSyncCounts()
        recordThroughputSample(transferred: counts.transferredBytes, at: Date())
        let (bps, eta) = throughputMetrics(
            totalBytes: counts.totalBytes,
            transferredBytes: counts.transferredBytes
        )
        return PhotoSyncRunSummary(
            authorization: authorization,
            visibleAssetCount: visibleCount,
            indexedCount: counts.indexed,
            newlyIndexedCount: newlyIndexedCount,
            enqueuedCount: enqueuedCount,
            pendingCount: counts.pending,
            activeCount: counts.active,
            completedCount: counts.completed,
            failedCount: counts.failed,
            totalBytes: counts.totalBytes,
            transferredBytes: counts.transferredBytes,
            averageBytesPerSecond: bps,
            estimatedTimeRemaining: eta,
            pausedByUser: isPausedByUser
        )
    }

    /// Append a sample to the rolling throughput buffer and prune anything
    /// older than `throughputWindow`. Called every time `statusSnapshot` runs
    /// (≈4 s cadence from the View), so the buffer stays bounded around 8
    /// entries — cheap to scan.
    private func recordThroughputSample(transferred: Int64, at date: Date) {
        if let last = throughputSamples.last, last.bytes == transferred, date.timeIntervalSince(last.date) < 1 {
            return
        }
        throughputSamples.append((date, transferred))
        let cutoff = date.addingTimeInterval(-throughputWindow)
        if let firstFreshIndex = throughputSamples.firstIndex(where: { $0.date >= cutoff }), firstFreshIndex > 0 {
            throughputSamples.removeFirst(firstFreshIndex)
        }
    }

    /// Compute the instantaneous bytes/sec (linear slope across the rolling
    /// window) and the resulting ETA. Returns `(0, nil)` when the window holds
    /// fewer than two samples or progress is flat — avoids reporting bogus
    /// "0 s remaining" before any work has happened.
    private func throughputMetrics(totalBytes: Int64, transferredBytes: Int64) -> (Double, TimeInterval?) {
        guard throughputSamples.count >= 2,
              let oldest = throughputSamples.first,
              let newest = throughputSamples.last else {
            return (0, nil)
        }
        let elapsed = newest.date.timeIntervalSince(oldest.date)
        guard elapsed > 0.5 else { return (0, nil) }
        let delta = Double(max(0, newest.bytes - oldest.bytes))
        let bps = delta / elapsed
        guard bps > 1 else { return (bps, nil) }
        let remaining = Double(max(0, totalBytes - transferredBytes))
        let eta = remaining > 0 ? remaining / bps : 0
        return (bps, eta)
    }

    private func photoSyncCounts() -> PhotoSyncCounts {
        let byteTotals = photoSyncByteTotals()
        return PhotoSyncCounts(
            indexed: fetchPhotoSyncCount(),
            pending: fetchPhotoSyncCount(.pending),
            active: fetchPhotoSyncCount(.exporting) + fetchPhotoSyncCount(.enqueued),
            completed: fetchPhotoSyncCount(.completed),
            failed: fetchPhotoSyncCount(.failed),
            totalBytes: byteTotals.total,
            transferredBytes: byteTotals.transferred
        )
    }

    /// Aggregates byte-level progress across the photo sync pipeline.
    ///
    /// - `total` = sum of `byteCount` over `PhotoSyncAsset` rows that count toward
    ///   the active backlog (pending, exporting, enqueued, completed). Failed and
    ///   skipped assets are intentionally excluded so the ratio stays meaningful.
    /// - `transferred` = sum of `bytesTransferred` over `Transfer` rows tagged with
    ///   `sourceKindRaw == "photoLibrary"`, clamped to `total` so the live RPC
    ///   updates can't push the bar past 100%.
    private func photoSyncByteTotals() -> (total: Int64, transferred: Int64) {
        guard let modelContext else { return (0, 0) }
        let assetDescriptor = FetchDescriptor<PhotoSyncAsset>(
            predicate: #Predicate {
                $0.statusRaw == "pending"
                    || $0.statusRaw == "exporting"
                    || $0.statusRaw == "enqueued"
                    || $0.statusRaw == "completed"
            }
        )
        let assets = (try? modelContext.fetch(assetDescriptor)) ?? []
        let totalBytes = assets.reduce(Int64(0)) { $0 + max(0, $1.byteCount) }

        let transferDescriptor = FetchDescriptor<Transfer>(
            predicate: #Predicate { $0.sourceKindRaw == "photoLibrary" }
        )
        let transfers = (try? modelContext.fetch(transferDescriptor)) ?? []
        let rawTransferred = transfers.reduce(Int64(0)) { $0 + max(0, $1.bytesTransferred) }
        let transferred = totalBytes > 0 ? min(rawTransferred, totalBytes) : rawTransferred
        return (totalBytes, transferred)
    }

    private func fetchPhotoSyncCount(_ status: PhotoSyncStatus? = nil) -> Int {
        guard let modelContext else { return 0 }
        if let status {
            let raw = status.rawValue
            let descriptor = FetchDescriptor<PhotoSyncAsset>(
                predicate: #Predicate { $0.statusRaw == raw }
            )
            return (try? modelContext.fetchCount(descriptor)) ?? 0
        }
        return (try? modelContext.fetchCount(FetchDescriptor<PhotoSyncAsset>())) ?? 0
    }

    private struct ExportedResource: Sendable {
        let url: URL
        let bytes: Int64
    }

    private func exportResources(forLocalIdentifier localIdentifier: String) async throws -> [ExportedResource] {
        try await Task.detached(priority: .utility) {
            try await Self.exportResourcesDetached(forLocalIdentifier: localIdentifier)
        }.value
    }

    nonisolated static func scanCandidates(
        _ candidates: [PhotoSyncCandidate],
        excluding existingIDs: Set<String>
    ) -> [PhotoSyncCandidate] {
        candidates.filter { !existingIDs.contains($0.localIdentifier) }
    }

    nonisolated static func batches<T>(_ elements: [T], size: Int) -> [[T]] {
        guard size > 0, !elements.isEmpty else { return [] }
        return stride(from: 0, to: elements.count, by: size).map { start in
            Array(elements[start..<min(start + size, elements.count)])
        }
    }

    nonisolated static func enqueueCapacity(
        activeCount: Int,
        requestedLimit: Int,
        limits: PhotoSyncLimits
    ) -> Int {
        max(0, min(requestedLimit, limits.maxActiveUploads - activeCount))
    }

    nonisolated static func shouldContinueSync(
        continueUntilEmpty: Bool,
        pendingCount: Int,
        activeCount: Int,
        limits: PhotoSyncLimits
    ) -> Bool {
        continueUntilEmpty && pendingCount > 0 && activeCount < limits.maxActiveUploads
    }

    /// Resolve the set of asset localIdentifiers eligible for sync given the
    /// user's current album selection. Returns `nil` when no album is
    /// selected (= scope is the whole library, no filter). Synchronous so
    /// it can be called from both MainActor (enqueuePending) and nonisolated
    /// (scanPhotoLibrary) contexts. Photos fetches are fast in-memory ops.
    #if os(iOS)
    nonisolated static func eligibleAssetIDs() -> Set<String>? {
        let selectedAlbumIDs = PhotoSyncAlbumStore.load()
        guard !selectedAlbumIDs.isEmpty else { return nil }
        let collections = PHAssetCollection.fetchAssetCollections(
            withLocalIdentifiers: Array(selectedAlbumIDs),
            options: nil
        )
        var ids = Set<String>()
        collections.enumerateObjects { collection, _, _ in
            let assets = PHAsset.fetchAssets(in: collection, options: nil)
            assets.enumerateObjects { asset, _, _ in
                ids.insert(asset.localIdentifier)
            }
        }
        return ids
    }
    #endif

    nonisolated private static func scanPhotoLibrary(
        excluding existingIDs: Set<String>
    ) -> PhotoSyncScanResult {
        // Read the user's album filter from UserDefaults. An empty set means
        // "scan everything" (legacy default behavior).
        #if os(iOS)
        let selectedAlbumIDs = PhotoSyncAlbumStore.load()
        #else
        let selectedAlbumIDs = Set<String>()
        #endif

        let filters = loadFilters()

        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]

        // Choose between full library scan and per-album scan. For per-album
        // we union the assets across collections, deduplicated by localIdentifier
        // — a photo can appear in multiple albums and we don't want it staged twice.
        let visibleCount: Int
        var candidates: [PhotoSyncCandidate] = []
        var seenLocalIDs = Set<String>()

        let append: (PHAsset) -> Void = { asset in
            guard matchesFilters(asset, filters: filters) else { return }
            let id = asset.localIdentifier
            guard seenLocalIDs.insert(id).inserted else { return }
            candidates.append(
                PhotoSyncCandidate(
                    localIdentifier: id,
                    mediaType: mediaTypeName(asset.mediaType),
                    creationDate: asset.creationDate
                )
            )
        }

        if selectedAlbumIDs.isEmpty {
            let assets = PHAsset.fetchAssets(with: options)
            visibleCount = assets.count
            candidates.reserveCapacity(min(visibleCount, 512))
            assets.enumerateObjects { asset, _, stop in
                if Task.isCancelled { stop.pointee = true; return }
                append(asset)
            }
        } else {
            let collections = PHAssetCollection.fetchAssetCollections(
                withLocalIdentifiers: Array(selectedAlbumIDs),
                options: nil
            )
            collections.enumerateObjects { collection, _, _ in
                let assets = PHAsset.fetchAssets(in: collection, options: options)
                assets.enumerateObjects { asset, _, stop in
                    if Task.isCancelled { stop.pointee = true; return }
                    append(asset)
                }
            }
            // visibleAssetCount = unique assets in the selected albums, not
            // the raw sum that double-counts photos in overlapping albums.
            // Otherwise the UI progress bar shows nonsense like "340/200".
            visibleCount = seenLocalIDs.count
        }

        return PhotoSyncScanResult(
            visibleAssetCount: visibleCount,
            candidates: scanCandidates(candidates, excluding: existingIDs)
        )
    }

    /// Returns `true` when the asset passes every active filter — type, sous-
    /// type (live/screenshot/slow-mo/panorama), date range et durée vidéo.
    /// On garde la logique inline (pas d'optimisation NSPredicate) car
    /// `enumerateObjects` ne supporte pas le filtrage de toute façon.
    nonisolated static func matchesFilters(_ asset: PHAsset, filters: PhotoSyncFilters) -> Bool {
        // Type principal.
        switch asset.mediaType {
        case .image:
            if !filters.includePhotos { return false }
        case .video:
            if !filters.includeVideos { return false }
        default:
            // audio, unknown — toujours ignorés (pas exposés dans l'UI).
            return false
        }

        // Sous-types qui se cumulent (un Live Photo est aussi une image, etc.).
        let sub = asset.mediaSubtypes
        if sub.contains(.photoLive) && !filters.includeLivePhotos { return false }
        if sub.contains(.photoScreenshot) && !filters.includeScreenshots { return false }
        if sub.contains(.photoPanorama) && !filters.includePanoramas { return false }
        if (sub.contains(.videoHighFrameRate) || sub.contains(.videoTimelapse)) && !filters.includeSlowMo {
            return false
        }

        // Date range.
        if let start = filters.dateRangeStart {
            guard let created = asset.creationDate, created >= start else { return false }
        }
        if let end = filters.dateRangeEnd {
            guard let created = asset.creationDate, created <= end else { return false }
        }

        // Durée vidéo (proxy taille).
        if asset.mediaType == .video, let max = filters.maxVideoDurationSeconds, max > 0 {
            if asset.duration > max { return false }
        }

        return true
    }

    nonisolated private static func visiblePhotoAssetCount() async -> Int {
        await Task.detached(priority: .utility) {
            let options = PHFetchOptions()
            return PHAsset.fetchAssets(with: options).count
        }.value
    }

    nonisolated private static func exportResourcesDetached(
        forLocalIdentifier localIdentifier: String
    ) async throws -> [ExportedResource] {
        let result = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
        guard let asset = result.firstObject else { throw PhotoSyncError.assetMissing }

        let allResources = PHAssetResource.assetResources(for: asset)
        let resources = preferredResources(from: allResources)
        guard !resources.isEmpty else { throw PhotoSyncError.noExportableResource }

        let stagingRoot = try stagingDirectory()
        var exported: [ExportedResource] = []
        for resource in resources {
            try Task.checkCancellation()
            let filename = safeFilename(resource.originalFilename, fallbackExtension: fallbackExtension(for: resource))
            let target = stagingRoot
                .appending(path: safeIdentifier(localIdentifier), directoryHint: .isDirectory)
                .appending(path: filename)
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: target.path) {
                try FileManager.default.removeItem(at: target)
            }

            let options = PHAssetResourceRequestOptions()
            options.isNetworkAccessAllowed = true
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                PHAssetResourceManager.default().writeData(for: resource, toFile: target, options: options) { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }
            let size = Int64((try? target.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            exported.append(ExportedResource(url: target, bytes: size))
        }
        return exported
    }

    nonisolated private static func preferredResources(from resources: [PHAssetResource]) -> [PHAssetResource] {
        let primary = resources.filter { resource in
            switch resource.type {
            case .photo, .video, .pairedVideo, .fullSizePhoto, .fullSizeVideo:
                return true
            default:
                return false
            }
        }
        return primary.isEmpty ? resources.prefix(1).map { $0 } : primary
    }

    nonisolated private static func remotePathForAsset(
        baseFolder: String,
        localIdentifier: String,
        creationDate: Date?,
        filename: String
    ) -> String {
        let date = creationDate ?? .now
        let calendar = Calendar(identifier: .gregorian)
        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        let stampFormatter = DateFormatter()
        stampFormatter.calendar = calendar
        stampFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let stamp = stampFormatter.string(from: date)
        let cleanID = safeIdentifier(localIdentifier)
        let cleanFilename = safeFilename(filename, fallbackExtension: nil)
        let prefix = baseFolder.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return "\(prefix)/\(year)/\(String(format: "%02d", month))/\(stamp)_\(cleanID)_\(cleanFilename)"
    }

    private var canStartNewWork: Bool {
        suspensionReason == nil
    }

    /// Why the sync is currently paused, or nil if it can run. Exposed so the
    /// PhotoSyncSettingsView can render a clear banner instead of letting the
    /// user wonder why nothing is happening after they tapped "Synchroniser".
    public var suspensionReason: String? {
        if ProcessInfo.processInfo.isLowPowerModeEnabled {
            return "Mode économie d'énergie actif — la synchro reprendra automatiquement."
        }
        guard requiresExternalPower else { return nil }
        UIDevice.current.isBatteryMonitoringEnabled = true
        let state = UIDevice.current.batteryState
        if state == .charging || state == .full {
            return nil
        }
        return "En attente du branchement secteur (option « Exiger la charge » activée)."
    }

    nonisolated private static func stagingDirectory() throws -> URL {
        let caches = try FileManager.default.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let root = caches.appending(path: "PhotoSyncStaging", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    nonisolated private static func safeIdentifier(_ id: String) -> String {
        id.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
    }

    nonisolated private static func safeFilename(_ name: String, fallbackExtension: String?) -> String {
        let fallback = fallbackExtension.map { "asset.\($0)" } ?? "asset"
        let base = name.isEmpty ? fallback : name
        let forbidden = CharacterSet(charactersIn: "/:")
        return base.components(separatedBy: forbidden).joined(separator: "_")
    }

    nonisolated private static func fallbackExtension(for resource: PHAssetResource) -> String {
        switch resource.type {
        case .photo, .fullSizePhoto:
            return "heic"
        case .video, .fullSizeVideo, .pairedVideo:
            return "mov"
        default:
            return "dat"
        }
    }

    nonisolated private static func mediaTypeName(_ mediaType: PHAssetMediaType) -> String {
        switch mediaType {
        case .image: return "image"
        case .video: return "video"
        case .audio: return "audio"
        default: return "unknown"
        }
    }

    nonisolated private static func authorizationState(from status: PHAuthorizationStatus) -> PhotoSyncAuthorizationState {
        switch status {
        case .authorized:
            return .authorized
        case .limited:
            return .limited
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .unknown
        }
    }
}

public enum PhotoSyncError: LocalizedError {
    case authorizationDenied
    case assetMissing
    case noExportableResource

    public var errorDescription: String? {
        switch self {
        case .authorizationDenied:
            return "Acces a la phototheque refuse ou limite sans selection exploitable."
        case .assetMissing:
            return "Asset PhotoKit introuvable."
        case .noExportableResource:
            return "Aucune ressource originale exportable."
        }
    }
}
