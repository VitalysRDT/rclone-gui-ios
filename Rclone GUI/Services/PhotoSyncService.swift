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

public struct PhotoSyncFilters: Sendable, Equatable {
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

    public nonisolated init(
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

    public nonisolated static let allEnabled = PhotoSyncFilters()

    public var isDefault: Bool {
        self == .allEnabled
    }
}

// Conformance Codable via extension avec init(from:) / encode(to:)
// explicitement nonisolated. Sans ça, le projet utilise MainActor
// comme default isolation et la conformance synthétisée hérite de
// MainActor, ce qui empêche son utilisation depuis un contexte
// nonisolated (loadFilters, JSONDecoder appelé hors MainActor).
extension PhotoSyncFilters: Codable {
    enum CodingKeys: String, CodingKey {
        case includePhotos, includeVideos, includeLivePhotos
        case includeScreenshots, includeSlowMo, includePanoramas
        case dateRangeStart, dateRangeEnd, maxVideoDurationSeconds
    }

    public nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            includePhotos: try c.decodeIfPresent(Bool.self, forKey: .includePhotos) ?? true,
            includeVideos: try c.decodeIfPresent(Bool.self, forKey: .includeVideos) ?? true,
            includeLivePhotos: try c.decodeIfPresent(Bool.self, forKey: .includeLivePhotos) ?? true,
            includeScreenshots: try c.decodeIfPresent(Bool.self, forKey: .includeScreenshots) ?? true,
            includeSlowMo: try c.decodeIfPresent(Bool.self, forKey: .includeSlowMo) ?? true,
            includePanoramas: try c.decodeIfPresent(Bool.self, forKey: .includePanoramas) ?? true,
            dateRangeStart: try c.decodeIfPresent(Date.self, forKey: .dateRangeStart),
            dateRangeEnd: try c.decodeIfPresent(Date.self, forKey: .dateRangeEnd),
            maxVideoDurationSeconds: try c.decodeIfPresent(Double.self, forKey: .maxVideoDurationSeconds)
        )
    }

    public nonisolated func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(includePhotos, forKey: .includePhotos)
        try c.encode(includeVideos, forKey: .includeVideos)
        try c.encode(includeLivePhotos, forKey: .includeLivePhotos)
        try c.encode(includeScreenshots, forKey: .includeScreenshots)
        try c.encode(includeSlowMo, forKey: .includeSlowMo)
        try c.encode(includePanoramas, forKey: .includePanoramas)
        try c.encodeIfPresent(dateRangeStart, forKey: .dateRangeStart)
        try c.encodeIfPresent(dateRangeEnd, forKey: .dateRangeEnd)
        try c.encodeIfPresent(maxVideoDurationSeconds, forKey: .maxVideoDurationSeconds)
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

/// Avancement live d'un batch rclone copy en cours, alimenté par
/// `core/stats` toutes les 500ms pendant la sync photo. Nil quand
/// aucun batch n'est actif.
public struct PhotoBatchLiveProgress: Sendable, Equatable {
    public let bytesTransferred: Int64
    public let bytesTotal: Int64
    public let speedBytesPerSec: Double
    public let etaSeconds: Int64?
    public let currentFilename: String?
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
    /// Compteurs de la session de sync en cours pour afficher « X/Y
    /// photos uploadées » dans la bannière Transferts. Reset à chaque
    /// runPipeline.
    public let sessionUploaded: Int
    public let sessionInitialPending: Int

    public var isLimitedAccess: Bool {
        authorization == .limited
    }

    public var byteProgress: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1.0, Double(transferredBytes) / Double(totalBytes))
    }

    /// Progression « X/Y » de la session en cours (0..1) ou nil si pas
    /// de session active.
    public var sessionProgress: Double? {
        guard sessionInitialPending > 0 else { return nil }
        return min(1.0, Double(sessionUploaded) / Double(sessionInitialPending))
    }
}

struct PhotoSyncLimits: Sendable, Equatable {
    var indexSaveBatchSize = 250
    /// Nombre de photos par batch rclone copy. Réduit à 10 : amorce
    /// l'upload en ~3-5s (vs 22s pour batch=50). Le coût d'init d'un
    /// job sync/copy étant négligeable côté librclone, on préfère
    /// streamer rapidement les petits batchs pour que l'utilisateur
    /// voie le compteur avancer. Le throughput global reste bon parce
    /// que le pipeline garde 2 batchs en avance (buffer).
    var enqueueBatchSize = 10
    /// Cap réel par batch rclone copy. Aligné sur enqueueBatchSize.
    var maxActiveUploads = 10
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

    /// Progression live du batch rclone copy en cours. Mise à jour par
    /// `waitForRcloneJob` à chaque tick de polling, lue par
    /// `statusSnapshot` pour qu'elle apparaisse dans la hero card de
    /// PhotoSyncSettingsView (bar de progression + débit + ETA).
    /// `nil` entre deux batches.
    public private(set) var liveBatchProgress: PhotoBatchLiveProgress?

    /// Exposition publique de isSyncing pour que TransfersView garde la
    /// bannière live affichée même pendant l'inter-batch (200ms où
    /// liveBatchProgress redevient nil entre deux sync/copy).
    public var isSyncingPublic: Bool { isSyncing }

    /// Timestamp du dernier `indexLibrary()` complet. Permet de skipper
    /// le scan PhotoKit (coûteux : ~1-2s sur 18k photos) entre deux
    /// batches consécutifs — l'index ne change pas significativement
    /// en 60s, et photoLibraryDidChange réinitialise déjà ce cache.
    private var lastFullIndexAt: Date?
    private static let indexCacheTTL: TimeInterval = 60

    /// Timestamp (haute résolution) du moment où le dernier sync/copy
    /// rclone s'est terminé. Sert à mesurer dans `enqueuePending`
    /// combien de temps a duré la « préparation du prochain batch »
    /// (marquage .completed + sleep 200ms + re-entry runSync + auth +
    /// indexLibrary). Catégorie `batch-perf`. nil avant le 1er batch.
    private var lastBatchEndedAt: ContinuousClock.Instant?

    /// Invalide le cache d'index — force un scan PhotoKit complet au
    /// prochain runSync. Appelé par photoLibraryDidChange et après un
    /// changement de filtres / album.
    public func invalidateIndexCache() { lastFullIndexAt = nil }

    /// Vrai tant qu'un sync/copy rclone est actif. Sert au pipeline
    /// pour réduire la concurrence des exports PhotoKit pendant un
    /// upload SFTP (4 → 2) afin de ne pas saturer le CPU/réseau.
    private var isUploadingBatch = false

    /// Concurrence d'exports PhotoKit : 4 si pas d'upload en cours
    /// (full speed), 2 si un sync/copy tourne (anti-saturation). C'est
    /// le motif observé empiriquement : avec 4 exports + 1 upload SFTP
    /// les exports passent de 80ms à 17000ms à cause de la contention.
    private var exportConcurrencyForCurrentLoad: Int {
        isUploadingBatch ? 2 : 4
    }

    /// Compteur global de la session en cours. uploadedThisSession est
    /// incrémenté à chaque batch upload réussi. Reset quand une nouvelle
    /// session démarre (premier batch d'un cycle). Sert au compteur
    /// « X / Y photos » affiché dans la bannière Transferts.
    public private(set) var uploadedThisSession: Int = 0
    public private(set) var sessionInitialPending: Int = 0
    public private(set) var sessionStartedAt: Date?

    /// Reset les compteurs de session — appelé au début d'un cycle
    /// drainant (runPipeline). Initialise sessionInitialPending au
    /// nombre de pending courant pour avoir un dénominateur stable.
    private func resetSessionCounters(pendingNow: Int) {
        uploadedThisSession = 0
        sessionInitialPending = pendingNow
        sessionStartedAt = Date()
    }

    /// Convertit un délai `ContinuousClock` depuis `since` en millisecondes
    /// entières. Utilisé par les logs `[batch-perf]`.
    nonisolated static func elapsedMs(since: ContinuousClock.Instant) -> Int {
        let dur = ContinuousClock.now - since
        // dur.components.seconds + attoseconds → ms
        let s = dur.components.seconds
        let atto = dur.components.attoseconds
        return Int(s) * 1000 + Int(atto / 1_000_000_000_000_000)
    }

    /// Formatter partagé pour les timestamps `HH:mm:ss.SSS` des logs
    /// `[batch-perf]`. Statique pour éviter de recréer un formatter à
    /// chaque log dans la boucle d'exports parallèles.
    nonisolated static let perfTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    /// Préfixe `[HH:mm:ss.SSS]` à insérer en tête de chaque message
    /// `[batch-perf]` pour visualiser le chevauchement des exports
    /// parallèles. Toujours basé sur l'horloge système (heure réelle),
    /// indépendamment de ContinuousClock.
    nonisolated static func perfTs() -> String {
        "[" + perfTimeFormatter.string(from: Date()) + "]"
    }
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
        let previousRemote = UserDefaults.standard.string(forKey: "photoSync.remote") ?? ""
        let previousFolder = UserDefaults.standard.string(forKey: "photoSync.folder") ?? ""
        let newRemote = remote ?? ""
        let newFolder = folder.isEmpty ? "Phototheque" : folder

        UserDefaults.standard.set(enabled, forKey: "photoSync.enabled")
        UserDefaults.standard.set(newRemote, forKey: "photoSync.remote")
        UserDefaults.standard.set(newFolder, forKey: "photoSync.folder")
        self.requiresExternalPower = requiresPower
        self.allowsCellular = allowsCellular

        // Quand l'utilisateur change le remote cible (ou le dossier), les
        // photos déjà marquées "completed" pointaient vers l'ANCIEN remote.
        // Sans reset, elles ne seraient jamais uploadées sur le nouveau et
        // l'utilisateur croirait sa photothèque sauvegardée alors qu'elle
        // est ailleurs. On bascule en .pending + reset des remotePaths
        // pour forcer une ré-indexation au prochain scan.
        let remoteChanged = !previousRemote.isEmpty && previousRemote != newRemote
        let folderChanged = !previousFolder.isEmpty && previousFolder != newFolder
        if remoteChanged || folderChanged {
            Task { @MainActor in
                resetUploadedAssetsForReindex(
                    previousRemote: previousRemote,
                    newRemote: newRemote,
                    previousFolder: previousFolder,
                    newFolder: newFolder
                )
            }
        }

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

    /// Remet les photos `completed`/`failed` en `pending` quand le remote
    /// ou le dossier cible change, pour que la prochaine sync ré-uploade
    /// l'historique vers la nouvelle destination. Les paths distants
    /// stockés sont aussi vidés (ils pointaient vers l'ancien remote).
    @MainActor
    private func resetUploadedAssetsForReindex(
        previousRemote: String,
        newRemote: String,
        previousFolder: String,
        newFolder: String
    ) {
        guard let modelContext else { return }
        let descriptor = FetchDescriptor<PhotoSyncAsset>(
            predicate: #Predicate { $0.statusRaw == "completed" || $0.statusRaw == "failed" }
        )
        guard let assets = try? modelContext.fetch(descriptor), !assets.isEmpty else { return }
        for asset in assets {
            asset.status = .pending
            asset.remotePaths = []
            asset.remoteHash = nil
            asset.verificationStatus = nil
            asset.lastError = nil
            asset.lastAttemptAt = nil
            asset.completedAt = nil
            asset.retryCount = 0
        }
        try? modelContext.save()
        Task {
            await LogService.shared.log(
                .info,
                category: "photos",
                message: "Cible photos changée (\(previousRemote)/\(previousFolder) → \(newRemote)/\(newFolder)) : \(assets.count) photos repassées en pending pour ré-upload"
            )
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
        // Bypass throttle 512KB/s tant qu'une sync photo tourne (couvre
        // toute la durée — export + sync/copy + verify), pas seulement
        // un batch isolé. Sans ça l'UserActivityMonitor remettait le
        // bwlimit entre deux batches dès qu'un tap était détecté.
        TransferQueue.shared.incrementActivityBypass()
        defer {
            isSyncing = false
            TransferQueue.shared.decrementActivityBypass()
            scheduleBackgroundProcessing()
        }

        do {
            let authorizationStatus = try await ensurePhotoAuthorization()
            let indexResult = try await indexLibrary()
            let enqueuedCount: Int
            if continueUntilEmpty {
                // Mode pipeline rclone-like : on prépare le batch N+1
                // pendant que sync/copy(N) tourne. Drainage complet,
                // re-loop intégré donc on n'a PAS besoin de
                // scheduleContinuationIfNeeded en sortie.
                enqueuedCount = await runPipeline(
                    remote: remote,
                    folder: configuredFolder,
                    requestedLimit: requestedLimit,
                    includeFailedRetries: includeFailedRetries
                )
            } else {
                // Mode 1-shot : 1 batch unique, sans pipeline.
                if let prepared = try await prepareBatch(
                    remote: remote,
                    folder: configuredFolder,
                    requestedLimit: requestedLimit,
                    includeFailedRetries: includeFailedRetries
                ) {
                    await uploadPreparedBatch(prepared, remote: remote, folder: configuredFolder)
                    enqueuedCount = prepared.enqueuedCount
                } else {
                    enqueuedCount = 0
                }
            }
            let summary = await statusSnapshot(
                authorizationStatus: authorizationStatus,
                visibleAssetCount: indexResult.visibleAssetCount,
                newlyIndexedCount: indexResult.newlyIndexedCount,
                enqueuedCount: enqueuedCount
            )
            if continueUntilEmpty {
                // Pipeline a déjà drainé toutes les pending (boucle while
                // interne). Plus besoin de scheduleContinuationIfNeeded
                // — c'était la source du bug 2-runSync-concurrents
                // (heartbeat tickait pendant le sleep 200ms et lançait
                // un 2e runSync en parallèle).
                finishFullSyncIfDrained(summary)
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
            // Invalide le cache d'index — il y a vraiment du nouveau à
            // découvrir côté PhotoKit, le scan complet redevient utile.
            PhotoSyncService.shared.invalidateIndexCache()
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

        // Skip le scan PhotoKit si on l'a fait il y a < 60s. C'est le
        // chemin chaud entre deux batches de continuation : sans ça,
        // chaque batch démarre par un scan complet de 18k+ photos
        // (~1-2s) avant même de pouvoir exporter quoi que ce soit, ce
        // qui crée le "Préparation du prochain batch…" long visible.
        // photoLibraryDidChange invalide ce cache via lastFullIndexAt
        // = nil quand la photothèque change.
        if let last = lastFullIndexAt, Date().timeIntervalSince(last) < Self.indexCacheTTL {
            await LogService.shared.log(
                .debug,
                category: "batch-perf",
                message: "\(Self.perfTs()) indexLibrary cache=HIT (skip scan)"
            )
            return PhotoSyncIndexResult(visibleAssetCount: 0, newlyIndexedCount: 0)
        }

        let indexStarted = ContinuousClock.now
        await LogService.shared.log(
            .debug,
            category: "batch-perf",
            message: "\(Self.perfTs()) indexLibrary scan PhotoKit start"
        )
        let existingIDs = try await indexedIdentifiers()
        let scan = try await Task.detached(priority: .utility) {
            try Task.checkCancellation()
            return Self.scanPhotoLibrary(excluding: existingIDs)
        }.value
        lastFullIndexAt = Date()
        let indexMs = Self.elapsedMs(since: indexStarted)
        await LogService.shared.log(
            .debug,
            category: "batch-perf",
            message: "\(Self.perfTs()) indexLibrary cache=MISS, scan PhotoKit en \(indexMs)ms (\(scan.candidates.count) nouveaux candidats)"
        )
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

    /// Prépare un batch (phase 1+2+3) sans lancer le sync/copy.
    /// Renvoie nil si rien à préparer. Le caller doit ensuite appeler
    /// `uploadPreparedBatch` pour lancer le sync/copy — ce découpage
    /// permet de PIPELINER (préparer le batch N+1 pendant que N upload).
    private func prepareBatch(
        remote: String,
        folder: String,
        requestedLimit: Int,
        includeFailedRetries: Bool
    ) async throws -> PreparedBatch? {
        guard let modelContext else { return nil }
        let prepStarted = ContinuousClock.now
        await LogService.shared.log(
            .info,
            category: "batch-perf",
            message: "\(Self.perfTs()) enqueuePending start (requestedLimit=\(requestedLimit))"
        )
        // Délai depuis la fin du sync/copy précédent. Couvre marquage
        // .completed, sleep 200ms, re-entry runSync, auth, indexLibrary.
        let interBatchMs: Int = lastBatchEndedAt.map { Self.elapsedMs(since: $0) } ?? 0
        lastBatchEndedAt = nil

        let activeCount = try activePhotoAssetCount()
        let limit = Self.enqueueCapacity(activeCount: activeCount, requestedLimit: requestedLimit, limits: limits)
        guard limit > 0 else { return nil }

        let fetchPendingStarted = ContinuousClock.now
        var pendingDescriptor = FetchDescriptor<PhotoSyncAsset>(
            predicate: #Predicate { $0.statusRaw == "pending" },
            sortBy: [SortDescriptor(\.creationDate, order: .forward)]
        )
        pendingDescriptor.fetchLimit = limit
        var records = try modelContext.fetch(pendingDescriptor)
        let fetchPendingMs = Self.elapsedMs(since: fetchPendingStarted)

        var fetchFailedMs = 0
        if includeFailedRetries && records.count < limit {
            let fetchFailedStarted = ContinuousClock.now
            var failedDescriptor = FetchDescriptor<PhotoSyncAsset>(
                predicate: #Predicate { $0.statusRaw == "failed" },
                sortBy: [SortDescriptor(\.creationDate, order: .forward)]
            )
            failedDescriptor.fetchLimit = 500
            let retryableFailures = try modelContext.fetch(failedDescriptor)
                .filter { $0.retryCount < limits.maxRetries }
                .prefix(limit - records.count)
            records.append(contentsOf: retryableFailures)
            fetchFailedMs = Self.elapsedMs(since: fetchFailedStarted)
        }

        var eligibleMs = 0
        #if os(iOS)
        let eligibleStarted = ContinuousClock.now
        if let eligibleIDs = Self.eligibleAssetIDs() {
            records = records.filter { eligibleIDs.contains($0.localIdentifier) }
        }
        eligibleMs = Self.elapsedMs(since: eligibleStarted)
        #endif

        guard !records.isEmpty else { return nil }

        // Mode rclone copy batché : on prépare un dossier temporaire qui
        // reproduit l'arborescence remote cible (sans le préfixe
        // baseFolder), on y déplace les fichiers exportés de PhotoKit,
        // puis on lance UN seul `sync/copy /tmp/batchDir remote:baseFolder`
        // équivalent à `rclone copy /tmp/batchDir remote:baseFolder` en
        // CLI — rclone gère lui-même la parallélisation, le retry et le
        // skip-if-already-uploaded.
        let batchDir = FileManager.default.temporaryDirectory
            .appending(path: "rclonePhotoBatch-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: batchDir, withIntermediateDirectories: true)
        // NB : pas de `defer { removeItem(batchDir) }` ici — c'est
        // uploadPreparedBatch qui supprime le batchDir une fois le
        // sync/copy terminé. Sans ce changement, le batch était
        // supprimé dès que prepareBatch retournait → erreur rclone
        // « directory not found » au moment du sync/copy.
        var batchedRecords: [(asset: PhotoSyncAsset, remotePaths: [String], bytes: Int64)] = []

        var enqueuedCount = 0
        // Compteurs de perf pour le log de synthèse `[batch-perf]`.
        var exportTotalMs = 0
        var exportCount = 0
        var hashTotalMs = 0
        var hashCount = 0
        var moveTotalMs = 0
        var saveTotalMs = 0
        var dedupSkips = 0

        // Phase 1 : marque tous les records .exporting d'un coup + 1 seul
        // save SwiftData (vs 1 par record auparavant).
        await LogService.shared.log(
            .info,
            category: "batch-perf",
            message: "\(Self.perfTs()) phase1 mark .exporting (\(records.count) records)"
        )
        for record in records {
            try Task.checkCancellation()
            record.status = .exporting
            record.lastAttemptAt = .now
            record.lastError = nil
        }
        let phase1Save = ContinuousClock.now
        try? modelContext.save()
        saveTotalMs += Self.elapsedMs(since: phase1Save)
        await LogService.shared.log(
            .info,
            category: "batch-perf",
            message: "\(Self.perfTs()) phase1 done (save=\(Self.elapsedMs(since: phase1Save))ms)"
        )

        // Phase 2 : exports PhotoKit en PARALLÈLE (concurrence adaptative).
        // 4 si idle, 2 si un upload sync/copy tourne en concurrence
        // (sinon les exports se mettent à throttler à 1-17s/photo à cause
        // de la saturation CPU+réseau SFTP).
        let concurrencyLimit = exportConcurrencyForCurrentLoad
        let identifiers = records.map { $0.localIdentifier }
        let exportsStarted = ContinuousClock.now
        await LogService.shared.log(
            .info,
            category: "batch-perf",
            message: "\(Self.perfTs()) phase2 exports start (limit=\(concurrencyLimit), n=\(identifiers.count))"
        )
        let exportResults: [String: Result<[ExportedResource], Error>] = await withTaskGroup(
            of: (String, Result<[ExportedResource], Error>, Int).self
        ) { group in
            var result: [String: Result<[ExportedResource], Error>] = [:]
            var nextIndex = 0
            let totalCount = identifiers.count
            // Amorce les `concurrencyLimit` premières tâches.
            while nextIndex < min(concurrencyLimit, totalCount) {
                let id = identifiers[nextIndex]
                let idx = nextIndex
                await LogService.shared.log(
                    .debug,
                    category: "batch-perf",
                    message: "\(Self.perfTs()) export #\(idx + 1)/\(totalCount) start id=\(id.suffix(10))"
                )
                group.addTask {
                    let started = ContinuousClock.now
                    do {
                        let exports = try await Self.exportResourcesDetached(forLocalIdentifier: id)
                        return (id, .success(exports), Self.elapsedMs(since: started))
                    } catch {
                        return (id, .failure(error), Self.elapsedMs(since: started))
                    }
                }
                nextIndex += 1
            }
            // À chaque task qui termine, démarre la suivante (sliding window).
            while let (id, res, ms) = await group.next() {
                result[id] = res
                let doneIdx = result.count
                await LogService.shared.log(
                    .debug,
                    category: "batch-perf",
                    message: "\(Self.perfTs()) export done \(doneIdx)/\(totalCount) in \(ms)ms id=\(id.suffix(10))"
                )
                if nextIndex < totalCount {
                    let nextID = identifiers[nextIndex]
                    let idx = nextIndex
                    await LogService.shared.log(
                        .debug,
                        category: "batch-perf",
                        message: "\(Self.perfTs()) export #\(idx + 1)/\(totalCount) start id=\(nextID.suffix(10))"
                    )
                    group.addTask {
                        let started = ContinuousClock.now
                        do {
                            let exports = try await Self.exportResourcesDetached(forLocalIdentifier: nextID)
                            return (nextID, .success(exports), Self.elapsedMs(since: started))
                        } catch {
                            return (nextID, .failure(error), Self.elapsedMs(since: started))
                        }
                    }
                    nextIndex += 1
                }
            }
            return result
        }
        exportTotalMs = Self.elapsedMs(since: exportsStarted)
        exportCount = identifiers.count
        await LogService.shared.log(
            .info,
            category: "batch-perf",
            message: "\(Self.perfTs()) phase2 done in \(exportTotalMs)ms (wall clock, parallèle ×\(concurrencyLimit))"
        )

        // Phase 3 : pour chaque record (séquentiel, MainActor), récupère
        // son export, hash si besoin, dedup, move dans batchDir, marque
        // .enqueued. SwiftData ne supporte pas la concurrence ; cette
        // phase reste séquentielle. Pas besoin de save par record — on
        // sauvegarde une seule fois à la fin.
        let phase3Started = ContinuousClock.now
        await LogService.shared.log(
            .info,
            category: "batch-perf",
            message: "\(Self.perfTs()) phase3 hash+dedup+move start"
        )
        for record in records {
            try Task.checkCancellation()
            let localIdentifier = record.localIdentifier
            let creationDate = record.creationDate

            guard let exportResult = exportResults[localIdentifier] else {
                record.status = .failed
                record.retryCount += 1
                record.lastError = "Export PhotoKit manquant (batch)"
                continue
            }

            let exports: [ExportedResource]
            switch exportResult {
            case .success(let e):
                exports = e
            case .failure(let error):
                record.status = .failed
                record.retryCount += 1
                record.lastError = error.localizedDescription
                await LogService.shared.log(.error, category: "photos", message: "Asset \(localIdentifier) non enqueue : \(error.localizedDescription)")
                continue
            }

            do {
                var remotePaths: [String] = []
                var bytes: Int64 = 0
                if let primary = exports.first, record.localHash == nil {
                    let hashStarted = ContinuousClock.now
                    if let hash = try? await Self.computeMD5(url: primary.url) {
                        record.localHash = hash
                    }
                    hashTotalMs += Self.elapsedMs(since: hashStarted)
                    hashCount += 1
                }
                if let hash = record.localHash, !hash.isEmpty,
                   let duplicate = findUploadedDuplicate(hash: hash, excluding: localIdentifier) {
                    record.status = .skipped
                    record.remotePaths = duplicate.remotePaths
                    record.byteCount = duplicate.byteCount
                    record.completedAt = .now
                    record.lastError = nil
                    dedupSkips += 1
                    await LogService.shared.log(.info, category: "photos", message: "Doublon ignoré (\(hash.prefix(8))) : \(localIdentifier)")
                    continue
                }
                for exported in exports {
                    let remotePath = Self.remotePathForAsset(
                        baseFolder: folder,
                        localIdentifier: localIdentifier,
                        creationDate: creationDate,
                        filename: exported.url.lastPathComponent
                    )
                    let relPath: String
                    if remotePath.hasPrefix(folder + "/") {
                        relPath = String(remotePath.dropFirst(folder.count + 1))
                    } else {
                        relPath = remotePath
                    }
                    let localDest = batchDir.appending(path: relPath)
                    try FileManager.default.createDirectory(
                        at: localDest.deletingLastPathComponent(),
                        withIntermediateDirectories: true
                    )
                    if FileManager.default.fileExists(atPath: localDest.path) {
                        try? FileManager.default.removeItem(at: localDest)
                    }
                    let moveStarted = ContinuousClock.now
                    try FileManager.default.moveItem(at: exported.url, to: localDest)
                    moveTotalMs += Self.elapsedMs(since: moveStarted)
                    remotePaths.append(remotePath)
                    bytes += exported.bytes
                }
                record.remotePaths = remotePaths
                record.byteCount = bytes
                record.status = .enqueued
                record.lastError = nil
                batchedRecords.append((record, remotePaths, bytes))
                enqueuedCount += 1
            } catch {
                record.status = .failed
                record.retryCount += 1
                record.lastError = error.localizedDescription
                await LogService.shared.log(.error, category: "photos", message: "Asset \(localIdentifier) non enqueue : \(error.localizedDescription)")
            }
        }

        // 1 save final pour toutes les transitions .enqueued / .skipped /
        // .failed faites en phase 3 (vs 3 saves × 50 records = 150 saves).
        let phase3Save = ContinuousClock.now
        try? modelContext.save()
        saveTotalMs += Self.elapsedMs(since: phase3Save)
        let phase3Ms = Self.elapsedMs(since: phase3Started)
        await LogService.shared.log(
            .info,
            category: "batch-perf",
            message: "\(Self.perfTs()) phase3 done in \(phase3Ms)ms (hash=\(hashTotalMs) [n=\(hashCount)], moves=\(moveTotalMs), final_save=\(Self.elapsedMs(since: phase3Save))ms)"
        )

        // Log de synthèse : où est passé le temps de préparation ?
        let totalPrepMs = Self.elapsedMs(since: prepStarted)
        let exportAvg = exportCount > 0 ? exportTotalMs / exportCount : 0
        let hashAvg = hashCount > 0 ? hashTotalMs / hashCount : 0
        await LogService.shared.log(
            .info,
            category: "batch-perf",
            message: "\(Self.perfTs()) T_prep=\(totalPrepMs)ms (inter_batch=\(interBatchMs), fetch_pending=\(fetchPendingMs), fetch_failed=\(fetchFailedMs), eligible=\(eligibleMs), exports=\(exportTotalMs) [avg=\(exportAvg)/n=\(exportCount)], hashes=\(hashTotalMs) [n=\(hashCount), avg=\(hashAvg)], moves=\(moveTotalMs), saves=\(saveTotalMs), dedup_skips=\(dedupSkips)) → \(batchedRecords.count) photos prêtes"
        )

        guard !batchedRecords.isEmpty else {
            try? FileManager.default.removeItem(at: batchDir)
            return nil
        }

        return PreparedBatch(
            batchDir: batchDir,
            records: batchedRecords,
            totalBytes: batchedRecords.reduce(Int64(0)) { $0 + $1.bytes },
            enqueuedCount: enqueuedCount
        )
    }

    /// Représente un batch prêt à uploader : tous les fichiers sont déjà
    /// exportés depuis PhotoKit, hashés, dédupliqués et placés dans
    /// `batchDir`. Le sync/copy reste à lancer.
    struct PreparedBatch {
        let batchDir: URL
        let records: [(asset: PhotoSyncAsset, remotePaths: [String], bytes: Int64)]
        let totalBytes: Int64
        let enqueuedCount: Int
    }

    /// Lance le sync/copy d'un batch déjà préparé puis marque les records
    /// completed (ou failed en cas d'erreur) et nettoie le batchDir.
    /// Set isUploadingBatch=true pendant toute la durée pour que la prep
    /// concurrente (pipeline) réduise sa concurrence d'exports PhotoKit
    /// et n'étouffe pas le SFTP.
    private func uploadPreparedBatch(
        _ batch: PreparedBatch,
        remote: String,
        folder: String
    ) async {
        defer {
            try? FileManager.default.removeItem(at: batch.batchDir)
            isUploadingBatch = false
        }
        isUploadingBatch = true

        await LogService.shared.log(
            .info,
            category: "photos",
            message: "rclone copy → \(remote):\(folder) (\(batch.records.count) photos, \(ByteCountFormatter.string(fromByteCount: batch.totalBytes, countStyle: .file)))"
        )

        do {
            let jobID = try await TransferService.shared.copyDirAsync(
                srcFs: batch.batchDir.path,
                dstFs: "\(remote):\(folder)",
                createEmptySrcDirs: false
            )
            try await waitForRcloneJob(jobID: jobID)
            for entry in batch.records {
                entry.asset.status = .completed
                entry.asset.completedAt = .now
                entry.asset.lastError = nil
            }
            try? modelContext?.save()
            uploadedThisSession += batch.records.count
            let progressStr = sessionInitialPending > 0
                ? " (session: \(uploadedThisSession)/\(sessionInitialPending))"
                : ""
            await LogService.shared.log(
                .info,
                category: "photos",
                message: "rclone copy ok : \(batch.records.count) photos uploadées\(progressStr)"
            )
        } catch {
            for entry in batch.records {
                entry.asset.status = .failed
                entry.asset.retryCount += 1
                entry.asset.lastError = error.localizedDescription
            }
            try? modelContext?.save()
            await LogService.shared.log(
                .error,
                category: "photos",
                message: "rclone copy échoué : \(error.localizedDescription) (\(batch.records.count) photos repassent en failed)"
            )
        }
    }

    /// Buffer de batchs préparés en attente d'upload. Backpressure : le
    /// producer s'arrête tant que `pipelineBuffer.count >= maxPipelineBuffer`.
    /// 2 batchs en avance = ~20 photos pré-exportées, soit ~30s de
    /// matière à uploader si la prep ralentit ou si PhotoKit bloque.
    private var pipelineBuffer: [PreparedBatch] = []
    private var pipelineProducerDone = false
    private static let maxPipelineBuffer = 2

    /// Orchestrateur pipeline rclone-like streaming. Producer prépare en
    /// continu jusqu'à `maxPipelineBuffer` batchs en avance. Consumer
    /// pop dès qu'un batch est dispo et le donne au sync/copy. Aucun
    /// gap entre 2 batchs : dès que l'upload N finit, le batch N+1
    /// est déjà prêt dans le buffer.
    ///
    /// Concurrence d'exports adaptative côté prepareBatch (cf.
    /// exportConcurrencyForCurrentLoad) : 2 simultanés quand un upload
    /// tourne, 4 quand idle.
    private func runPipeline(
        remote: String,
        folder: String,
        requestedLimit: Int,
        includeFailedRetries: Bool
    ) async -> Int {
        // Reset compteurs de session pour la bannière X/Y.
        let pendingAtStart = (try? pendingWorkCount(includeFailedRetries: includeFailedRetries)) ?? 0
        resetSessionCounters(pendingNow: pendingAtStart)
        await LogService.shared.log(
            .info,
            category: "photos",
            message: "PhotoSync session start : \(pendingAtStart) photos en attente"
        )

        pipelineBuffer = []
        pipelineProducerDone = false
        var totalEnqueued = 0

        // Producer : prepare en continu jusqu'au buffer plein, puis se
        // met en pause via backpressure.
        let producer = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                // Backpressure : si buffer plein, attendre qu'une slot
                // se libère.
                while self.pipelineBuffer.count >= Self.maxPipelineBuffer {
                    try? await Task.sleep(for: .milliseconds(150))
                    if Task.isCancelled { return }
                }
                do {
                    guard let batch = try await self.prepareBatch(
                        remote: remote,
                        folder: folder,
                        requestedLimit: requestedLimit,
                        includeFailedRetries: includeFailedRetries
                    ) else {
                        self.pipelineProducerDone = true
                        return
                    }
                    self.pipelineBuffer.append(batch)
                } catch {
                    await LogService.shared.log(
                        .error,
                        category: "photos",
                        message: "prepareBatch (producer) échoué : \(error.localizedDescription)"
                    )
                    self.pipelineProducerDone = true
                    return
                }
            }
        }

        // Consumer : pop du buffer et upload séquentiellement (on n'a
        // qu'1 sync/copy à la fois — rclone parallélise déjà ses
        // transferts internes).
        while true {
            while pipelineBuffer.isEmpty {
                if pipelineProducerDone {
                    await producer.value
                    return totalEnqueued
                }
                try? await Task.sleep(for: .milliseconds(150))
            }
            let batch = pipelineBuffer.removeFirst()
            totalEnqueued += batch.enqueuedCount
            await uploadPreparedBatch(batch, remote: remote, folder: folder)
        }
    }

    /// Boucle d'attente sur un job rclone asynchrone (`sync/copy`,
    /// `sync/move`…). Throw si le job échoue ou si la Task est annulée.
    /// À chaque tick, met à jour `liveBatchProgress` à partir de
    /// `core/stats` pour que la UI affiche un compteur live.
    private func waitForRcloneJob(jobID: Int) async throws {
        defer { liveBatchProgress = nil }
        while true {
            try Task.checkCancellation()
            try await Task.sleep(nanoseconds: 500_000_000)
            // Met à jour la progression LIVE avant de vérifier le statut
            // — si le job vient juste de finir, on garde une dernière
            // valeur cohérente jusqu'au prochain snapshot.
            if let stats = try? await TransferService.shared.coreStats() {
                let primary = stats.transferring.first
                liveBatchProgress = PhotoBatchLiveProgress(
                    bytesTransferred: stats.transferredBytes,
                    bytesTotal: stats.totalBytes,
                    speedBytesPerSec: stats.globalSpeed,
                    etaSeconds: primary?.eta,
                    currentFilename: primary?.name
                )
            }
            let status = try await TransferService.shared.jobStatus(jobID: jobID)
            if status.finished {
                if status.success {
                    // Marque la fin du batch pour mesurer le délai inter-batch
                    // côté enqueuePending suivant.
                    lastBatchEndedAt = ContinuousClock.now
                    await LogService.shared.log(
                        .info,
                        category: "batch-perf",
                        message: "\(Self.perfTs()) batch fini, début préparation du suivant"
                    )
                    return
                }
                throw NSError(
                    domain: "rclone.job",
                    code: jobID,
                    userInfo: [NSLocalizedDescriptionKey: status.error ?? "Job rclone échoué"]
                )
            }
        }
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
            // Délai court (200ms) entre deux batches : on enchaîne vite
            // pour drainer le backlog rapidement. Suffisant pour que
            // SwiftUI place un cycle de rendu et traite un éventuel tap.
            try? await Task.sleep(for: .milliseconds(200))
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
        let (rollingBps, rollingEta) = throughputMetrics(
            totalBytes: counts.totalBytes,
            transferredBytes: counts.transferredBytes
        )
        // Quand un batch rclone copy est en vol, on remplace les compteurs
        // basés sur l'état persisté (qui ne bougent qu'à la fin du batch
        // entier) par la progression LIVE issue de core/stats.
        let live = liveBatchProgress
        let transferred = live.map { counts.transferredBytes + $0.bytesTransferred } ?? counts.transferredBytes
        let total = live.map { max(counts.totalBytes, counts.transferredBytes + $0.bytesTotal) } ?? counts.totalBytes
        let bps = live.map { $0.speedBytesPerSec } ?? rollingBps
        let eta: TimeInterval?
        if let etaSeconds = live?.etaSeconds, etaSeconds > 0 {
            eta = TimeInterval(etaSeconds)
        } else {
            eta = rollingEta
        }
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
            totalBytes: total,
            transferredBytes: transferred,
            averageBytesPerSecond: bps,
            estimatedTimeRemaining: eta,
            pausedByUser: isPausedByUser,
            sessionUploaded: uploadedThisSession,
            sessionInitialPending: sessionInitialPending
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
