//
//  BridgeFolderDownloader.swift
//  Rclone GUI — Services
//
//  Download de dossier via N workers bridge loopback en parallèle.
//  Remplace `sync/copy` (operations/sync/copy + job/status + core/stats
//  polling) pour les téléchargements de dossiers — qui sature l'iCloud
//  Drive `bird` daemon et gelait l'app sur 9 GB.
//
//  Pattern identique à `BridgeFileDownloader` (FileProviderFetchService) et
//  `MediaCacheService.downloadViaBridge` : un fichier par worker =
//  un `RclonebridgeStartFileHTTP` + `URLSession.shared.download`. Pas
//  d'RPC pendant le download, progression via URLSession callbacks, iOS
//  gère l'I/O disque + la backpressure côté kernel.
//
//  Décisions de conception (validées par l'utilisateur) :
//    - 4 workers parallèles par défaut (configurable via UserDefaults)
//    - Large-first sort (sature le réseau dès les premiers octets)
//    - Skip si fichier destination existe avec taille identique
//    - Validation immédiate à la fin (pas de sous-dossier `.partial`)
//

import Foundation
#if canImport(RcloneKit)
import RcloneKit
#endif

public actor BridgeFolderDownloader {
    public static let shared = BridgeFolderDownloader()
    private init() {}

    public struct ProgressSnapshot: Sendable {
        public var bytesTransferred: Int64
        public var bytesTotal: Int64
        public var filesCompleted: Int
        public var filesTotal: Int
        public var currentFilename: String?
    }

    public enum DownloadError: LocalizedError {
        case emptyFolder(remote: String, path: String)
        case listingFailed(remote: String, path: String, underlying: Error)
        case workerFailed(file: String, underlying: Error)

        public var errorDescription: String? {
            switch self {
            case .emptyFolder(let remote, let path):
                return "Dossier vide ou inaccessible : \(remote):\(path)"
            case .listingFailed(let remote, let path, let err):
                return "Listing impossible pour \(remote):\(path) — \(err.localizedDescription)"
            case .workerFailed(let file, let err):
                return "Échec du téléchargement de \(file) — \(err.localizedDescription)"
            }
        }
    }

    /// Progression courante du download (snapshot lu par les callers).
    private var lastSnapshot: ProgressSnapshot = .init(bytesTransferred: 0, bytesTotal: 0, filesCompleted: 0, filesTotal: 0, currentFilename: nil)

    public func lastProgress() -> ProgressSnapshot { lastSnapshot }

    /// Télécharge un dossier via N workers bridge parallèles. Le callback
    /// `onProgress` est invoqué sur le MainActor après chaque chunk (throttlé
    /// à 500 ms en interne pour éviter de marteler SwiftData).
    ///
    /// - Parameters:
    ///   - remote: nom du remote rclone (ex: `"drivethe"`)
    ///   - sourcePath: chemin source dans le remote (ex: `"daisychain"`)
    ///   - destDir: dossier local de destination
    ///   - concurrency: nombre de workers parallèles (défaut: 4)
    ///   - onProgress: callback SwiftUI/SwiftData update (doit s'exécuter sur MainActor)
    public func downloadFolder(
        remote: String,
        sourcePath: String,
        destDir: URL,
        concurrency: Int = 4,
        onProgress: @escaping @MainActor @Sendable (ProgressSnapshot) -> Void
    ) async throws {
        let concurrency = max(1, min(concurrency, 16))
        let started = Date()

        // 1) Listing récursif
        let files: [RemoteEntryDTO]
        do {
            files = try await RemoteService.shared.listRecursive(remote: remote, path: sourcePath)
        } catch {
            throw DownloadError.listingFailed(remote: remote, path: sourcePath, underlying: error)
        }
        guard !files.isEmpty else {
            throw DownloadError.emptyFolder(remote: remote, path: sourcePath)
        }

        // 2) Tri large-first (sature le réseau + le disque dès le début)
        let sorted = Self.sortLargeFirst(files)

        // 3) Skip fichiers déjà présents avec taille identique (reprise après
        //    pause sans tout retélécharger). On calcule bytesTransferred
        //    initial pour ne pas fausser la barre de progression.
        var todo: [(entry: RemoteEntryDTO, destURL: URL)] = []
        var skippedBytes: Int64 = 0
        var skippedCount = 0
        let partition = Self.partitionByExistence(
            files: sorted, sourcePath: sourcePath, destDir: destDir
        )
        skippedBytes = partition.skippedBytes
        skippedCount = partition.skippedCount
        todo = partition.todo

        let bytesTotal = sorted.reduce(Int64(0)) { $0 + $1.size }
        var bytesTransferred = skippedBytes
        var filesCompleted = skippedCount

        // Snapshot initial
        var snapshot = ProgressSnapshot(
            bytesTransferred: bytesTransferred,
            bytesTotal: bytesTotal,
            filesCompleted: filesCompleted,
            filesTotal: sorted.count,
            currentFilename: nil
        )
        lastSnapshot = snapshot
        await MainActor.run { onProgress(snapshot) }

        await LogService.shared.log(
            .info, category: "transfer",
            message: "🌉 BridgeFolderDownloader start remote=\(remote):\(sourcePath) → \(destDir.path) files=\(sorted.count) skip=\(skippedCount) concurrency=\(concurrency) bytesTotal=\(bytesTotal)"
        )

        // 4) Pool de workers TaskGroup avec concurrence bornée
        var iterator = todo.makeIterator()
        let throttledProgress = ThrottledProgress(onProgress: onProgress, intervalMs: 500)
        var workerErrors: [Error] = []

        try await withThrowingTaskGroup(of: Void.self) { group in
            // Seed N workers
            for _ in 0..<concurrency {
                guard let next = iterator.next() else { break }
                group.addTask { [self] in
                    do {
                        try await runWorker(
                            remote: remote,
                            entry: next.entry,
                            destURL: next.destURL,
                            onFileBytes: { writtenDelta, totalSize in
                                Task { await self.recordFileBytes(delta: writtenDelta, currentTotal: snapshot.bytesTotal) }
                                throttledProgress.maybeFire(snapshot)
                            },
                            onFileDone: { filename in
                                Task { await self.recordFileDone(filename: filename, currentTotal: snapshot.bytesTotal) }
                                throttledProgress.maybeFire(snapshot, force: true)
                            }
                        )
                    } catch {
                        workerErrors.append(error)
                    }
                }
            }

            // Au fur et à mesure qu'un worker finit, en ajoute un nouveau
            // tant qu'il reste des fichiers.
            while try await group.next() != nil {
                if Task.isCancelled { break }
                while let next = iterator.next() {
                    group.addTask { [self] in
                        do {
                            try await runWorker(
                                remote: remote,
                                entry: next.entry,
                                destURL: next.destURL,
                                onFileBytes: { writtenDelta, _ in
                                    Task { await self.recordFileBytes(delta: writtenDelta, currentTotal: snapshot.bytesTotal) }
                                    throttledProgress.maybeFire(snapshot)
                                },
                                onFileDone: { filename in
                                    Task { await self.recordFileDone(filename: filename, currentTotal: snapshot.bytesTotal) }
                                    throttledProgress.maybeFire(snapshot, force: true)
                                }
                            )
                        } catch {
                            workerErrors.append(error)
                        }
                    }
                }
            }
        }

        // 5) Vérifier les erreurs — si au moins un worker a échoué, on remonte
        //    la première (le caller peut retry). Les fichiers déjà écrits
        //    restent sur disque (reprise partielle naturelle).
        if let firstError = workerErrors.first {
            let elapsed = Int(Date().timeIntervalSince(started))
            await LogService.shared.log(
                .error, category: "transfer",
                message: "🌉 BridgeFolderDownloader PARTIAL FAIL after \(elapsed)s errors=\(workerErrors.count) first=\(firstError.localizedDescription)"
            )
            throw DownloadError.workerFailed(file: "multiple", underlying: firstError)
        }

        let elapsed = Int(Date().timeIntervalSince(started))
        let avgSpeed = elapsed > 0 ? bytesTransferred / Int64(elapsed) : 0
        await LogService.shared.log(
            .info, category: "transfer",
            message: "✅ BridgeFolderDownloader DONE remote=\(remote):\(sourcePath) files=\(sorted.count) bytes=\(bytesTransferred)/\(bytesTotal) elapsed=\(elapsed)s avg=\(avgSpeed) B/s"
        )

        // Flush final
        snapshot.bytesTransferred = bytesTransferred
        snapshot.filesCompleted = filesCompleted
        lastSnapshot = snapshot
        await MainActor.run { onProgress(snapshot) }
    }

    // MARK: - Worker

    /// Télécharge un fichier via bridge loopback + URLSession. Pas
    /// d'actor isolation interne : utilise un NSObject delegate + continuation
    /// comme `BridgeFileDownloader` côté FileProvider.
    private nonisolated func runWorker(
        remote: String,
        entry: RemoteEntryDTO,
        destURL: URL,
        onFileBytes: @escaping @Sendable (Int64, Int64) -> Void,
        onFileDone: @escaping @Sendable (String) -> Void
    ) async throws {
        // 1) Démarre la session bridge loopback pour ce fichier
        guard let session = await RcloneStreamingService.shared.liveSession(
            remote: remote, path: entry.pathInRemote
        ) else {
            throw DownloadError.workerFailed(
                file: entry.pathInRemote,
                underlying: NSError(
                    domain: "BridgeFolderDownloader", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Bridge liveSession indisponible"]
                )
            )
        }
        defer { Task { await RcloneStreamingService.shared.stop(session) } }

        // 2) Pré-crée le dossier destination (sub-dossiers du path relatif)
        let parent = destURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)

        // 3) Télécharge via URLSession
        let downloader = FileWorkerDownloader(
            dest: destURL,
            onProgress: { written, total in
                onFileBytes(written, total)
            }
        )
        try await downloader.download(from: session.url)

        // 4) Signale la fin du fichier (la taille entière est_bytesTotal)
        onFileDone(entry.pathInRemote)
    }

    // MARK: - Progress bookkeeping (actor-isolated)

    fileprivate func recordFileBytes(delta: Int64, currentTotal: Int64) {
        var snap = lastSnapshot
        snap.bytesTransferred += delta
        lastSnapshot = snap
    }

    fileprivate func recordFileDone(filename: String, currentTotal: Int64) {
        var snap = lastSnapshot
        snap.filesCompleted += 1
        snap.currentFilename = filename
        lastSnapshot = snap
    }

    // MARK: - Pure helpers (testable sans HTTP ni actor)

    /// Tri large-first : sature le réseau dès les premiers octets (les gros
    /// fichiers remplissent le pipe et les petits finissent dans la queue).
    /// Stable : à taille égale, l'ordre d'origine (alphabétique de rclone)
    /// est préservé via `sorted(by:)` qui est stable sur Swift 5+.
    nonisolated static func sortLargeFirst(_ files: [RemoteEntryDTO]) -> [RemoteEntryDTO] {
        files.sorted { $0.size > $1.size }
    }

    /// Calcule le chemin relatif d'un fichier par rapport au `sourcePath`
    /// source du download. Préserve la structure interne du dossier distant.
    /// - `sourcePath=""` → `entry.pathInRemote` est déjà relatif
    /// - `sourcePath="daisychain"`, `entry.pathInRemote="daisychain/sub/foo.mp4"`
    ///   → retourne `"sub/foo.mp4"`
    nonisolated static func relativePath(for entry: RemoteEntryDTO, sourcePath: String) -> String {
        if sourcePath.isEmpty {
            return entry.pathInRemote
        }
        let prefix = sourcePath.hasSuffix("/") ? sourcePath : sourcePath + "/"
        if entry.pathInRemote.hasPrefix(prefix) {
            return String(entry.pathInRemote.dropFirst(prefix.count))
        }
        return entry.pathInRemote
    }

    /// Partitionne les fichiers en `todo` (à télécharger) vs `skipped`
    /// (déjà présents avec taille identique). Les fichiers `entry.size == 0`
    /// ne sont JAMAIS skippés (ré-engagement du download pour récupérer la
    /// taille réelle — important pour les backends qui retardent la taille).
    /// Utilisé pour la reprise après pause/crash sans tout retélécharger.
    nonisolated static func partitionByExistence(
        files: [RemoteEntryDTO],
        sourcePath: String,
        destDir: URL,
        fileManager: FileManager = .default
    ) -> (todo: [(entry: RemoteEntryDTO, destURL: URL)], skippedBytes: Int64, skippedCount: Int) {
        var todo: [(entry: RemoteEntryDTO, destURL: URL)] = []
        var skippedBytes: Int64 = 0
        var skippedCount = 0
        for entry in files {
            let rel = relativePath(for: entry, sourcePath: sourcePath)
            let destURL = destDir.appending(path: rel)
            if entry.size > 0,
               let attrs = try? fileManager.attributesOfItem(atPath: destURL.path),
               let size = attrs[.size] as? Int64,
               size == entry.size {
                skippedBytes += entry.size
                skippedCount += 1
                continue
            }
            todo.append((entry, destURL))
        }
        return (todo, skippedBytes, skippedCount)
    }
}

/// Wrapper URLSession minimal pour un worker. Réplique le pattern de
/// `BridgeFileDownloader` (FileProviderFetchService.swift:443) mais en
/// autonome — pas de fichier `.partial`, le fichier final est écrit
/// directement à la destination.
private final class FileWorkerDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let dest: URL
    private let onProgress: @Sendable (Int64, Int64) -> Void
    private var continuation: CheckedContinuation<Void, Error>?
    private var session: URLSession?
    private var moveError: Error?
    private var lastProgressAt = Date.distantPast

    init(dest: URL, onProgress: @escaping @Sendable (Int64, Int64) -> Void) {
        self.dest = dest
        self.onProgress = onProgress
        super.init()
    }

    func download(from url: URL) async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                self.continuation = cont
                let config = URLSessionConfiguration.default
                config.timeoutIntervalForRequest = 120
                config.timeoutIntervalForResource = 3600 * 6
                config.requestCachePolicy = .reloadIgnoringLocalCacheData
                // Pas d'HTTP cookie storage ni de credentials : on parle au bridge
                // loopback local, pas à Internet.
                config.httpCookieStorage = nil
                config.urlCredentialStorage = nil
                let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
                self.session = session
                session.downloadTask(with: url).resume()
            }
        } onCancel: {
            self.session?.invalidateAndCancel()
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        // Throttle à 250 ms (le throttler global applique aussi 500 ms côté
        // caller → au final ~500 ms effectif, peu de pression SwiftData).
        let now = Date()
        if now.timeIntervalSince(lastProgressAt) >= 0.25 {
            lastProgressAt = now
            onProgress(totalBytesWritten, max(0, totalBytesExpectedToWrite))
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? fm.removeItem(at: dest)
            try fm.moveItem(at: location, to: dest)
        } catch {
            moveError = error
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        session.finishTasksAndInvalidate()
        let cont = continuation
        continuation = nil
        if let moveError { cont?.resume(throwing: moveError); return }
        if let error { cont?.resume(throwing: error); return }
        if let http = task.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            cont?.resume(throwing: NSError(
                domain: "BridgeFolderDownloader", code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode) via bridge"]
            ))
            return
        }
        cont?.resume()
    }
}

/// Helper pour throttler les callbacks de progression. Pas d'actor isolation :
/// utilisé depuis plusieurs workers simultanément, garde son état interne.
private final class ThrottledProgress: @unchecked Sendable {
    private let onProgress: @Sendable (BridgeFolderDownloader.ProgressSnapshot) -> Void
    private let interval: TimeInterval
    private var lastFire: Date = .distantPast
    private let lock = NSLock()

    init(
        onProgress: @escaping @Sendable (BridgeFolderDownloader.ProgressSnapshot) -> Void,
        intervalMs: Int
    ) {
        self.onProgress = onProgress
        self.interval = TimeInterval(intervalMs) / 1000
    }

    func maybeFire(_ snapshot: BridgeFolderDownloader.ProgressSnapshot, force: Bool = false) {
        lock.lock()
        let now = Date()
        let shouldFire = force || now.timeIntervalSince(lastFire) >= interval
        if shouldFire { lastFire = now }
        lock.unlock()
        guard shouldFire else { return }
        Task { @MainActor in
            self.onProgress(snapshot)
        }
    }
}