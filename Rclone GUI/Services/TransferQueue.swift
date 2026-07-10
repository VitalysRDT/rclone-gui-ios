//
//  TransferQueue.swift
//  Rclone GUI — Services
//
//  MainActor orchestrator. Persists Transfer rows via SwiftData,
//  dispatches the rclone async jobs, and polls progress until done.
//
//  Wired up from `Rclone_GUIApp` via `TransferQueue.shared.attach(modelContext:)`
//  on first appearance of the root view.
//
//  Phase C scope:
//    - download / upload / delete / move / rename
//    - polling loop (~500 ms) merging job/status + core/stats
//    - cold-start replay (resume interrupted transfers)
//
//  Phase C non-scope (deferred to D/E):
//    - URLSession-direct path for HTTP backends (S3/R2/Bunny)
//    - Live Activities
//    - Bandwidth limiting
//

import Foundation
import SwiftData

@MainActor
public final class TransferQueue {
    public static let shared = TransferQueue()

    private init() {}

    // MARK: - State

    private var modelContext: ModelContext?
    private var pollTasks: [Int: Task<Void, Never>] = [:]
    private var statsTask: Task<Void, Never>?
    /// Anti-double-fire du log debug `📈 core/stats …` : on ne veut qu'une ligne
    /// par tranche de 5 s même si tickStats() est appelé plusieurs fois par
    /// seconde par startStatsPolling().
    private var lastCoreStatsLog: Int = 0
    /// Scope security-scoped iCloud Drive / picker externe par jobID.
    /// DOIT rester vivant pendant toute la durée du job rclone (la goroutine
    /// librclone écrit hors-sandbox via `os.Open` APRÈS le retour de
    /// `sync/copy`). Libéré par `pollLoop` quand `finished=true` (ou sur
    /// erreur / annulation). Sans ce maintien, l'écriture échoue silencieusement
    /// en permission denied et le job reste bloqué à 0 octet pour toujours.
    private var activeSecurityScopes: [Int: (url: URL, didStart: Bool)] = [:]
    /// Phase E — re-enqueue auto borné. Compteur par signature logique de
    /// transfert (remote+chemin+dest) pour couvrir les coupures réseau
    /// transitoires sans boucler sur des erreurs permanentes.
    private var autoRetryCounts: [String: Int] = [:]
    /// Tasks actifs des downloads de dossier via BridgeFolderDownloader,
    /// indexés par transferID. Permettent pause/annulation : `cancel()`
    /// stoppe le TaskGroup interne, les URLSession tasks en vol sont
    /// invalidées, les fichiers finis restent sur disque (skip-existing
    /// au prochain run).
    private var bridgeFolderTasks: [String: Task<Void, Never>] = [:]
    private let maxAutoRetries = 2

    // MARK: - Mode Auto (gestion automatique de la concurrence)

    /// Dernière décision du mode Auto (voir AutoTransferPolicy). Rafraîchie
    /// par refreshAutoPolicy() sur les évènements réseau/énergie déjà câblés,
    /// consommée par `maxConcurrent` et affichée dans Réglages → Performance.
    public private(set) var currentAutoDecision = AutoTransferPolicy.Decision(
        queueConcurrency: 3, bridgeConcurrency: 4, reason: .nominal
    )

    /// Mode Auto actif ? Défaut ON tant que l'utilisateur n'a pas touché au
    /// toggle ; OFF → les réglages manuels reprennent la main à l'identique.
    public var isAutoModeEnabled: Bool {
        AutoTransferPolicy.isAutoModeEnabled(UserDefaults.standard)
    }

    /// Échantillonne les signaux réseau/énergie et met à jour la décision du
    /// mode Auto. Appelé à l'attach, sur changement de lien réseau, sur
    /// changement thermique/mode éco, et au toggle dans les réglages.
    /// Réduction NON préemptive : les transferts en vol terminent, seuls les
    /// prochains dispatchs voient moins de slots — on ne relance donc le
    /// scheduler que quand la concurrence AUGMENTE.
    public func refreshAutoPolicy() {
        guard isAutoModeEnabled else { return }
        // snapshot : une seule prise de lock — trois lectures séparées
        // pourraient chevaucher une bascule de path (état déchiré).
        let reach = NetworkReachability.shared.snapshot
        let info = ProcessInfo.processInfo
        let decision = AutoTransferPolicy.decide(AutoTransferPolicy.Inputs(
            isOnline: reach.online,
            isExpensive: reach.expensive,
            isConstrained: reach.constrained,
            thermal: info.thermalState,
            lowPower: info.isLowPowerModeEnabled
        ))
        guard decision != currentAutoDecision else { return }
        let previous = currentAutoDecision
        currentAutoDecision = decision
        Task {
            await LogService.shared.log(.info, category: "transfer",
                message: "🤖 Mode Auto : concurrence \(decision.queueConcurrency) (\(decision.reason.rawValue))")
        }
        if decision.queueConcurrency > previous.queueConcurrency {
            scheduleNext()
        }
    }

    // MARK: - Security-scoped bookmark helpers

    /// Capture un bookmark security-scoped pour une URL issue de
    /// UIDocumentPicker (iCloud Drive, On My iPhone, picker externe). Renvoie
    /// nil pour les URLs du sandbox app (Documents/, Caches/) où la permission
    /// est implicite — `bookmarkData()` retourne alors nil sans erreur.
    /// L'URL doit être accessible (scope déjà démarré par l'appelant, sinon
    /// `bookmarkData` peut renvoyer nil). On ne capture que pour les downloads
    /// de DOSSIER (sync/copy est asynchrone via librclone goroutine et peut
    /// tourner après la désallocation de l'URL caller — voir `relaunch`).
    static func captureSecurityScopedBookmark(for url: URL) -> Data? {
        // Sur iOS, un bookmark créé depuis une URL issue de UIDocumentPicker
        // est implicitement security-scoped : la résolution via
        // URL(resolvingBookmarkData:) suivie de startAccessingSecurityScopedResource()
        // rouvre l'accès hors-sandbox. Pas de flag spécial à passer sur iOS
        // (.withSecurityScope est macOS-only). On capture le bookmark tel quel
        // et le scope sera rétabli dans resolveSecurityScopedBookmark().
        do {
            let data = try url.bookmarkData(
                options: [],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            return data
        } catch {
            // URL non-security-scoped (sandbox app) ou scope non démarré →
            // fallback transparent sur destinationURL.path dans relaunch().
            return nil
        }
    }

    /// Résout un bookmark security-scoped et démarre le scope. Renvoie
    /// l'URL résolue (à utiliser comme `dstFs`) si succès, nil sinon.
    /// Le caller DOIT appeler `url.stopAccessingSecurityScopedResource()` après
    /// la fin du job rclone (cleanup dans `pollLoop`).
    static func resolveSecurityScopedBookmark(_ data: Data) -> (url: URL, didStart: Bool)? {
        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: data,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            let didStart = url.startAccessingSecurityScopedResource()
            if isStale {
                // Le bookmark a expiré (ex : utilisateur a déplacé le dossier
                // hors iCloud). On loggue un warning et on tente quand même —
                // iOS peut encore autoriser l'accès si l'URL reste valide.
            }
            return (url, didStart)
        } catch {
            return nil
        }
    }

    // MARK: - Setup

    /// Attach the SwiftData model context. Idempotent; safe to call multiple
    /// times (e.g. on every scene activation).
    public func attach(modelContext: ModelContext) {
        guard self.modelContext !== modelContext else { return }
        self.modelContext = modelContext
        Task { await replayInterrupted() }
        startStatsPolling()
        startEnergyObservers()
        migrateAutoModeDefaultIfNeeded()
        refreshAutoPolicy()
    }

    /// Défaut ON du mode Auto réservé aux installations SANS réglage manuel
    /// préalable : un utilisateur existant qui avait explicitement réglé
    /// « Transferts simultanés » garde son comportement (Auto OFF, activable
    /// à tout moment dans Réglages → Performance). Écrit la clé une seule
    /// fois — le choix de l'utilisateur reste ensuite souverain.
    private func migrateAutoModeDefaultIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: AutoTransferPolicy.autoModeEnabledKey) == nil else { return }
        if defaults.object(forKey: Self.maxConcurrentKey) != nil {
            defaults.set(false, forKey: AutoTransferPolicy.autoModeEnabledKey)
        }
    }

    // MARK: - Enqueue API

    public func enqueueDownload(remote: String, path: String, to localURL: URL) async throws {
        let parent = localURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)

        let transfer = Transfer(
            kind: .download,
            sourceRemote: remote,
            sourcePath: path,
            destinationPath: localURL.path,
            displayName: localURL.lastPathComponent,
            sourceKind: .remote
        )
        // Le dispatch effectif (copyfile) est fait par le scheduler via relaunch().
        enqueueAndSchedule(transfer)
    }

    @discardableResult
    public func enqueueDownloadBatch(
        remote: String,
        entries: [RemoteEntryDTO],
        to directory: URL,
        conflictPolicy: LocalConflictPolicy
    ) async throws -> TransferBatch {
        let batch = TransferBatch(
            title: entries.count == 1 ? "Téléchargement \(entries[0].name)" : "Téléchargement de \(entries.count) éléments",
            kind: .download,
            totalItems: entries.count
        )
        batch.status = .running
        modelContext?.insert(batch)
        try modelContext?.save()

        for entry in entries {
            try await enqueueDownload(
                remote: remote,
                entry: entry,
                to: directory,
                conflictPolicy: conflictPolicy,
                batchID: batch.id
            )
        }
        return batch
    }

    public func enqueueDownload(
        remote: String,
        entry: RemoteEntryDTO,
        to directory: URL,
        conflictPolicy: LocalConflictPolicy = .keepBoth,
        batchID: String? = nil
    ) async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let requestedURL = directory.appending(path: entry.name, directoryHint: entry.isDirectory ? .isDirectory : .notDirectory)
        guard let destinationURL = try LocalFileConflictResolver.destination(for: requestedURL, policy: conflictPolicy) else {
            await LogService.shared.log(.info, category: "transfer", message: "Téléchargement ignoré : \(remote):\(entry.pathInRemote)")
            return
        }

        if entry.isDirectory {
            try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)
            // Pré-calcul de la taille du dossier via operations/size pour avoir
            // un bytesTotal déterminé dès l'enqueue → la barre de progression
            // s'affiche immédiatement. Échec non bloquant : 0 → barre indéterminée.
            var folderBytesTotal: Int64 = 0
            do {
                let sizing = try await RemoteService.shared.size(remote: remote, path: entry.pathInRemote)
                folderBytesTotal = max(sizing.bytes, 0)
            } catch {
                await LogService.shared.log(
                    .info,
                    category: "transfer",
                    message: "operations/size échec pour \(remote):\(entry.pathInRemote) : \(error.localizedDescription) — progression dossier indéterminée"
                )
            }
            let transfer = Transfer(
                kind: .download,
                sourceRemote: remote,
                sourcePath: entry.pathInRemote,
                destinationPath: destinationURL.path,
                batchID: batchID,
                relativePath: entry.name,
                displayName: entry.name,
                sourceKind: .remote,
                bytesTotal: folderBytesTotal
            )
            transfer.isDirectoryTransfer = true
            // Persistance du scope security-scoped (iCloud Drive, On My iPhone,
            // Dropbox picker, etc.) : sans ça, l'URL du dossier destination est
            // désallouée dès la fin de cette Task, iOS retire le scope, et la
            // goroutine librclone écrit hors-sandbox → permission denied
            // silencieux, job bloqué à 0 octet, jamais de "terminé"/"échoué".
            // Le bookmark .withSecurityScope survit aux redémarrages et est
            // résolu dans `relaunch` au moment du job via
            // startAccessingSecurityScopedResource(). Pour les chemins du
            // sandbox app (Documents/, Caches/), bookmarkData() ne capture rien
            // et le champ reste nil → fallback transparent sur destinationURL.path.
            transfer.destinationSecurityBookmark = Self.captureSecurityScopedBookmark(for: directory)
            enqueueAndSchedule(transfer)
        } else {
            let transfer = Transfer(
                kind: .download,
                sourceRemote: remote,
                sourcePath: entry.pathInRemote,
                destinationPath: destinationURL.path,
                batchID: batchID,
                relativePath: entry.name,
                displayName: entry.name,
                sourceKind: .remote,
                bytesTotal: entry.size
            )
            transfer.isDirectoryTransfer = false
            enqueueAndSchedule(transfer)
        }
    }

    public func enqueueUpload(
        local: URL,
        remote: String,
        path: String,
        batchID: String? = nil,
        relativePath: String? = nil,
        sourceKind: TransferSourceKind = .localFile
    ) async throws {
        let transfer = Transfer(
            kind: .upload,
            sourcePath: local.path,
            destinationRemote: remote,
            destinationPath: path,
            batchID: batchID,
            relativePath: relativePath,
            displayName: local.lastPathComponent,
            sourceKind: sourceKind,
            bytesTotal: fileSize(at: local)
        )
        enqueueAndSchedule(transfer)
    }

    @discardableResult
    public func enqueueUploadBatch(
        localURLs: [URL],
        remote: String,
        destinationFolder: String,
        sourceKind: TransferSourceKind = .localFile
    ) async throws -> TransferBatch {
        let batch = TransferBatch(
            title: localURLs.count == 1 ? "Upload \(localURLs[0].lastPathComponent)" : "Upload de \(localURLs.count) éléments",
            kind: .upload,
            totalItems: localURLs.count
        )
        batch.status = .running
        modelContext?.insert(batch)
        try modelContext?.save()

        for localURL in localURLs {
            let didStart = localURL.startAccessingSecurityScopedResource()
            defer { if didStart { localURL.stopAccessingSecurityScopedResource() } }

            if isDirectory(localURL) {
                let dstPath = joinedRemotePath(destinationFolder, localURL.lastPathComponent)
                try await enqueueUploadFolder(
                    localFolder: localURL,
                    remote: remote,
                    destinationFolder: dstPath,
                    batchID: batch.id,
                    sourceKind: sourceKind
                )
            } else {
                let dstPath = joinedRemotePath(destinationFolder, localURL.lastPathComponent)
                try await enqueueUpload(
                    local: localURL,
                    remote: remote,
                    path: dstPath,
                    batchID: batch.id,
                    relativePath: localURL.lastPathComponent,
                    sourceKind: sourceKind
                )
            }
        }
        return batch
    }

    public func enqueueUploadFolder(
        localFolder: URL,
        remote: String,
        destinationFolder: String,
        batchID: String? = nil,
        sourceKind: TransferSourceKind = .localFolder
    ) async throws {
        // Calcul de taille du dossier HORS main thread (peut parcourir des
        // milliers de fichiers). Sans ça, le tap « Upload » d'un gros dossier
        // figeait l'UI le temps de l'énumération récursive.
        let bytesTotal = await Task.detached(priority: .utility) {
            TransferQueue.directorySize(at: localFolder)
        }.value
        let transfer = Transfer(
            kind: .upload,
            sourcePath: localFolder.path,
            destinationRemote: remote,
            destinationPath: destinationFolder,
            batchID: batchID,
            relativePath: localFolder.lastPathComponent,
            displayName: localFolder.lastPathComponent,
            sourceKind: sourceKind,
            bytesTotal: bytesTotal
        )
        enqueueAndSchedule(transfer)
    }

    public func enqueueDelete(remote: String, path: String, isDirectory: Bool) async throws {
        let transfer = Transfer(
            kind: .delete,
            sourceRemote: remote,
            sourcePath: path,
            destinationPath: ""
        )
        transfer.status = .running
        modelContext?.insert(transfer)
        try modelContext?.save()

        let jobID: Int
        if isDirectory {
            jobID = try await TransferService.shared.purgeAsync(remote: remote, path: path)
        } else {
            jobID = try await TransferService.shared.deleteFileAsync(remote: remote, path: path)
        }
        transfer.jobID = jobID
        try modelContext?.save()
        startPolling(transfer)
    }

    /// Soft-delete: move the item to the per-remote trash folder via TrashService.
    /// The original path is recorded so the user can restore it within the
    /// retention window (30 days by default).
    ///
    /// `sizeBytes` is best-effort metadata for the trash UI. Pass -1 if unknown.
    public func enqueueTrash(
        remote: String,
        path: String,
        name: String,
        isDirectory: Bool,
        sizeBytes: Int64
    ) async throws {
        let transfer = Transfer(
            kind: .delete,
            sourceRemote: remote,
            sourcePath: path,
            destinationPath: "",
            displayName: "Corbeille — \(name)"
        )
        transfer.status = .running
        modelContext?.insert(transfer)
        try modelContext?.save()

        do {
            _ = try await TrashService.shared.moveToTrash(
                remote: remote,
                path: path,
                name: name,
                isDirectory: isDirectory,
                sizeBytes: sizeBytes
            )
            transfer.status = .completed
            transfer.finishedAt = .now
            try modelContext?.save()
        } catch {
            transfer.status = .failed
            transfer.lastError = error.localizedDescription
            transfer.finishedAt = .now
            try? modelContext?.save()
            throw error
        }
    }

    public func enqueueRename(remote: String, oldPath: String, newPath: String) async throws {
        let transfer = Transfer(
            kind: .move,
            sourceRemote: remote,
            sourcePath: oldPath,
            destinationRemote: remote,
            destinationPath: newPath
        )
        transfer.status = .running
        modelContext?.insert(transfer)
        try modelContext?.save()

        let jobID = try await TransferService.shared.renameAsync(remote: remote, oldPath: oldPath, newPath: newPath)
        transfer.jobID = jobID
        try modelContext?.save()
        startPolling(transfer)
    }

    public func enqueueMove(srcRemote: String, srcPath: String, dstRemote: String, dstPath: String) async throws {
        let transfer = Transfer(
            kind: .move,
            sourceRemote: srcRemote,
            sourcePath: srcPath,
            destinationRemote: dstRemote,
            destinationPath: dstPath
        )
        transfer.status = .running
        modelContext?.insert(transfer)
        try modelContext?.save()

        let jobID = try await TransferService.shared.moveFileAsync(
            srcFs: "\(srcRemote):",
            srcPath: srcPath,
            dstFs: "\(dstRemote):",
            dstPath: dstPath
        )
        transfer.jobID = jobID
        try modelContext?.save()
        startPolling(transfer)
    }

    @discardableResult
    public func enqueueRemoteTransferBatch(
        kind: TransferKind,
        srcRemote: String,
        entries: [RemoteEntryDTO],
        dstRemote: String,
        dstFolder: String
    ) async throws -> TransferBatch {
        let batch = TransferBatch(
            title: remoteBatchTitle(kind: kind, count: entries.count),
            kind: kind,
            totalItems: entries.count
        )
        batch.status = .running
        modelContext?.insert(batch)
        try modelContext?.save()

        for entry in entries {
            try await enqueueRemoteTransfer(
                kind: kind,
                srcRemote: srcRemote,
                entry: entry,
                dstRemote: dstRemote,
                dstPath: joinedRemotePath(dstFolder, entry.name),
                batchID: batch.id
            )
        }

        return batch
    }

    public func enqueueRemoteTransfer(
        kind: TransferKind,
        srcRemote: String,
        entry: RemoteEntryDTO,
        dstRemote: String,
        dstPath: String,
        batchID: String? = nil
    ) async throws {
        precondition(kind == .copy || kind == .move || kind == .sync)

        let transfer = Transfer(
            kind: kind,
            sourceRemote: srcRemote,
            sourcePath: entry.pathInRemote,
            destinationRemote: dstRemote,
            destinationPath: dstPath,
            batchID: batchID,
            relativePath: entry.name,
            displayName: entry.name,
            sourceKind: .remote,
            bytesTotal: entry.size
        )
        transfer.isDirectoryTransfer = entry.isDirectory
        transfer.status = .running
        modelContext?.insert(transfer)
        try modelContext?.save()

        let jobID: Int
        switch (kind, entry.isDirectory) {
        case (.copy, false), (.sync, false):
            jobID = try await TransferService.shared.copyFileAsync(
                srcFs: "\(srcRemote):",
                srcPath: entry.pathInRemote,
                dstFs: "\(dstRemote):",
                dstPath: dstPath
            )
        case (.copy, true):
            jobID = try await TransferService.shared.copyDirAsync(
                srcFs: "\(srcRemote):\(entry.pathInRemote)",
                dstFs: "\(dstRemote):\(dstPath)"
            )
        case (.move, false):
            jobID = try await TransferService.shared.moveFileAsync(
                srcFs: "\(srcRemote):",
                srcPath: entry.pathInRemote,
                dstFs: "\(dstRemote):",
                dstPath: dstPath
            )
        case (.move, true):
            jobID = try await TransferService.shared.moveDirAsync(
                srcFs: "\(srcRemote):\(entry.pathInRemote)",
                dstFs: "\(dstRemote):\(dstPath)"
            )
        case (.sync, true):
            jobID = try await TransferService.shared.syncDirAsync(
                srcFs: "\(srcRemote):\(entry.pathInRemote)",
                dstFs: "\(dstRemote):\(dstPath)"
            )
        default:
            throw RcloneError.engineNotAvailable(String(localized: "Type de transfert remote non supporté : \(kind.rawValue)"))
        }

        transfer.jobID = jobID
        try modelContext?.save()
        startPolling(transfer)
    }

    public func cancel(_ transfer: Transfer) async {
        if let id = transfer.jobID {
            pollTasks[id]?.cancel()
            pollTasks[id] = nil
            try? await TransferService.shared.stopJob(jobID: id)
        }
        // Cancel aussi le Task du download de dossier si actif. La Task
        // détecte le cancel via Task.checkCancellation() dans copyFileAndWait
        // et sort proprement. Le dossier partiel reste sur disque
        // (skip-existing à la prochaine tentative).
        if let bridgeTask = bridgeFolderTasks[transfer.id] {
            bridgeTask.cancel()
            bridgeFolderTasks[transfer.id] = nil
        }
        transfer.jobID = nil
        transfer.status = .failed
        transfer.lastError = "Annulé par l'utilisateur"
        transfer.finishedAt = .now
        transfer.currentFilename = nil
        try? modelContext?.save()
        scheduleNext()   // libère un slot → démarre le suivant en file
    }

    // MARK: - Pause / reprise par transfert

    /// Met EN PAUSE un transfert précis (et lui seul). rclone ne sait pas
    /// suspendre un job en cours : on l'arrête proprement (`job/stop`) tout en
    /// conservant TOUTES les métadonnées du transfert, puis on passe la ligne
    /// en `.paused`. La reprise relancera l'opération via `relaunch(_:)`.
    /// Les copies de DOSSIER reprennent efficacement (rclone saute les fichiers
    /// déjà transférés) ; un fichier seul redémarre depuis le début.
    public func pause(_ transfer: Transfer) async {
        guard transfer.status == .running
            || transfer.status == .pending
            || transfer.status == .enqueued else { return }
        // Download de dossier : on annule la Task. downloadFolderViaFiles
        // détecte le cancel (Task.checkCancellation dans copyFileAndWait) et
        // sort proprement ; le fichier en cours sera re-téléchargé au skip.
        if let bridgeTask = bridgeFolderTasks[transfer.id] {
            bridgeTask.cancel()
            bridgeFolderTasks[transfer.id] = nil
            // On remet bytesTransferred/bytesTotal à leur dernière valeur
            // persistée (déjà le cas, mais on force un save pour éviter
            // qu'un callback asynchrone tardif n'écrase après le cancel).
            try? modelContext?.save()
        } else if let id = transfer.jobID {
            // Sync/copy historique
            pollTasks[id]?.cancel()
            pollTasks[id] = nil
            try? await TransferService.shared.stopJob(jobID: id)
        }
        transfer.jobID = nil
        transfer.status = .paused
        transfer.finishedAt = nil
        transfer.autoPaused = false   // pause manuelle par défaut (autoPauseActive remet true)
        transfer.currentFilename = nil
        try? modelContext?.save()
        await LogService.shared.log(
            .info,
            category: "transfer",
            message: "⏸️ Transfert en pause : \(transfer.sourcePath)"
        )
        scheduleNext()   // libère un slot → démarre le suivant en file
    }

    /// Reprend un transfert mis en pause : relance l'opération rclone sur le
    /// MÊME enregistrement (la ligne reste en place et reprend sa progression).
    public func resume(_ transfer: Transfer) async throws {
        guard transfer.status == .paused else { return }
        transfer.autoPaused = false
        transfer.lastError = nil
        transfer.finishedAt = nil
        // Download de dossier : relance immédiate via startClaimed →
        // downloadFolderViaFiles. Les fichiers déjà téléchargés sont skippés
        // (taille identique) ; le fileCount est recalculé par listRecursive.
        if transfer.kind == .download, (transfer.isDirectoryTransfer ?? false) {
            transfer.status = .running
            transfer.bytesTransferred = 0   // recalculé par la nouvelle snapshot
            transfer.bytesTotal = 0         // recalculé par la nouvelle snapshot
            transfer.fileCount = 0
            try? modelContext?.save()
            startClaimed(transfer)
            await LogService.shared.log(
                .info, category: "transfer",
                message: "▶️ Bridge folder repris : \(transfer.sourcePath)"
            )
            return
        }
        if isQueuedKind(transfer) {
            // Repasse par la file bornée (respecte la concurrence max + priorité).
            transfer.status = .enqueued
            try? modelContext?.save()
            scheduleNext()
            await LogService.shared.log(
                .info,
                category: "transfer",
                message: "▶️ Transfert remis en file : \(transfer.sourcePath)"
            )
        } else {
            // copy/move/sync : relance immédiate hors file bornée.
            transfer.status = .running
            try? modelContext?.save()
            do {
                let jobID = try await relaunch(transfer)
                transfer.jobID = jobID
                try? modelContext?.save()
                startPolling(transfer)
                await LogService.shared.log(
                    .info,
                    category: "transfer",
                    message: "▶️ Transfert repris : \(transfer.sourcePath)"
                )
            } catch {
                transfer.status = .paused
                transfer.lastError = error.localizedDescription
                try? modelContext?.save()
                throw error
            }
        }
    }

    /// Relance l'opération rclone d'un transfert et renvoie le nouveau jobID.
    /// Centralise le routage (fichier vs dossier ; download/upload/copy/move/
    /// sync) utilisé par la reprise (`resume`). Les uploads issus de Fichiers
    /// peuvent échouer si le fichier local temporaire a été purgé entre-temps.
    private func relaunch(_ t: Transfer) async throws -> Int {
        switch t.kind {
        case .download:
            guard let remote = t.sourceRemote else {
                throw TransferQueueError.cannotRetry("Remote source manquant.")
            }
            let destinationURL = URL(fileURLWithPath: t.destinationPath)
            if t.isDirectoryTransfer ?? false {
                try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)
                // Réacquisition du scope security-scoped pour les downloads de
                // dossier vers iCloud Drive / On My iPhone / picker externe.
                // Sans ça, l'URL caller a été désallouée → scope iOS retiré →
                // librclone écrit hors-sandbox → permission denied silencieux,
                // job bloqué à 0 octet, jamais de "terminé"/"échoué".
                //
                // Le scope DOIT rester actif pendant toute la durée du job
                // rclone, PAS seulement pendant cet appel Swift — librclone
                // retourne le jobid quasi-instantanément, puis la goroutine Go
                // appelle os.Open() pour CHAQUE fichier du dossier bien après
                // que `copyDirAsync` ait rendu la main. On stocke donc la
                // (URL, didStart) dans `activeSecurityScopes[jobID]` et c'est
                // `pollLoop` qui libère le scope quand `finished=true`.
                let resolvedBookmark = t.destinationSecurityBookmark.flatMap(Self.resolveSecurityScopedBookmark)
                let dstFs = resolvedBookmark?.url.path ?? destinationURL.path
                let jobID: Int
                do {
                    jobID = try await TransferService.shared.copyDirAsync(
                        srcFs: "\(remote):\(t.sourcePath)",
                        dstFs: dstFs
                    )
                } catch {
                    if let pair = resolvedBookmark, pair.didStart {
                        pair.url.stopAccessingSecurityScopedResource()
                    }
                    await LogService.shared.log(.error, category: "transfer",
                        message: "copyDirAsync échec src=\(remote):\(t.sourcePath) dst=\(dstFs) → \(error.localizedDescription)")
                    throw error
                }
                if let pair = resolvedBookmark {
                    activeSecurityScopes[jobID] = pair
                    await LogService.shared.log(.debug, category: "transfer",
                        message: "🔒 scope security-scoped actif pour jobID=\(jobID) dst=\(dstFs) (scope started=\(pair.didStart))")
                }
                return jobID
            } else {
                let parent = destinationURL.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
                return try await TransferService.shared.copyFileAsync(
                    srcFs: "\(remote):",
                    srcPath: t.sourcePath,
                    dstFs: parent.path,
                    dstPath: destinationURL.lastPathComponent
                )
            }

        case .upload:
            guard let remote = t.destinationRemote else {
                throw TransferQueueError.cannotRetry("Remote destination manquant.")
            }
            let localURL = URL(fileURLWithPath: t.sourcePath)
            let isFolder = t.sourceKind == .localFolder
                || (t.isDirectoryTransfer ?? false)
                || isDirectory(localURL)
            if isFolder {
                return try await TransferService.shared.copyDirAsync(
                    srcFs: localURL.path,
                    dstFs: "\(remote):\(t.destinationPath)"
                )
            } else {
                return try await TransferService.shared.copyFileAsync(
                    srcFs: localURL.deletingLastPathComponent().path,
                    srcPath: localURL.lastPathComponent,
                    dstFs: "\(remote):",
                    dstPath: t.destinationPath
                )
            }

        case .copy, .move, .sync:
            guard let srcRemote = t.sourceRemote,
                  let dstRemote = t.destinationRemote else {
                throw TransferQueueError.cannotRetry("Source ou destination manquante.")
            }
            switch (t.kind, t.isDirectoryTransfer ?? false) {
            case (.copy, false), (.sync, false):
                return try await TransferService.shared.copyFileAsync(
                    srcFs: "\(srcRemote):", srcPath: t.sourcePath,
                    dstFs: "\(dstRemote):", dstPath: t.destinationPath)
            case (.copy, true):
                return try await TransferService.shared.copyDirAsync(
                    srcFs: "\(srcRemote):\(t.sourcePath)",
                    dstFs: "\(dstRemote):\(t.destinationPath)")
            case (.move, false):
                return try await TransferService.shared.moveFileAsync(
                    srcFs: "\(srcRemote):", srcPath: t.sourcePath,
                    dstFs: "\(dstRemote):", dstPath: t.destinationPath)
            case (.move, true):
                return try await TransferService.shared.moveDirAsync(
                    srcFs: "\(srcRemote):\(t.sourcePath)",
                    dstFs: "\(dstRemote):\(t.destinationPath)")
            case (.sync, true):
                return try await TransferService.shared.syncDirAsync(
                    srcFs: "\(srcRemote):\(t.sourcePath)",
                    dstFs: "\(dstRemote):\(t.destinationPath)")
            default:
                throw TransferQueueError.cannotRetry("Type de transfert non supporté.")
            }

        case .delete:
            throw TransferQueueError.cannotRetry("Une suppression ne peut pas être reprise.")
        }
    }

    // MARK: - Scheduler (file d'attente à concurrence bornée)

    static let maxConcurrentKey = "transfer.maxConcurrentTransfers"
    static let pauseOnCellularKey = "transfer.pauseOnCellular"
    static let cellularLimitKey = "transfer.cellularLimitMBps"
    static let wifiLimitKey = "transfer.bandwidthLimitMBps"

    /// Nombre max de transferts download/upload simultanés. Mode Auto ON →
    /// valeur décidée par AutoTransferPolicy (réseau + énergie) ; OFF →
    /// préférence manuelle inchangée (défaut 3, borné 1…8).
    public var maxConcurrent: Int {
        if isAutoModeEnabled { return currentAutoDecision.queueConcurrency }
        let v = UserDefaults.standard.integer(forKey: Self.maxConcurrentKey)
        return v <= 0 ? 3 : min(v, 8)
    }

    /// Seuls les transferts « lourds » (download/upload) passent par la file
    /// bornée ; copy/move/sync/rename/delete restent dispatchés immédiatement.
    private func isQueuedKind(_ t: Transfer) -> Bool {
        t.kind == .download || t.kind == .upload
    }

    /// Peut-on démarrer de nouveaux transferts ? Faux si pause globale,
    /// hors-ligne, ou cellulaire avec l'option « pause en cellulaire ».
    private var canStartNewTransfers: Bool {
        if isPausedGlobally { return false }
        let reach = NetworkReachability.shared
        if !reach.isOnline { return false }
        if reach.isCellularLike && UserDefaults.standard.bool(forKey: Self.pauseOnCellularKey) {
            return false
        }
        return true
    }

    /// Cœur de la file : démarre autant de transferts `.enqueued` que de slots
    /// libres, par priorité (queueOrder) puis ancienneté. Synchrone : réclame
    /// les slots de façon ATOMIQUE (statut `.running` posé avant tout await),
    /// puis dispatch chaque job en arrière-plan via startClaimed.
    public func scheduleNext() {
        guard modelContext != nil else { return }
        guard canStartNewTransfers else {
            // Diagnostic : des transferts attendent mais on ne peut pas démarrer
            // → journalise la raison (visible dans Réglages → Logs).
            if !fetchEnqueuedSorted().isEmpty {
                let reason = isPausedGlobally
                    ? "pause globale active"
                    : (!NetworkReachability.shared.isOnline
                        ? "hors-ligne"
                        : "cellulaire + « pause en cellulaire »")
                Task { await LogService.shared.log(.info, category: "transfer",
                    message: "⏳ File en attente : démarrage bloqué (\(reason))") }
            }
            return
        }
        let slots = maxConcurrent - countRunningQueued()
        guard slots > 0 else { return }
        let waiting = Array(fetchEnqueuedSorted().prefix(slots))
        guard !waiting.isEmpty else { return }
        for t in waiting { t.status = .running }   // réservation atomique du slot
        try? modelContext?.save()
        for t in waiting { startClaimed(t) }
    }

    private func countRunningQueued() -> Int {
        guard let modelContext else { return 0 }
        let descriptor = FetchDescriptor<Transfer>(
            predicate: #Predicate { $0.statusRaw == "running" }
        )
        let running = (try? modelContext.fetch(descriptor)) ?? []
        return running.filter { isQueuedKind($0) }.count
    }

    private func fetchEnqueuedSorted() -> [Transfer] {
        guard let modelContext else { return [] }
        let descriptor = FetchDescriptor<Transfer>(
            predicate: #Predicate { $0.statusRaw == "enqueued" },
            sortBy: [SortDescriptor(\.queueOrder, order: .forward),
                     SortDescriptor(\.startedAt, order: .forward)]
        )
        let all = (try? modelContext.fetch(descriptor)) ?? []
        let queued = all.filter { isQueuedKind($0) }
        guard isAutoModeEnabled, queued.count > 1 else { return queued }
        // Mode Auto : petits-fichiers-d'abord à priorité manuelle égale —
        // maximise les éléments terminés par minute. Le geste « Prioriser »
        // (queueOrder min-1) prime toujours sur la taille ; bytesTotal est
        // déjà connu à l'enqueue (operations/size / entry.size), zéro RPC.
        let candidates = queued.map {
            AutoTransferPolicy.QueueCandidate(
                id: $0.id,
                queueOrder: $0.queueOrder,
                bytesTotal: $0.bytesTotal,
                startedAt: $0.startedAt
            )
        }
        let byID = Dictionary(uniqueKeysWithValues: queued.map { ($0.id, $0) })
        return AutoTransferPolicy.sortSmallFirst(candidates).compactMap { byID[$0.id] }
    }

    /// Dispatch effectif d'un transfert déjà réservé (.running) par scheduleNext.
    private func startClaimed(_ transfer: Transfer) {
        let id = transfer.id
        // Les downloads de DOSSIER sont développés en une file de copyfile PAR
        // FICHIER, bornée et passant par le bouclier cgoQueue (comme la synchro
        // photos). On abandonne les workers URLSession hors-bouclier et le
        // sync/copy global de tout l'arbre : les deux figeaient l'app (pool GCD
        // épuisé / daemon iCloud `bird` saturé sur les gros dossiers).
        if transfer.kind == .download, (transfer.isDirectoryTransfer ?? false) {
            // On stocke la Task pour permettre pause/cancel ciblés. La Task se
            // retire du dict en sortant.
            let task = Task { @MainActor [weak self] in
                guard let self else { return }
                await self.downloadFolderViaFiles(id: id)
                self.bridgeFolderTasks[id] = nil
            }
            bridgeFolderTasks[id] = task
            return
        }
        Task { @MainActor in
            do {
                let jobID = try await relaunch(transfer)
                guard let t = fetchTransfer(id: id), t.status == .running else { return }
                t.jobID = jobID
                try? modelContext?.save()
                startPolling(t)
            } catch {
                if let t = fetchTransfer(id: id) {
                    if autoPauseInsteadOfFail(t) {
                        // Le dispatch a échoué parce que le réseau est tombé
                        // entre la réservation du slot et la RPC : pause auto,
                        // le retour du lien remettra en file.
                        scheduleNext()
                        return
                    }
                    t.status = .failed
                    t.lastError = error.localizedDescription
                    t.finishedAt = .now
                    try? modelContext?.save()
                }
                await LogService.shared.log(.error, category: "transfer",
                    message: "Démarrage du transfert échoué : \(error.localizedDescription)")
                scheduleNext()
            }
        }
    }

    /// True si ce transfert tourne via BridgeFolderDownloader (et donc a une
    /// Task dans `bridgeFolderTasks`).
    fileprivate func isBridgeFolderTransfer(_ transfer: Transfer) -> Bool {
        transfer.kind == .download
            && (transfer.isDirectoryTransfer ?? false)
            && bridgeFolderTasks[transfer.id] != nil
    }

    /// Télécharge un dossier comme la synchro PHOTOS : une file de
    /// `operations/copyfile` (RPC async + poll job/status) PAR FICHIER, bornée
    /// à `maxConcurrent`, TOUS passant par le bouclier `cgoQueue`. Aucun worker
    /// URLSession hors-bouclier (qui figeait l'app), aucun `sync/copy` global
    /// de tout l'arbre (qui saturait le daemon iCloud `bird` sur 9 Go). Le
    /// scope security-scoped du dossier destination est tenu pendant TOUTE la
    /// durée (les goroutines librclone écrivent après le retour du copyfile).
    /// Une seule ligne `Transfer` par dossier (pas d'explosion SwiftData sur
    /// les gros dossiers) ; progression et `currentFilename` mis à jour à la
    /// complétion de chaque fichier.
    private func downloadFolderViaFiles(id: String) async {
        guard let transfer = fetchTransfer(id: id) else { return }
        guard let remote = transfer.sourceRemote else {
            transfer.status = .failed
            transfer.lastError = "Remote source manquant."
            transfer.finishedAt = .now
            try? modelContext?.save()
            scheduleNext()
            return
        }
        let sourcePath = transfer.sourcePath
        let batchID = transfer.batchID
        let destinationURL = URL(fileURLWithPath: transfer.destinationPath)
        // Scope tenu pour tout le dossier (le bookmark vise le dossier parent
        // choisi par l'utilisateur ; les fichiers s'écrivent en-dessous).
        let resolvedBookmark = transfer.destinationSecurityBookmark.flatMap(Self.resolveSecurityScopedBookmark)
        func releaseScope() {
            if let pair = resolvedBookmark, pair.didStart {
                pair.url.stopAccessingSecurityScopedResource()
            }
        }

        // 1) Listing récursif (fichiers seulement).
        let files: [RemoteEntryDTO]
        do {
            files = try await RemoteService.shared.listRecursive(remote: remote, path: sourcePath)
                .filter { !$0.isDirectory }
        } catch {
            releaseScope()
            if let t = fetchTransfer(id: id), !autoPauseInsteadOfFail(t) {
                t.status = .failed
                t.lastError = error.localizedDescription
                t.finishedAt = .now
                try? modelContext?.save()
            }
            await LogService.shared.log(.error, category: "transfer",
                message: "Listing dossier échoué \(remote):\(sourcePath) — \(error.localizedDescription)")
            scheduleNext()
            return
        }
        let bytesTotal = files.reduce(Int64(0)) { $0 + max($1.size, 0) }
        transfer.fileCount = files.count
        transfer.bytesTotal = max(bytesTotal, transfer.bytesTotal)
        try? modelContext?.save()

        // 2) Skip des fichiers déjà présents avec la même taille (reprise sans
        //    tout retélécharger). destDir = racine locale du dossier.
        let partition = BridgeFolderDownloader.partitionByExistence(
            files: files, sourcePath: sourcePath, destDir: destinationURL
        )
        var doneBytes = partition.skippedBytes
        transfer.bytesTransferred = doneBytes
        try? modelContext?.save()

        await LogService.shared.log(.info, category: "transfer",
            message: "📁 Download dossier (par fichiers) \(remote):\(sourcePath) files=\(files.count) skip=\(partition.skippedCount) concurrency=\(min(max(maxConcurrent,1),8)) bytesTotal=\(bytesTotal)")

        // 3) File bornée de copyfile+poll. maxConcurrent respecte le mode Auto
        //    / le réglage manuel, borné 1…8. Chaque copyfile passe par le
        //    bouclier cgoQueue → jamais d'épuisement du pool GCD → pas de gel.
        let concurrency = min(max(maxConcurrent, 1), 8)
        var iterator = partition.todo.makeIterator()
        var firstError: Error?

        await withTaskGroup(of: (name: String, size: Int64, error: Error?).self) { group in
            @discardableResult
            func addNext() -> Bool {
                guard let next = iterator.next() else { return false }
                let srcPath = next.entry.pathInRemote
                let size = max(next.entry.size, 0)
                let destURL = next.destURL
                let name = next.entry.name
                group.addTask { [self] in
                    do {
                        try await self.copyFileAndWait(remote: remote, srcPath: srcPath, destURL: destURL)
                        return (name, size, nil)
                    } catch {
                        return (name, size, error)
                    }
                }
                return true
            }

            for _ in 0..<concurrency where addNext() {}

            while let result = await group.next() {
                if let err = result.error {
                    if firstError == nil { firstError = err }
                    group.cancelAll()
                    continue
                }
                doneBytes += result.size
                if let t = fetchTransfer(id: id) {
                    t.bytesTransferred = doneBytes
                    t.currentFilename = result.name
                    try? modelContext?.save()
                }
                if Task.isCancelled { group.cancelAll(); continue }
                addNext()
            }
        }

        releaseScope()

        // 4) Finalisation.
        if Task.isCancelled {
            // Pause/annulation : l'état (.paused) est posé par pause()/cancel().
            scheduleNext()
            return
        }
        if let err = firstError {
            if let t = fetchTransfer(id: id), !autoPauseInsteadOfFail(t) {
                t.status = .failed
                t.lastError = err.localizedDescription
                t.finishedAt = .now
                try? modelContext?.save()
                updateBatch(batchID, completedDelta: 0, failedDelta: 1)
                await LogService.shared.log(.error, category: "transfer",
                    message: "❌ Download dossier échoué \(remote):\(sourcePath) — \(err.localizedDescription)")
            }
        } else if let t = fetchTransfer(id: id) {
            t.bytesTransferred = max(t.bytesTransferred, t.bytesTotal)
            t.status = .completed
            t.finishedAt = .now
            try? modelContext?.save()
            updateBatch(batchID, completedDelta: 1, failedDelta: 0)
            await LogService.shared.log(.info, category: "transfer",
                message: "✅ Download dossier terminé \(remote):\(sourcePath) (\(t.fileCount) fichiers)")
        }
        scheduleNext()
    }

    /// Copie UN fichier via `operations/copyfile` (async) puis attend la fin en
    /// pollant `job/status` (500 ms). Le copyfile rend la main quasi
    /// instantanément (jobID) → la lane du bouclier est libérée aussitôt, seul
    /// le poll — léger — reste. `Task.checkCancellation()` stoppe le poll sur
    /// pause/annulation (le fichier partiel sera re-téléchargé au skip-existing).
    private func copyFileAndWait(remote: String, srcPath: String, destURL: URL) async throws {
        let parent = destURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let jobID = try await TransferService.shared.copyFileAsync(
            srcFs: "\(remote):", srcPath: srcPath,
            dstFs: parent.path, dstPath: destURL.lastPathComponent
        )
        while true {
            try Task.checkCancellation()
            let status = try await TransferService.shared.jobStatus(jobID: jobID)
            if status.finished {
                if !status.success {
                    throw RcloneError.rcloneError(
                        code: 0, method: "operations/copyfile",
                        message: status.error ?? "échec du téléchargement de \(destURL.lastPathComponent)"
                    )
                }
                return
            }
            try await Task.sleep(for: .milliseconds(500))
        }
    }

    /// Crée le transfert EN FILE D'ATTENTE (.enqueued) puis tente de démarrer.
    /// Utilisé par les enqueue download/upload à la place du démarrage immédiat.
    private func enqueueAndSchedule(_ transfer: Transfer) {
        transfer.status = .enqueued
        modelContext?.insert(transfer)
        try? modelContext?.save()
        scheduleNext()
    }

    /// Change le nombre de transferts simultanés et relance le scheduler.
    public func setMaxConcurrent(_ n: Int) {
        UserDefaults.standard.set(min(max(n, 1), 8), forKey: Self.maxConcurrentKey)
        scheduleNext()
    }

    /// Fait passer un transfert en attente en TÊTE de file (priorité souple :
    /// pas de préemption d'un job en cours, mais premier servi au slot suivant).
    public func prioritize(_ transfer: Transfer) {
        let minOrder = fetchEnqueuedSorted().map(\.queueOrder).min() ?? 0
        transfer.queueOrder = minOrder - 1
        try? modelContext?.save()
        scheduleNext()
    }

    // MARK: - Politique réseau (Wi-Fi / cellulaire)

    /// Abonné aux changements de lien (`.networkPathDidChange`) : réévalue la
    /// concurrence du mode Auto puis applique la politique réseau courante.
    public func handleNetworkChange() async {
        refreshAutoPolicy()
        await applyNetworkPolicy()
    }

    /// Génération de politique réseau : invalide une fenêtre de drain en cours
    /// si un nouvel évènement réseau survient entre-temps.
    private var networkPolicyGeneration = 0
    /// Fenêtre de drain (s) avant de suspendre sur bascule vers cellulaire.
    private static let networkDrainSeconds: UInt64 = 8

    /// Applique la limite de bande passante selon le lien (Wi-Fi vs cellulaire),
    /// met en pause auto en cellulaire/hors-ligne si demandé, et reprend les
    /// transferts AUTO-pausés quand la connexion redevient utilisable.
    public func applyNetworkPolicy() async {
        networkPolicyGeneration &+= 1
        let gen = networkPolicyGeneration
        let reach = NetworkReachability.shared
        let cellular = reach.isCellularLike
        let pauseOnCellular = UserDefaults.standard.bool(forKey: Self.pauseOnCellularKey)
        let wifiMBps = UserDefaults.standard.double(forKey: Self.wifiLimitKey)
        let cellMBps = UserDefaults.standard.double(forKey: Self.cellularLimitKey)

        if !reach.isOnline {
            // Hors-ligne : pause immédiate (drainer sans réseau n'a aucun sens).
            await LogService.shared.log(.info, category: "transfer",
                message: "📴 Hors-ligne : pause auto des transferts actifs")
            await autoPauseActive()
            return
        }
        if cellular && pauseOnCellular {
            // Fenêtre de DRAIN : on laisse les transferts en vol progresser
            // quelques secondes avant de les suspendre, plutôt qu'un arrêt sec
            // qui gaspille les octets en cours sur la bascule Wi-Fi → cellulaire.
            await LogService.shared.log(.info, category: "transfer",
                message: "📵 Passage en cellulaire : drain \(Self.networkDrainSeconds)s avant pause")
            try? await Task.sleep(nanoseconds: Self.networkDrainSeconds * 1_000_000_000)
            // Un nouvel évènement réseau a invalidé ce drain → on laisse la
            // nouvelle évaluation décider.
            guard gen == networkPolicyGeneration else { return }
            // Conditions plus réunies (retour Wi-Fi, option coupée…) → réévalue.
            guard reach.isOnline, reach.isCellularLike,
                  UserDefaults.standard.bool(forKey: Self.pauseOnCellularKey) else {
                await applyNetworkPolicy()
                return
            }
            await LogService.shared.log(.info, category: "transfer",
                message: "📵 Cellulaire + « pause en cellulaire » : transferts suspendus")
            await autoPauseActive()
            return
        }
        let bytes = cellular ? Int64(cellMBps * 1024 * 1024) : Int64(wifiMBps * 1024 * 1024)
        try? await TransferService.shared.setBandwidthLimit(bytesPerSecond: bytes)
        await LogService.shared.log(.info, category: "transfer",
            message: cellular
                ? "📶 Cellulaire : limite \(cellMBps <= 0 ? "illimitée" : String(format: "%.1f MB/s", cellMBps))"
                : "📶 Wi-Fi : limite \(wifiMBps <= 0 ? "illimitée" : String(format: "%.1f MB/s", wifiMBps))")
        resumeAutoPaused()
    }

    /// Met en pause AUTO tous les transferts download/upload actifs (marqués
    /// `autoPaused` pour distinguer d'une pause manuelle).
    private func autoPauseActive() async {
        for t in fetchActivePausable() where isQueuedKind(t) {
            await pause(t)
            t.autoPaused = true
        }
        try? modelContext?.save()
    }

    /// Remet en file les transferts AUTO-pausés (jamais ceux pausés à la main).
    private func resumeAutoPaused() {
        let paused = fetchPaused().filter { $0.autoPaused }
        for t in paused {
            t.autoPaused = false
            t.status = .enqueued
        }
        if !paused.isEmpty { try? modelContext?.save() }
        scheduleNext()
    }

    /// Retry a failed transfer by re-enqueuing an equivalent operation. The
    /// failed Transfer record stays in the store as audit trail; a brand new
    /// Transfer is created via the regular enqueue path. Not every kind can
    /// be retried automatically — uploads need the original local file (often
    /// deleted by then), and deletes don't carry the isDirectory hint.
    public func retry(_ transfer: Transfer) async throws {
        switch transfer.kind {
        case .download:
            guard let srcRemote = transfer.sourceRemote, !transfer.destinationPath.isEmpty else {
                throw TransferQueueError.cannotRetry("Métadonnées du téléchargement incomplètes.")
            }
            try await enqueueDownload(
                remote: srcRemote,
                path: transfer.sourcePath,
                to: URL(fileURLWithPath: transfer.destinationPath)
            )

        case .copy, .move, .sync:
            guard let srcRemote = transfer.sourceRemote,
                  let dstRemote = transfer.destinationRemote else {
                throw TransferQueueError.cannotRetry("Source ou destination manquante.")
            }
            // Use the persisted isDirectoryTransfer flag set by enqueueRemoteTransfer.
            // Pre-Sprint-3 records have nil → treat as file (the old default behavior).
            // For records where we know it's a directory, we route through the right
            // rclone RPC (sync/copy or sync/move instead of operations/copyfile).
            let synthetic = RemoteEntryDTO(
                pathInRemote: transfer.sourcePath,
                name: transfer.displayName ?? (transfer.sourcePath as NSString).lastPathComponent,
                isDirectory: transfer.isDirectoryTransfer ?? false,
                size: transfer.bytesTotal,
                modTime: .now,
                mimeType: nil,
                hashMD5: nil,
                hashSHA1: nil
            )
            try await enqueueRemoteTransfer(
                kind: transfer.kind,
                srcRemote: srcRemote,
                entry: synthetic,
                dstRemote: dstRemote,
                dstPath: transfer.destinationPath
            )

        case .upload:
            throw TransferQueueError.cannotRetry(
                "Le retry d'un upload n'est pas supporté — relancez l'upload depuis le dossier d'origine."
            )

        case .delete:
            throw TransferQueueError.cannotRetry(
                "Le retry d'une suppression n'est pas supporté — réessayez depuis le dossier."
            )
        }

        // Annotate the original transfer so the UI can collapse old failures.
        transfer.lastError = (transfer.lastError ?? "Échec") + " — retry lancé"
        try? modelContext?.save()
    }

    /// Persisted across launches so that the UI and rclone agree on the
    /// pause state after a cold start. rclone forgets its bwlimit between
    /// runs, so we replay this flag at boot via `restoreFromPersistedState`.
    public static let persistedPauseKey = "transfer.isPausedGlobally"

    /// Met en pause TOUS les transferts actifs, individuellement (stop + état
    /// `.paused`), au lieu de l'ancien `core/bwlimit 1b` global qui finissait
    /// par faire timeout/mourir les jobs (d'où « ça ne redémarre pas »).
    /// Exclut PhotoSync (qui a sa propre pause) et les suppressions (instantanées).
    public func pauseAllTransfers() async throws {
        for t in fetchActivePausable() where t.sourceKind != .photoLibrary && t.kind != .delete {
            await pause(t)
        }
        isPausedGlobally = true
        UserDefaults.standard.set(true, forKey: Self.persistedPauseKey)
    }

    /// Reprend TOUS les transferts en pause (relance chaque opération) et
    /// restaure la limite de bande passante préférée de l'utilisateur.
    /// `bytesPerSecond == 0` means "no limit" (rate "off").
    public func resumeAllTransfers(bytesPerSecond: Int64) async throws {
        // La pause par-transfert ne touche pas le bwlimit, mais on réapplique
        // la préférence utilisateur par sécurité (no-op si déjà correcte).
        try? await TransferService.shared.setBandwidthLimit(bytesPerSecond: bytesPerSecond)
        for t in fetchPaused() where t.sourceKind != .photoLibrary {
            try? await resume(t)
        }
        isPausedGlobally = false
        UserDefaults.standard.set(false, forKey: Self.persistedPauseKey)
    }

    private func fetchActivePausable() -> [Transfer] {
        guard let modelContext else { return [] }
        let descriptor = FetchDescriptor<Transfer>(
            predicate: #Predicate { $0.statusRaw == "running" || $0.statusRaw == "pending" || $0.statusRaw == "enqueued" }
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private func fetchPaused() -> [Transfer] {
        guard let modelContext else { return [] }
        let descriptor = FetchDescriptor<Transfer>(
            predicate: #Predicate { $0.statusRaw == "paused" }
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    /// Apply the user's bandwidth setting without toggling pause state.
    /// Called at app launch and whenever the user changes the slider in
    /// the Performance settings.
    public func applyBandwidthLimit(bytesPerSecond: Int64) async throws {
        try await TransferService.shared.setBandwidthLimit(bytesPerSecond: bytesPerSecond)
    }

// MARK: - Throttle pendant l'activité utilisateur

    /// Marge « soft » retenue sur le débit max quand l'utilisateur est actif :
    /// 10% du ceiling reste dispo pour absorber les pics UI / SwiftData fetches
    /// / RPC core/stats sans freezer l'app. Combiné au fait que l'utilisateur
    /// voit son activité détectée par `UserActivityMonitor` (cf.
    /// inactivityThreshold), on garde 90% du débit max en continu et 100%
    /// dès qu'il arrête d'interagir.
    private static let activeMarginNumerator: Int64 = 9
    private static let activeMarginDenominator: Int64 = 10

    /// Compteur de bypass : TransfersView l'incrémente à .onAppear et le
    /// décrémente à .onDisappear pour ne PAS throttler quand l'utilisateur
    /// regarde explicitement les transferts (il veut voir le débit réel).
    private var userActivityBypassCount: Int = 0
    private var isThrottlingForUserActivity = false
    /// Dernière limite réellement appliquée (octets/s) — évite les RPC bwlimit
    /// redondantes ET permet de réappliquer quand le cap média change sans que
    /// l'état de throttle d'activité bouge.
    private var lastAppliedBwlimit: Int64 = -1
    /// Plafond de débit pendant un téléchargement vidéo (0 = pas de cap). Sans
    /// lui, à l'inactivité le download repasse plein débit (ceiling utilisateur),
    /// sature le process rclone et fige l'app. Avec, il reste plafonné en continu.
    private var mediaDownloadCapBytes: Int64 = 0

    /// Plafonne une limite « débit utilisateur » par le cap média s'il est actif.
    private func clampToMediaCap(_ bytes: Int64) -> Int64 {
        guard mediaDownloadCapBytes > 0 else { return bytes }
        if bytes == 0 { return mediaDownloadCapBytes }   // 0 = illimité côté user
        return min(bytes, mediaDownloadCapBytes)
    }

    /// Active (bytes>0) ou retire (0) le plafond de débit « téléchargement vidéo ».
    public func setMediaDownloadCap(_ bytes: Int64) async {
        mediaDownloadCapBytes = max(0, bytes)
        await reevaluateUserActivityThrottle()
    }

    public func incrementActivityBypass() {
        userActivityBypassCount += 1
        // Re-évalue : si on était en throttle mais bypass demandé, on retire.
        Task { await reevaluateUserActivityThrottle() }
    }

    public func decrementActivityBypass() {
        userActivityBypassCount = max(0, userActivityBypassCount - 1)
        Task { await reevaluateUserActivityThrottle() }
    }

    /// Appelé par UserActivityMonitor (via Notification) quand l'état
    /// d'activité change. Politique : toujours plein débit mais plafonné à 90%
    /// du ceiling — les 10% restants absorbent les pics UI / SwiftData fetches
    /// / RPC core/stats sans freezer l'app. Idle → 100% du ceiling.
    public func applyThrottleForUserActivity(isActive: Bool, userPreferredBytes: Int64) async {
        // Y a-t-il quelque chose à throttler ? Si AUCUN transfert ne tourne et
        // qu'il n'y a pas de cap média, toucher au bwlimit pendant la simple
        // navigation ne sert à rien et générait une rafale de core/bwlimit
        // (off↔90% à chaque tap) — pur gaspillage CPU/énergie. On s'abstient.
        let hasThrottleableWork = mediaDownloadCapBytes > 0 || anyRunningTransfer()

        // Politique unique : 90% du ceiling quand l'utilisateur est actif,
        // 100% quand inactif. Pas de throttle dur séparé pour la nav : on
        // garde 10% de marge pour absorber les pics CPU/IO sans freezer.
        // Si le user a lui-même choisi une limite (transfer.bandwidthLimitMBps),
        // elle est dans `userPreferredBytes` et `smartCeiling` la respecte.
        // Les 10% se gomment quand le user fixe une limite stricte.
        let ceiling = clampToMediaCap(smartCeiling(userPreferredBytes))
        let target: Int64
        let isThrottlingNow: Bool
        if !isActive || !hasThrottleableWork || isPausedGlobally {
            // Idle ou rien à faire : plein débit (100% du ceiling).
            target = ceiling
            isThrottlingNow = false
        } else {
            // Actif + transfert en cours : 90% du ceiling. Si le user a fixé
            // une limite stricte < ceiling, on prend 90% de SA limite — sinon
            // 90% du plafond intelligent (qui peut être 0 = illimité, on
            // active alors le throttle off, qui en pratique = pas de cap).
            let activeCeiling = ceiling
            target = activeCeiling > 0
                ? (activeCeiling * Self.activeMarginNumerator / Self.activeMarginDenominator)
                : 0
            isThrottlingNow = target > 0
        }

        guard target != lastAppliedBwlimit else { return }

        do {
            try await TransferService.shared.setBandwidthLimit(bytesPerSecond: target)
            lastAppliedBwlimit = target
            isThrottlingForUserActivity = isThrottlingNow
        } catch {
            // Best effort : si la RPC bwlimit fail, on log mais on n'altère
            // pas le flag pour qu'un retry futur tente à nouveau.
            await LogService.shared.log(
                .debug,
                category: "transfer",
                message: "Throttle activity échec : \(error.localizedDescription)"
            )
        }
    }

    private func reevaluateUserActivityThrottle() async {
        // Réajuste après changement de bypass count / pression énergie : on relit
        // la prefs depuis UserDefaults et on aligne sur l'état actif courant.
        let mbps = UserDefaults.standard.double(forKey: "transfer.bandwidthLimitMBps")
        let bytes = Int64(mbps * 1024 * 1024)
        let isActive = UserActivityMonitor.shared.isUserActive
        await applyThrottleForUserActivity(isActive: isActive, userPreferredBytes: bytes)
    }

    /// Y a-t-il au moins un transfert `.running` ? Borné à 1 (fetchCount) pour
    /// rester quasi gratuit même appelé sur chaque évènement d'activité.
    private func anyRunningTransfer() -> Bool {
        guard let modelContext else { return false }
        var descriptor = FetchDescriptor<Transfer>(
            predicate: #Predicate { $0.statusRaw == "running" }
        )
        descriptor.fetchLimit = 1
        return ((try? modelContext.fetchCount(descriptor)) ?? 0) > 0
    }

    /// Plafond « intelligent » du débit : réduit la limite sous pression
    /// thermique ou en mode économie d'énergie pour rester fluide et économe.
    /// Ne fait que BAISSER une limite (jamais l'augmenter) et seulement sous
    /// pression réelle — au repos thermique, renvoie la préférence inchangée.
    /// `bytes == 0` = illimité côté utilisateur ; renvoie alors le cap s'il y en a un.
    private func smartCeiling(_ userPreferredBytes: Int64) -> Int64 {
        let info = ProcessInfo.processInfo
        var cap: Int64 = 0   // 0 = aucune contrainte
        if info.isLowPowerModeEnabled { cap = 2 * 1_048_576 }              // 2 MB/s en mode éco
        switch info.thermalState {
        case .serious:  cap = cap == 0 ? 1_048_576 : min(cap, 1_048_576)   // 1 MB/s si ça chauffe
        case .critical: cap = cap == 0 ? 524_288 : min(cap, 524_288)       // 0,5 MB/s si critique
        default: break
        }
        guard cap > 0 else { return userPreferredBytes }
        return userPreferredBytes == 0 ? cap : min(userPreferredBytes, cap)
    }

    /// Réagit aux changements d'état thermique / mode éco pour relever ou
    /// rabaisser le plafond intelligent sans attendre la prochaine interaction.
    private var energyObserversInstalled = false
    private func startEnergyObservers() {
        guard !energyObserversInstalled else { return }
        energyObserversInstalled = true
        let names: [Notification.Name] = [
            ProcessInfo.thermalStateDidChangeNotification,
            .NSProcessInfoPowerStateDidChange,
        ]
        for name in names {
            NotificationCenter.default.addObserver(
                forName: name, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    // Concurrence (mode Auto) ET plafond de débit réagissent
                    // au même évènement thermique/énergie.
                    self?.refreshAutoPolicy()
                    await self?.reevaluateUserActivityThrottle()
                }
            }
        }
    }

    /// Cold-start handler: re-applies the persisted pause/bwlimit state to
    /// rclone (which forgot it) and updates the in-memory `isPausedGlobally`
    /// flag so the UI matches the real backend state.
    ///
    /// `bytesPerSecond` is the user's preferred ceiling (0 = unlimited),
    /// read from `@AppStorage("transfer.bandwidthLimitMBps")` by the caller.
    /// Retries with exponential backoff on RPC failure — rclone's Go runtime
    /// may not be listening yet at the moment this is invoked.
    public func restoreFromPersistedState(bytesPerSecond: Int64) async {
        // La pause GLOBALE est un état de SESSION, PAS un verrou persistant :
        // la restaurer à `true` au boot bloquait silencieusement tout nouveau
        // transfert (symptôme « reste en file, ne démarre pas »). Les transferts
        // mis en pause restent `.paused` individuellement (persistés par
        // SwiftData) et restent repris à la main ; un nouveau lancement démarre
        // donc librement.
        isPausedGlobally = false
        UserDefaults.standard.set(false, forKey: Self.persistedPauseKey)

        let delays: [UInt64] = [500_000_000, 1_000_000_000, 2_000_000_000]
        for (index, delay) in delays.enumerated() {
            do {
                try await TransferService.shared.setBandwidthLimit(bytesPerSecond: bytesPerSecond)
                if index > 0 {
                    await LogService.shared.log(
                        .info,
                        category: "transfer",
                        message: "Bandwidth state restored after \(index) retry attempt(s)"
                    )
                }
                return
            } catch {
                if index == delays.count - 1 {
                    await LogService.shared.log(
                        .error,
                        category: "transfer",
                        message: "Failed restoring bandwidth after \(delays.count) attempts: \(error.localizedDescription)"
                    )
                    return
                }
                try? await Task.sleep(nanoseconds: delay)
            }
        }
    }

    /// Live state mirrored from `pauseAllTransfers` / `resumeAllTransfers`
    /// and rehydrated by `restoreFromPersistedState` at launch.
    public private(set) var isPausedGlobally: Bool = false

    // MARK: - Polling

    private func startPolling(_ transfer: Transfer) {
        guard let jobID = transfer.jobID else { return }
        let transferID = transfer.id
        let task = Task { [weak self] in
            await self?.pollLoop(transferID: transferID, jobID: jobID)
            return ()
        }
        pollTasks[jobID] = task
    }

    private func autoRetryKey(_ t: Transfer) -> String {
        "\(t.sourceRemote ?? "")|\(t.sourcePath)|\(t.destinationRemote ?? "")|\(t.destinationPath)"
    }

    /// Éligible au re-enqueue automatique ? On exclut les batches et PhotoSync
    /// (logiques propres) et les downloads de DOSSIER (retry() les relancerait
    /// en copyfile). Budget de tentatives : en mode Auto, par CLASSE d'erreur
    /// (permanent 0 / inconnu 2 / transitoire et rate-limit 3) ; en manuel,
    /// `maxAutoRetries` historique — via une signature stable.
    private func shouldAutoRetry(_ t: Transfer, errorMessage: String?) -> Bool {
        guard t.batchID == nil, t.sourceKind != .photoLibrary else { return false }
        switch t.kind {
        case .copy, .move, .sync:
            break
        case .download where (t.isDirectoryTransfer ?? false) == false:
            break
        default:
            return false
        }
        return autoRetryCounts[autoRetryKey(t), default: 0] < retryBudget(for: errorMessage)
    }

    /// Nombre max de tentatives auto pour un message d'erreur donné.
    private func retryBudget(for errorMessage: String?) -> Int {
        guard isAutoModeEnabled else { return maxAutoRetries }
        return AutoTransferPolicy.maxAttempts(for: AutoTransferPolicy.classify(errorMessage))
    }

    /// Garde hors-ligne du mode Auto : un échec pendant une coupure réseau
    /// n'est PAS un échec. Passe le transfert en pause AUTO sans consommer de
    /// tentative ; le retour du réseau le remet en file via le chemin existant
    /// .networkPathDidChange → applyNetworkPolicy → resumeAutoPaused (les
    /// dossiers reprennent en skip-existing). Réservé aux download/upload
    /// (seuls repêchés par resumeAutoPaused) ENCORE .running — une pause
    /// manuelle ou une annulation posée pendant l'await du dispatch/poll ne
    /// doit jamais être convertie en pause auto relançable — hors PhotoSync
    /// (pipeline d'état propre). Renvoie true si la pause a été appliquée.
    private func autoPauseInsteadOfFail(_ t: Transfer) -> Bool {
        guard AutoTransferPolicy.shouldAutoPauseInsteadOfFail(
            status: t.status,
            kind: t.kind,
            sourceKind: t.sourceKind,
            autoEnabled: isAutoModeEnabled,
            isOnline: NetworkReachability.shared.isOnline
        ) else { return false }
        t.jobID = nil
        t.status = .paused
        t.autoPaused = true
        t.finishedAt = nil
        try? modelContext?.save()
        let src = t.sourcePath
        Task {
            await LogService.shared.log(.info, category: "transfer",
                message: "📴 Échec hors-ligne : \(src) en pause auto (reprise au retour du réseau)")
        }
        return true
    }

    private func pollLoop(transferID: String, jobID: Int) async {
        var lastPollLogged = -10
        while !Task.isCancelled {
            do {
                let status = try await TransferService.shared.jobStatus(jobID: jobID)
                let transfer = self.fetchTransfer(id: transferID)
                guard let transfer else {
                    break
                }
                // Log debug toutes les 30 s (pas 5 s) pour éviter de marteler
                // LogService (actor hop + ring buffer append) pendant les gros
                // transferts où chaque µs de CPU compte. La première fenêtre
                // 0-30 s est couverte par les logs `📈 core/stats` ; au-delà
                // un sample toutes les 30 s suffit pour confirmer la vie du job.
                let elapsed = Int(Date().timeIntervalSince(transfer.startedAt))
                if !status.finished, elapsed > 0, elapsed % 30 == 0, elapsed - lastPollLogged >= 25 {
                    lastPollLogged = elapsed
                    await LogService.shared.log(.debug, category: "transfer",
                        message: "📊 poll jobID=\(jobID) src=\(transfer.sourceRemote ?? "?"):\(transfer.sourcePath) finished=\(status.finished) success=\(status.success) error=\(status.error ?? "nil") elapsed=\(elapsed)s scopeLocked=\(activeSecurityScopes[jobID] != nil)")
                }
                if status.finished {
                    let finalKind = transfer.kind
                    let finalSrc = transfer.sourcePath
                    var deleteAfterCompletion = false
                    if status.success {
                        transfer.bytesTransferred = max(transfer.bytesTransferred, transfer.bytesTotal)
                        transfer.status = .completed
                        updateBatch(transfer.batchID, completedDelta: 1, failedDelta: 0)
                        if transfer.sourceKind == .photoLibrary {
                            PhotoSyncService.shared.transferDidFinish(
                                destinationPath: transfer.destinationPath,
                                success: true,
                                error: nil
                            )
                            // Anti-explosion SwiftData : 1 ligne Transfer par photo
                            // (18k+) saturait la table (full scans + @Query qui
                            // matérialise des milliers de lignes). L'état est déjà
                            // suivi par PhotoSyncAsset → on supprime la ligne terminée.
                            if transfer.batchID == nil { deleteAfterCompletion = true }
                        }
                        if !deleteAfterCompletion {
                            await LogService.shared.log(
                                .info,
                                category: "transfer",
                                message: "✅ \(finalKind.rawValue) terminé : \(finalSrc)"
                            )
                        }
                    } else if autoPauseInsteadOfFail(transfer) {
                        // Coupure réseau : pause auto au lieu d'un échec — ne
                        // consomme aucune tentative, reprise au retour du lien.
                        break
                    } else if shouldAutoRetry(transfer, errorMessage: status.error) {
                        // Re-enqueue auto borné (coupures réseau transitoires).
                        let key = autoRetryKey(transfer)
                        let attempt = autoRetryCounts[key, default: 0] + 1
                        autoRetryCounts[key] = attempt
                        let budget = retryBudget(for: status.error)
                        transfer.status = .failed
                        transfer.lastError = (status.error ?? "Échec") + " — nouvelle tentative \(attempt)/\(budget)"
                        transfer.finishedAt = .now
                        try? modelContext?.save()
                        await LogService.shared.log(
                            .info,
                            category: "transfer",
                            message: "🔁 Nouvelle tentative auto \(attempt)/\(budget) : \(finalSrc)"
                        )
                        let toRetry = transfer
                        // Backoff EXPONENTIEL avec jitter (équilibré) : plus doux
                        // pour le radio/la batterie que l'ancien délai linéaire,
                        // et le jitter évite que plusieurs échecs simultanés ne
                        // retentent tous au même instant. Mode Auto : bornes par
                        // CLASSE d'erreur (rate-limit attend plus longtemps) ;
                        // manuel : formule historique cap 60 s inchangée.
                        let backoff: Double
                        if isAutoModeEnabled,
                           let range = AutoTransferPolicy.retryDelayRange(
                               errorClass: AutoTransferPolicy.classify(status.error),
                               attempt: attempt
                           ) {
                            backoff = Double.random(in: range)
                        } else {
                            let capped = min(60.0, 3.0 * pow(2.0, Double(attempt - 1)))
                            backoff = capped / 2 + Double.random(in: 0...(capped / 2))
                        }
                        Task { @MainActor in
                            try? await Task.sleep(for: .seconds(backoff))
                            try? await self.retry(toRetry)
                        }
                        break
                    } else {
                        transfer.status = .failed
                        transfer.lastError = status.error ?? "Échec inconnu"
                        updateBatch(transfer.batchID, completedDelta: 0, failedDelta: 1)
                        if transfer.sourceKind == .photoLibrary {
                            PhotoSyncService.shared.transferDidFinish(
                                destinationPath: transfer.destinationPath,
                                success: false,
                                error: transfer.lastError
                            )
                        }
                        await LogService.shared.log(
                            .error,
                            category: "transfer",
                            message: "❌ \(finalKind.rawValue) échoué : \(finalSrc) — \(status.error ?? "raison inconnue")"
                        )
                    }
                    if deleteAfterCompletion {
                        modelContext?.delete(transfer)
                    } else {
                        transfer.finishedAt = .now
                    }
                    try? modelContext?.save()
                    break
                }
                // Pas de save() ici : le chemin « non terminé » ne mute RIEN dans
                // pollLoop (la progression est persistée par tickStats, qui a son
                // propre dirty-flag). Sauver à chaque tick (500 ms/job) invalidait
                // inutilement tous les @Query → re-render des vues. Dirty-flag de fait.
                try await Task.sleep(for: .milliseconds(500))
            } catch is CancellationError {
                break
            } catch {
                let transfer = self.fetchTransfer(id: transferID)
                if let transfer, autoPauseInsteadOfFail(transfer) {
                    // La RPC de poll a échoué parce que le réseau est tombé :
                    // pause auto (reprise au retour) au lieu d'un échec sec.
                    break
                }
                transfer?.status = .failed
                transfer?.lastError = error.localizedDescription
                transfer?.finishedAt = .now
                updateBatch(transfer?.batchID, completedDelta: 0, failedDelta: transfer == nil ? 0 : 1)
                try? modelContext?.save()
                await LogService.shared.log(
                    .error,
                    category: "transfer",
                    message: "Polling jobID=\(jobID) interrompu : \(error.localizedDescription)"
                )
                break
            }
        }
        pollTasks[jobID] = nil
        // Libère le scope security-scoped iCloud Drive quand le polling se
        // termine (succès, échec, annulation, ou interruption réseau).
        // La goroutine librclone a fini ses `os.Open` à ce stade → safe.
        if let pair = activeSecurityScopes.removeValue(forKey: jobID), pair.didStart {
            pair.url.stopAccessingSecurityScopedResource()
            await LogService.shared.log(.debug, category: "transfer",
                message: "🔓 scope security-scoped libéré pour jobID=\(jobID)")
        }
        // Un transfert vient de se terminer (succès/échec) → libère son slot
        // et démarre le suivant en file d'attente.
        scheduleNext()
    }

    private func fetchTransfer(id: String) -> Transfer? {
        guard let modelContext else { return nil }
        let descriptor = FetchDescriptor<Transfer>(
            predicate: #Predicate { $0.id == id }
        )
        return try? modelContext.fetch(descriptor).first
    }

    // MARK: - Stats polling (running transfers progress)

    private func startStatsPolling() {
        guard statsTask == nil else { return }
        statsTask = Task { [weak self] in
            while !Task.isCancelled {
                let hadWork = await self?.tickStats() ?? false
                // Intervalle adaptatif selon la charge de travail :
                //   - idle → 3 s (économie énergie)
                //   - transfert léger (< 100 MB) → 800 ms (UI fluide)
                //   - transfert lourd (≥ 100 MB, typique 9 GB iCloud Drive)
                //     → 2 s : la barre de progression n'a pas besoin de 75
                //     updates/min sous contention IO `bird` daemon. 30/min
                //     suffit pour ne pas paraître figée et libère 60% de
                //     CPU polling + SwiftData fetches + RPC core/stats.
                let interval: Duration
                if !hadWork {
                    interval = .seconds(3)
                } else if let maxBytes = await self?.maxRunningTransferBytes(), maxBytes >= 100_000_000 {
                    interval = .seconds(2)
                } else {
                    interval = .milliseconds(800)
                }
                try? await Task.sleep(for: interval)
            }
        }
    }

    /// Plus gros transfert `.running` en octets (bytesTotal), 0 si aucun.
    /// Coût négligeable : fetch SwiftData indexé sur statusRaw + max().
    private func maxRunningTransferBytes() -> Int64 {
        guard let modelContext else { return 0 }
        let descriptor = FetchDescriptor<Transfer>(
            predicate: #Predicate { $0.statusRaw == "running" }
        )
        guard let running = try? modelContext.fetch(descriptor) else { return 0 }
        return running.map(\.bytesTotal).max() ?? 0
    }

    @discardableResult
    private func tickStats() async -> Bool {
        guard let modelContext else { return false }
        let descriptor = FetchDescriptor<Transfer>(
            predicate: #Predicate { $0.statusRaw == "running" }
        )
        guard let running = try? modelContext.fetch(descriptor), !running.isEmpty else {
            return false
        }
        guard let stats = try? await TransferService.shared.coreStats() else { return false }

        // Log debug toutes les ~10 s (pas 5 s) pour confirmer que librclone EXPOSE
        // bien des fichiers en train de se transférer (vs coincé sans rien
        // produire). Utile pour distinguer "barre cassée" (stat transferring
        // non vide mais matching rate) de "vraiment bloqué" (stat vide →
        // librclone hang). On n'émet que s'il y a au moins un transfert dossier
        // (cas d'intérêt) pour ne pas spammer les logs pendant les copies de
        // fichiers simples. 10 s plutôt que 5 s : allège LogService (actor hop
        // + ring buffer append) qui consommait ~5% CPU sur les gros dossiers.
        let hasDirTransfer = running.contains { ($0.isDirectoryTransfer ?? false) }
        if hasDirTransfer {
            let now = Int(Date().timeIntervalSince1970)
            if now % 10 == 0, now != lastCoreStatsLog {
                lastCoreStatsLog = now
                let sample = stats.transferring.prefix(3)
                    .map { "\($0.name)(\($0.bytesTransferred)/\(($0.bytesTotal)))" }
                    .joined(separator: ", ")
                await LogService.shared.log(.debug, category: "transfer",
                    message: "📈 core/stats transferring=\(stats.transferring.count) bytes=\(stats.transferredBytes)/\(stats.totalBytes) sample=[\(sample)]")
            }
        }

        // core/stats reports per-file under `transferring`, keyed by the destination basename.
        // We do best-effort matching. Dirty flag : on évite save() si rien
        // n'a changé (épargne ~10ms × 75/min = 750ms CPU/min en idle).
        //
        // Stratégie à deux passes :
        //  1. Transferts FICHIER : match direct (statMatchesTransfer / fallbacks).
        //     On note les index consommés pour ne pas les recompter dans un dossier.
        //  2. Transferts DOSSIER : on agrège les stats restantes internes au dossier
        //     (stat.name préfixé par le relativePath / sourcePath du dossier) en
        //     sommant bytesTransferred et bytesTotal. bytesTotal reste plafonné par
        //     le pré-calcul operations/size fait à l'enqueue.
        var consumedStatIndexes = Set<Int>()
        var didMutate = false

        // Passe 1 — transferts fichier (non-dossier).
        for transfer in running where !(transfer.isDirectoryTransfer ?? false) {
            if let match = stats.transferring.firstIndex(where: { statMatchesTransfer($0, transfer: transfer) })
                ?? uniqueSizeFallbackIndex(stats: stats, running: running, transfer: transfer)
                ?? singleTransferFallbackIndex(stats: stats, running: running) {
                let stat = stats.transferring[match]
                consumedStatIndexes.insert(match)
                let newBytes = stat.bytesTransferred
                let newTotal = max(stat.bytesTotal, transfer.bytesTotal)
                if transfer.bytesTransferred != newBytes || transfer.bytesTotal != newTotal {
                    transfer.bytesTransferred = newBytes
                    transfer.bytesTotal = newTotal
                    didMutate = true
                }
            }
        }

        // Passe 2 — transferts dossier : agrégation des fichiers internes.
        for transfer in running where (transfer.isDirectoryTransfer ?? false) {
            let matchedIndexes = directoryInternalStatIndexes(
                stats: stats,
                transfer: transfer,
                excluding: consumedStatIndexes
            )
            guard !matchedIndexes.isEmpty else { continue }
            let aggBytes = matchedIndexes.reduce(Int64(0)) { $0 + stats.transferring[$1].bytesTransferred }
            let aggFileTotal = matchedIndexes.reduce(Int64(0)) { $0 + stats.transferring[$1].bytesTotal }
            consumedStatIndexes.formUnion(matchedIndexes)
            // bytesTransferred = somme des bytes déjà transmis des fichiers internes.
            let newBytes = aggBytes
            // bytesTotal : on garde le max entre le pré-calcul operations/size
            // et la somme des tailles des fichiers actuellement transférés
            // (rclone peut découvrir des fichiers au fil de l'eau, et certains
            // peuvent être sizeless si operations/size a échoué → fallback).
            let newTotal = max(aggFileTotal, transfer.bytesTotal)
            if transfer.bytesTransferred != newBytes || transfer.bytesTotal != newTotal {
                transfer.bytesTransferred = newBytes
                transfer.bytesTotal = newTotal
                didMutate = true
            }
        }

        let batchesChanged = updateRunningBatches()
        if didMutate || batchesChanged {
            try? modelContext.save()
        }
        return true
    }

    /// Renvoie les index de `stats.transferring` correspondant aux fichiers
    /// internes à un transfert dossier, hors ceux déjà consommés par un
    /// transfert fichier. Un stat est rattaché au dossier si son `name`
    /// (chemin relatif rclone) commence par le `relativePath` / basename
    /// du dossier, ou si aucun transfert fichier ne le réclame et qu'il
    /// reste des stats non matchées (fallback unique dossier).
    private func directoryInternalStatIndexes(
        stats: CoreStatsDTO,
        transfer: Transfer,
        excluding consumed: Set<Int>
    ) -> Set<Int> {
        let folderBases = [
            transfer.relativePath,
            transfer.displayName,
            (transfer.sourcePath as NSString).lastPathComponent,
            (transfer.destinationPath as NSString).lastPathComponent
        ].compactMap { $0?.isEmpty == false ? $0 : nil }

        // Cas "destination aplatie" : l'utilisateur a pické le dossier parent
        // (ex : /Downloads/) au lieu d'un sous-dossier. librclone copie alors
        // le contenu de `drivethe:daisychain` À PLAT dans /Downloads/, donc les
        // fichiers transférés ont des noms SANS préfixe (juste le basename :
        // "pleading-horny_4471641.mp4"). Le matching par préfixe échoue → la
        // barre de progression reste à 0 alors que les octets passent.
        // On détecte : destination.basename != source.basename. Si vrai, on
        // matche tous les fichiers non-claimed. Si plusieurs transferts dossier
        // aplatis tournent en parallèle, le premier consomme tout (cas rare
        // et visible : on verra 0 sur les suivants, l'utilisateur s'en rend
        // compte — acceptable vs barre cassée sur 9 GB de média).
        let sourceBasename = (transfer.sourcePath as NSString).lastPathComponent
        let destBasename = (transfer.destinationPath as NSString).lastPathComponent
        let isFlattened = !sourceBasename.isEmpty
            && !destBasename.isEmpty
            && sourceBasename != destBasename

        var matched = Set<Int>()
        for (i, stat) in stats.transferring.enumerated() where !consumed.contains(i) {
            let name = stat.name
            if isFlattened {
                // Destination aplatie : tous les fichiers non-claimed
                // appartiennent à ce transfert.
                matched.insert(i)
                continue
            }
            // Match direct : le fichier est à l'intérieur du dossier
            // → "subfolder/photo.jpg" sous "Photos" → préfixe "Photos/".
            let isInternal = folderBases.contains { base in
                name == base || name.hasPrefix("\(base)/") || name.hasPrefix("\(base)\\")
            }
            if isInternal { matched.insert(i) }
        }
        return matched
    }

    private func statMatchesTransfer(_ stat: CoreStatsDTO.Transferring, transfer: Transfer) -> Bool {
        let statName = stat.name
        let statBase = (statName as NSString).lastPathComponent
        let sourceBase = (transfer.sourcePath as NSString).lastPathComponent
        let destinationBase = (transfer.destinationPath as NSString).lastPathComponent
        let displayName = transfer.displayName ?? ""

        let candidates = [
            transfer.sourcePath,
            transfer.destinationPath,
            sourceBase,
            destinationBase,
            displayName,
        ].filter { !$0.isEmpty }

        return candidates.contains { candidate in
            statName == candidate
                || statBase == candidate
                || statName.hasSuffix("/\(candidate)")
                || candidate.hasSuffix("/\(statName)")
        }
    }

    private func uniqueSizeFallbackIndex(
        stats: CoreStatsDTO,
        running: [Transfer],
        transfer: Transfer
    ) -> Int? {
        guard transfer.bytesTotal > 0 else { return nil }
        let sameSizeTransfers = running.filter { $0.bytesTotal == transfer.bytesTotal }
        guard sameSizeTransfers.count == 1 else { return nil }
        let sameSizeStats = stats.transferring.enumerated().filter { $0.element.bytesTotal == transfer.bytesTotal }
        guard sameSizeStats.count == 1 else { return nil }
        return sameSizeStats.first?.offset
    }

    private func singleTransferFallbackIndex(
        stats: CoreStatsDTO,
        running: [Transfer]
    ) -> Int? {
        guard stats.transferring.count == 1, running.count == 1 else { return nil }
        return 0
    }

    // MARK: - Cold start replay

    private func replayInterrupted() async {
        guard let modelContext else { return }
        // La pause globale n'est plus un verrou persistant (cf.
        // restoreFromPersistedState) : un nouveau lancement démarre librement.
        isPausedGlobally = false
        let descriptor = FetchDescriptor<Transfer>(
            predicate: #Predicate { $0.statusRaw == "running" || $0.statusRaw == "pending" || $0.statusRaw == "enqueued" }
        )
        guard let candidates = try? modelContext.fetch(descriptor) else { return }
        for transfer in candidates {
            if isQueuedKind(transfer) {
                // Reprise robuste au démarrage à froid : le job rclone n'existe
                // plus après la mort du process → on remet en file pour relance
                // automatique (rclone saute les fichiers déjà transférés).
                transfer.jobID = nil
                transfer.autoPaused = false
                transfer.status = .enqueued
            } else {
                // copy/move/sync/rename : pas de reprise auto, relance manuelle.
                transfer.status = .failed
                transfer.lastError = "Interrompu — relance manuelle requise"
                transfer.finishedAt = .now
            }
        }
        try? modelContext.save()
        scheduleNext()
    }

    // MARK: - Batch helpers

    private func updateBatch(_ batchID: String?, completedDelta: Int, failedDelta: Int) {
        guard let batchID, let batch = fetchBatch(id: batchID) else { return }
        batch.completedItems += completedDelta
        batch.failedItems += failedDelta
        if batch.completedItems + batch.failedItems >= batch.totalItems {
            batch.status = batch.failedItems > 0 ? .failed : .completed
            batch.finishedAt = .now
        }
        try? modelContext?.save()
    }

    /// Renvoie `true` si au moins un champ d'un batch a été modifié, pour
    /// que tickStats puisse skip le save() quand rien n'a bougé.
    @discardableResult
    private func updateRunningBatches() -> Bool {
        guard let modelContext else { return false }
        let descriptor = FetchDescriptor<TransferBatch>(
            predicate: #Predicate { $0.statusRaw == "running" }
        )
        guard let batches = try? modelContext.fetch(descriptor), !batches.isEmpty else { return false }
        var didMutate = false
        for batch in batches {
            let id = batch.id
            let transferDescriptor = FetchDescriptor<Transfer>(
                predicate: #Predicate { $0.batchID == id }
            )
            guard let transfers = try? modelContext.fetch(transferDescriptor) else { continue }
            let total = transfers.reduce(Int64(0)) { $0 + $1.bytesTotal }
            let transferred = transfers.reduce(Int64(0)) { $0 + $1.bytesTransferred }
            if batch.bytesTotal != total || batch.bytesTransferred != transferred {
                batch.bytesTotal = total
                batch.bytesTransferred = transferred
                didMutate = true
            }
        }
        return didMutate
    }

    private func fetchBatch(id: String) -> TransferBatch? {
        guard let modelContext else { return nil }
        let descriptor = FetchDescriptor<TransferBatch>(
            predicate: #Predicate { $0.id == id }
        )
        return try? modelContext.fetch(descriptor).first
    }

    private func joinedRemotePath(_ folder: String, _ name: String) -> String {
        let cleanFolder = folder.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return cleanFolder.isEmpty ? name : "\(cleanFolder)/\(name)"
    }

    private func remoteBatchTitle(kind: TransferKind, count: Int) -> String {
        let action: String
        switch kind {
        case .copy: action = "Copie"
        case .move: action = "Déplacement"
        case .sync: action = "Synchronisation"
        default: action = "Transfert"
        }
        return count == 1 ? "\(action) d'un élément" : "\(action) de \(count) éléments"
    }

    private func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        return isDirectory.boolValue
    }

    /// Le chemin est-il dans iCloud Drive ? Les URLs de l'espace « iCloud Drive »
    /// (dossier Mobile Documents) contiennent le conteneur `com~apple~CloudDocs` ;
    /// y écrire un gros dossier déclenche le daemon `bird` (upload iCloud) qui
    /// fige l'app. `nonisolated static` → pur et testable sans le singleton.
    nonisolated static func isICloudDrivePath(_ path: String) -> Bool {
        path.contains("com~apple~CloudDocs") || path.contains("/Mobile Documents/")
    }

    private func fileSize(at url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values?.fileSize ?? 0)
    }

    // `nonisolated static` : énumération récursive O(arbre) → doit tourner HORS
    // du @MainActor (sinon hitch visible au tap « Upload » d'un gros dossier).
    nonisolated static func directorySize(at url: URL) -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
            if values?.isDirectory != true {
                total += Int64(values?.fileSize ?? 0)
            }
        }
        return total
    }
}

public enum TransferQueueError: LocalizedError, Equatable {
    /// The retry path can't fully reconstruct the original transfer (missing
    /// metadata, unsupported kind). The associated message is shown to the user.
    case cannotRetry(String)

    public var errorDescription: String? {
        switch self {
        case .cannotRetry(let reason):
            return "Retry impossible : \(reason)"
        }
    }
}
