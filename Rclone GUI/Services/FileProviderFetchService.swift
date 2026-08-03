//
//  FileProviderFetchService.swift
//  Rclone GUI — Services
//
//  Worker côté app principale pour les téléchargements demandés par
//  l'extension FileProvider. Une .appex iOS plafonne ~256 Mo et le combo
//  Go runtime + librclone + déchiffrement crypt fait jetsam pendant le
//  download. L'app principale (1.5 Go RAM) prend le relais.
//
//  Protocole IPC :
//   1. Extension écrit pending-fetches/<UUID>.json avec {requestID, remote,
//      path, destPath} et poste Darwin notification fp.fetch-request.
//   2. Ce service observe la notif, scanne pending-fetches/, télécharge
//      via TransferService.copyFileAsync (qui hit operations/copyfile)
//      vers un fichier temporaire `.partial-*`, écrit un heartbeat
//      `<UUID>.json.status`, puis déplace atomiquement ce fichier vers
//      destPath seulement après succès.
//   3. L'extension polle destPath toutes les 250ms ; quand le fichier
//      apparaît il est complet et elle le retourne à iOS via fetchContents
//      completion.
//   4. En cas d'échec, ce service écrit pending-fetches/<UUID>.json.error
//      avec le message ; l'extension le détecte et propage l'erreur.
//

import Foundation
#if canImport(RcloneKit)
import RcloneKit
#endif

/// Politique de durée de vie et de priorité des requêtes IPC File Provider.
///
/// Une énumération `list` n'a plus aucun consommateur après le timeout de 60 s
/// de l'extension. La rejouer au prochain lancement peut au contraire écraser un
/// manifest récent et, avec un backend lent, bloquer toutes les requêtes vivantes
/// derrière des centaines d'anciens chemins. Les téléchargements complets gardent
/// la durée maximale de six heures promise à l'extension, plus une marge de
/// nettoyage, afin qu'un téléchargement orphelin ne survive pas indéfiniment.
enum FileProviderPendingRequestPolicy {
    static let interactiveLifetime: TimeInterval = 2 * 60
    static let fullDownloadLifetime: TimeInterval = 6 * 60 * 60 + interactiveLifetime

    static func lifetime(for kind: String?) -> TimeInterval {
        switch kind {
        case "list", "stream-url": interactiveLifetime
        default: fullDownloadLifetime
        }
    }

    static func isExpired(_ pending: AppGroupPendingFetch, now: Date) -> Bool {
        now.timeIntervalSince(pending.createdAt) > lifetime(for: pending.kind)
    }

    /// Les listings/URLs de streaming sont interactifs et passent avant les
    /// downloads. Entre requêtes interactives, la plus récente gagne ; entre
    /// downloads, on conserve le FIFO.
    static func shouldProcessBefore(
        _ lhs: AppGroupPendingFetch,
        _ rhs: AppGroupPendingFetch
    ) -> Bool {
        func rank(_ kind: String?) -> Int {
            switch kind {
            case "list": 0
            case "stream-url": 1
            default: 2
            }
        }

        let lhsRank = rank(lhs.kind)
        let rhsRank = rank(rhs.kind)
        if lhsRank != rhsRank { return lhsRank < rhsRank }
        if lhs.createdAt == rhs.createdAt { return lhs.requestID < rhs.requestID }
        return lhsRank < 2
            ? lhs.createdAt > rhs.createdAt
            : lhs.createdAt < rhs.createdAt
    }
}

/// Clé réseau d'un listing File Provider. Plusieurs waiters possèdent chacun
/// leur propre requestID/ACK, mais un même `(remote, path)` ne doit déclencher
/// qu'un seul `operations/list` dans un batch — succès comme échec.
struct FileProviderPendingListKey: Hashable {
    let remote: String
    let path: String

    init?(_ pending: AppGroupPendingFetch) {
        guard pending.kind == "list" else { return nil }
        remote = pending.remote
        path = pending.path
    }
}

@MainActor
public final class FileProviderFetchService {
    public static let shared = FileProviderFetchService()
    private init() {}

    private var observerToken: UnsafeMutableRawPointer?
    private var processing: Set<String> = []
    private var isDraining = false
    private var needsAnotherDrain = false

    private struct DecodedRequest {
        let url: URL
        let pending: AppGroupPendingFetch
    }

    /// À appeler une fois au boot de l'app principale. Configure l'observer
    /// Darwin et traite les pending-fetches déjà présents (cas où l'extension
    /// a écrit pendant que l'app était killed).
    public func start() {
        registerDarwinObserver()
        Task { await processPendingFetches(reason: "boot scan") }
    }

    deinit {
        if let token = observerToken {
            let center = CFNotificationCenterGetDarwinNotifyCenter()
            CFNotificationCenterRemoveEveryObserver(center, token)
        }
    }

    // MARK: - Darwin observer

    private func registerDarwinObserver() {
        guard observerToken == nil else { return }
        let token = Unmanaged.passUnretained(self).toOpaque()
        observerToken = token
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterAddObserver(
            center,
            token,
            { _, observer, _, _, _ in
                guard let observer else { return }
                let service = Unmanaged<FileProviderFetchService>.fromOpaque(observer).takeUnretainedValue()
                Task { @MainActor in
                    await service.processPendingFetches(reason: "darwin notif")
                }
            },
            AppGroup.fileProviderFetchRequestNotification as CFString,
            nil,
            .deliverImmediately
        )
    }

    // MARK: - Processing

    private func processPendingFetches(reason: String) async {
        // Les callbacks Darwin peuvent réentrer pendant qu'un appel réseau est
        // suspendu. Un seul drain séquentiel évite alors de lancer plusieurs
        // listings librclone concurrents. La notification est mémorisée et un
        // nouveau scan est effectué à la fin du drain courant.
        guard !isDraining else {
            needsAnotherDrain = true
            return
        }
        isDraining = true
        defer { isDraining = false }

        var scanReason = reason
        repeat {
            needsAnotherDrain = false
            await processPendingBatch(reason: scanReason)
            scanReason = "notifications regroupées"
        } while needsAnotherDrain
    }

    private func processPendingBatch(reason: String) async {
        let dir = AppGroup.pendingFetchesDir
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return
        }
        let jsons = entries.filter { $0.pathExtension == "json" }
        if jsons.isEmpty { return }

        let now = Date()
        var requests: [DecodedRequest] = []
        var expiredCount = 0
        var unreadableCount = 0

        for url in jsons {
            guard let data = try? Data(contentsOf: url),
                  let pending = try? JSONDecoder().decode(AppGroupPendingFetch.self, from: data) else {
                unreadableCount += 1
                cleanupIPC(at: url)
                continue
            }
            guard !FileProviderPendingRequestPolicy.isExpired(pending, now: now) else {
                expiredCount += 1
                cleanupIPC(at: url)
                continue
            }
            requests.append(DecodedRequest(url: url, pending: pending))

            if pending.kind == "list" {
                // Accuser réception de tous les waiters AVANT le premier appel
                // Drime. Un doublon plus ancien attendra ainsi le manifest commun
                // au lieu de conclure à tort que l'app est inactive après 1,5 s.
                let statusURL = url.appendingPathExtension("status")
                try? fm.removeItem(at: url.appendingPathExtension("error"))
                writeFetchStatus(
                    stage: "queued",
                    jobID: nil,
                    bytesTransferred: 0,
                    bytesTotal: 0,
                    message: nil,
                    to: statusURL
                )
            }
        }

        requests.sort {
            FileProviderPendingRequestPolicy.shouldProcessBefore($0.pending, $1.pending)
        }

        await LogService.shared.log(
            .debug,
            category: "fileprovider",
            message: "FetchService scan (\(reason)) : \(jsons.count) observée(s), \(requests.count) active(s), \(expiredCount) expirée(s), \(unreadableCount) illisible(s)",
            supportMessage: "operation=listing stage=queued count=\(requests.count) expired_count=\(expiredCount) unreadable_count=\(unreadableCount)"
        )

        var processedListKeys: Set<FileProviderPendingListKey> = []
        for request in requests {
            if let key = FileProviderPendingListKey(request.pending) {
                guard processedListKeys.insert(key).inserted else { continue }

                // Le tri global place la requête interactive la plus récente en
                // tête. Tous les doublons conservent néanmoins leur ACK propre et
                // recevront le même manifest ou la même erreur.
                let group = requests.filter {
                    FileProviderPendingListKey($0.pending) == key
                        && fm.fileExists(atPath: $0.url.path)
                }
                var waiting: [DecodedRequest] = []
                for member in group {
                    if folderManifestIsNewer(
                        than: member.pending.createdAt,
                        pending: member.pending
                    ) {
                        cleanupIPC(at: member.url)
                    } else {
                        waiting.append(member)
                    }
                }
                guard !waiting.isEmpty else { continue }
                await handleListRequests(waiting)
                continue
            }

            // Une autre passe réentrante peut avoir terminé cette requête entre
            // le scan et son tour de boucle.
            guard fm.fileExists(atPath: request.url.path) else { continue }
            await handlePendingURL(request.url, pending: request.pending)
        }
    }

    private func handlePendingURL(_ url: URL, pending: AppGroupPendingFetch) async {
        // Déduplication : si plusieurs notifs Darwin arrivent en série pendant
        // que le download tourne, on évite de relancer le même request.
        if processing.contains(pending.requestID) { return }
        processing.insert(pending.requestID)
        defer { processing.remove(pending.requestID) }

        switch pending.kind {
        case "stream-url":
            await handleStreamURLRequest(pending: pending, pendingURL: url)
        case "list":
            await handleListRequests([DecodedRequest(url: url, pending: pending)])
        default:
            await handleFullDownload(pending: pending, pendingURL: url)
        }
    }

    private func handleListRequests(_ requests: [DecodedRequest]) async {
        guard let leader = requests.first else { return }
        let pending = leader.pending
        await LogService.shared.log(
            .info,
            category: "fileprovider",
            message: "FetchService list \(pending.remote):\(pending.path) waiters=\(requests.count)",
            supportMessage: "operation=listing stage=started waiters=\(requests.count)"
        )

        // Chaque extension attend son propre `.status`. Tous les doublons sont
        // donc maintenus en vie pendant l'unique appel réseau du leader.
        for request in requests {
            writeFetchStatus(
                stage: "running",
                jobID: nil,
                bytesTransferred: 0,
                bytesTotal: 0,
                message: nil,
                to: request.url.appendingPathExtension("status")
            )
        }

        do {
            let entries = try await RemoteService.shared.list(
                remote: pending.remote,
                path: pending.path
            )

            // Une mutation ou une annulation peut supprimer tous les waiters
            // pendant le listing lent. Dans ce cas, ne republie pas un snapshot
            // devenu inutile après leur disparition.
            let activeRequests = requests.filter {
                FileManager.default.fileExists(atPath: $0.url.path)
            }
            guard !activeRequests.isEmpty else {
                await LogService.shared.log(
                    .debug,
                    category: "fileprovider",
                    message: "FetchService list discarded \(pending.remote):\(pending.path) (aucun waiter actif)",
                    supportMessage: "operation=listing stage=cancelled"
                )
                return
            }

            // FileProviderManager écrit le manifest au bon path et signale
            // l'enumerator (que iOS ignorera pour cette requete-ci, mais utile
            // pour les rafraîchissements futurs).
            guard await FileProviderManager.shared.writeFolderManifest(
                remote: pending.remote,
                path: pending.path,
                entries: entries
            ) else {
                throw NSError(
                    domain: "FileProviderFetchService",
                    code: -2,
                    userInfo: [
                        NSLocalizedDescriptionKey: "Le manifest File Provider n'a pas pu être écrit."
                    ]
                )
            }
            let stillActiveRequests = activeRequests.filter {
                FileManager.default.fileExists(atPath: $0.url.path)
            }
            guard !stillActiveRequests.isEmpty else {
                // La mutation a pu annuler les waiters pendant l'écriture du
                // manifest. Retire immédiatement ce snapshot pré-mutation ; le
                // signal post-mutation déclenchera le listing suivant.
                removeFolderManifest(for: pending)
                await LogService.shared.log(
                    .debug,
                    category: "fileprovider",
                    message: "FetchService list unpublished \(pending.remote):\(pending.path) (waiters invalidés)",
                    supportMessage: "operation=listing stage=cancelled"
                )
                return
            }
            await LogService.shared.log(
                .info,
                category: "fileprovider",
                message: "FetchService list done \(pending.remote):\(pending.path) (\(entries.count) entrées, \(stillActiveRequests.count) waiter(s))",
                supportMessage: "operation=listing stage=completed count=\(entries.count) waiters=\(stillActiveRequests.count)"
            )
            for request in stillActiveRequests {
                cleanupIPC(at: request.url)
            }
        } catch {
            let message = error.localizedDescription
            await LogService.shared.log(
                .error,
                category: "fileprovider",
                message: "FetchService list failed \(pending.remote):\(pending.path) : \(message)"
            )
            // Fan-out : tous les waiters coalescés reçoivent la même erreur et
            // aucun doublon ne relance le backend dans ce batch.
            for request in requests where FileManager.default.fileExists(atPath: request.url.path) {
                let errorURL = request.url.appendingPathExtension("error")
                try? Data(message.utf8).write(to: errorURL, options: [.atomic])
                try? FileManager.default.removeItem(at: request.url.appendingPathExtension("status"))
                // Le .error reste disponible pour l'extension, mais le .json ne
                // doit jamais être rejoué au prochain boot si elle a disparu.
                try? FileManager.default.removeItem(at: request.url)
            }
        }
    }

    private func handleFullDownload(pending: AppGroupPendingFetch, pendingURL: URL) async {
        await LogService.shared.log(
            .info,
            category: "fileprovider",
            message: "FetchService download \(pending.remote):\(pending.path)"
        )

        let destination = URL(fileURLWithPath: pending.destPath)
        let parentDirectory = destination.deletingLastPathComponent()
        let partialDestination = parentDirectory.appending(
            path: "\(destination.lastPathComponent).partial-\(pending.requestID)"
        )
        let statusURL = pendingURL.appendingPathExtension("status")
        let errorURL = pendingURL.appendingPathExtension("error")
        var activeJobID: Int?
        do {
            try FileManager.default.createDirectory(
                at: parentDirectory,
                withIntermediateDirectories: true
            )
            try? FileManager.default.removeItem(at: destination)
            try? FileManager.default.removeItem(at: partialDestination)
            try? FileManager.default.removeItem(at: statusURL)
            try? FileManager.default.removeItem(at: errorURL)

            writeFetchStatus(
                stage: "running",
                jobID: nil,
                bytesTransferred: 0,
                bytesTotal: 0,
                message: nil,
                to: statusURL
            )

            // PRÉFÉRÉ : bridge loopback + URLSession (chemin SANS freeze). Le
            // copyfile + polling job/status toutes les 500 ms (core/stats +
            // job/status) saturait le pont RC de librclone et FIGEAIT l'app — le
            // même bug que côté lecteur, réglé en #71. La progression vient ici de
            // didWriteData (local, zéro RPC). Repli copyfile si le bridge échoue.
            if let bridge = await RcloneStreamingService.shared.liveSession(
                remote: pending.remote, path: pending.path
            ) {
                defer { Task { await RcloneStreamingService.shared.stop(bridge) } }
                let downloader = BridgeFileDownloader(dest: partialDestination) { written, total in
                    // L'extension supprime le pending pour annuler → on ne réécrit
                    // plus le statut dans ce cas. Hop MainActor : writeFetchStatus
                    // construit un type isolé MainActor (AppGroupFetchStatus). On
                    // passe par le singleton pour ne PAS capturer `self` (sinon
                    // warning de concurrence → erreur Swift 6).
                    guard FileManager.default.fileExists(atPath: pendingURL.path) else { return }
                    Task { @MainActor in
                        FileProviderFetchService.shared.writeFetchStatus(
                            stage: "running", jobID: nil,
                            bytesTransferred: written, bytesTotal: total,
                            message: nil, to: statusURL
                        )
                    }
                }
                try await downloader.download(from: bridge.url)
            } else {
                let jobID = try await TransferService.shared.copyFileAsync(
                    srcFs: "\(pending.remote):",
                    srcPath: pending.path,
                    dstFs: parentDirectory.path,
                    dstPath: partialDestination.lastPathComponent
                )
                activeJobID = jobID
                try await waitForJob(
                    jobID: jobID,
                    method: "operations/copyfile",
                    remotePath: pending.path,
                    partialURL: partialDestination,
                    statusURL: statusURL,
                    pendingURL: pendingURL
                )
            }

            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: partialDestination, to: destination)
            let finalSize = fileSize(at: destination)
            writeFetchStatus(
                stage: "completed",
                jobID: activeJobID,
                bytesTransferred: finalSize,
                bytesTotal: finalSize,
                message: nil,
                to: statusURL
            )

            await LogService.shared.log(
                .info,
                category: "fileprovider",
                message: "FetchService done \(pending.remote):\(pending.path) → \(destination.lastPathComponent)"
            )
            try? FileManager.default.removeItem(at: pendingURL)
            try? FileManager.default.removeItem(at: statusURL)
            try? FileManager.default.removeItem(at: errorURL)
        } catch {
            if let activeJobID {
                try? await TransferService.shared.stopJob(jobID: activeJobID)
            }
            try? FileManager.default.removeItem(at: partialDestination)

            if !FileManager.default.fileExists(atPath: pendingURL.path) || error is CancellationError {
                try? FileManager.default.removeItem(at: statusURL)
                try? FileManager.default.removeItem(at: errorURL)
                await LogService.shared.log(
                    .debug,
                    category: "fileprovider",
                    message: "FetchService canceled \(pending.remote):\(pending.path)"
                )
                return
            }

            let message = error.localizedDescription
            writeFetchStatus(
                stage: "failed",
                jobID: activeJobID,
                bytesTransferred: fileSize(at: partialDestination),
                bytesTotal: 0,
                message: message,
                to: statusURL
            )
            await LogService.shared.log(
                .error,
                category: "fileprovider",
                message: "FetchService failed \(pending.remote):\(pending.path) : \(message)"
            )
            try? Data(message.utf8).write(to: errorURL, options: [.atomic])
            try? FileManager.default.removeItem(at: pendingURL)
        }
    }

    private func handleStreamURLRequest(pending: AppGroupPendingFetch, pendingURL: URL) async {
        await LogService.shared.log(
            .info,
            category: "fileprovider",
            message: "FetchService stream URL \(pending.remote):\(pending.path)"
        )

        #if canImport(RcloneKit)
        // Bridge Go : démarre un serveur HTTP loopback avec range support pour
        // ce remote+path. Renvoie {"id": "...", "url": "http://127.0.0.1:..."}.
        let raw = RclonebridgeStartFileHTTP(pending.remote, pending.path)
        guard let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sessionID = object["id"] as? String,
              let urlString = object["url"] as? String,
              !sessionID.isEmpty else {
            let message = "Bridge StartFileHTTP a retourné une réponse invalide : \(raw)"
            await LogService.shared.log(.error, category: "fileprovider", message: message)
            let errorURL = pendingURL.appendingPathExtension("error")
            try? Data(message.utf8).write(to: errorURL, options: [.atomic])
            try? FileManager.default.removeItem(at: pendingURL)
            return
        }

        let session = AppGroupStreamSessionInfo(
            sessionID: sessionID,
            url: urlString,
            createdAt: .now
        )
        let urlFile = URL(fileURLWithPath: pending.destPath)
        do {
            try FileManager.default.createDirectory(
                at: urlFile.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let payload = try JSONEncoder().encode(session)
            try payload.write(to: urlFile, options: [.atomic])
            await LogService.shared.log(
                .info,
                category: "fileprovider",
                message: "FetchService stream ready \(pending.remote):\(pending.path) sid=\(sessionID)"
            )
            try? FileManager.default.removeItem(at: pendingURL)
        } catch {
            let message = "stream URL write failed: \(error.localizedDescription)"
            await LogService.shared.log(.error, category: "fileprovider", message: message)
            let errorURL = pendingURL.appendingPathExtension("error")
            try? Data(message.utf8).write(to: errorURL, options: [.atomic])
            try? FileManager.default.removeItem(at: pendingURL)
        }
        #else
        let message = "RcloneKit indisponible pour streaming"
        await LogService.shared.log(.error, category: "fileprovider", message: message)
        let errorURL = pendingURL.appendingPathExtension("error")
        try? Data(message.utf8).write(to: errorURL, options: [.atomic])
        try? FileManager.default.removeItem(at: pendingURL)
        #endif
    }

    private func cleanupIPC(at pendingURL: URL) {
        try? FileManager.default.removeItem(at: pendingURL)
        try? FileManager.default.removeItem(at: pendingURL.appendingPathExtension("status"))
        try? FileManager.default.removeItem(at: pendingURL.appendingPathExtension("error"))
    }

    private func folderManifestIsNewer(
        than requestDate: Date,
        pending: AppGroupPendingFetch
    ) -> Bool {
        let key = "\(pending.remote):\(pending.path)"
        let safe = key.addingPercentEncoding(withAllowedCharacters: .alphanumerics)
            ?? key
        let url = AppGroup.containerURL
            .appending(path: "manifest", directoryHint: .isDirectory)
            .appending(path: "folders", directoryHint: .isDirectory)
            .appending(path: safe)
            .appendingPathExtension("json")
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let modificationDate = attributes[.modificationDate] as? Date else {
            return false
        }
        return modificationDate > requestDate
    }

    private func removeFolderManifest(for pending: AppGroupPendingFetch) {
        let key = "\(pending.remote):\(pending.path)"
        let safe = key.addingPercentEncoding(withAllowedCharacters: .alphanumerics)
            ?? key
        let url = AppGroup.containerURL
            .appending(path: "manifest", directoryHint: .isDirectory)
            .appending(path: "folders", directoryHint: .isDirectory)
            .appending(path: safe)
            .appendingPathExtension("json")
        try? FileManager.default.removeItem(at: url)
    }

    private func waitForJob(
        jobID: Int,
        method: String,
        remotePath: String,
        partialURL: URL,
        statusURL: URL,
        pendingURL: URL
    ) async throws {
        while !Task.isCancelled {
            try await Task.sleep(for: .milliseconds(500))
            guard FileManager.default.fileExists(atPath: pendingURL.path) else {
                throw CancellationError()
            }

            let progress = await fetchProgressSnapshot(partialURL: partialURL, remotePath: remotePath)
            writeFetchStatus(
                stage: "running",
                jobID: jobID,
                bytesTransferred: progress.bytesTransferred,
                bytesTotal: progress.bytesTotal,
                message: nil,
                to: statusURL
            )

            let info = try await TransferService.shared.jobStatus(jobID: jobID)
            if info.finished {
                if info.success { return }
                throw NSError(
                    domain: "FileProviderFetchService",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: info.error ?? "Échec rclone (\(method))"]
                )
            }
        }
        throw CancellationError()
    }

    private func writeFetchStatus(
        stage: String,
        jobID: Int?,
        bytesTransferred: Int64,
        bytesTotal: Int64,
        message: String?,
        to url: URL
    ) {
        let status = AppGroupFetchStatus(
            stage: stage,
            jobID: jobID,
            bytesTransferred: bytesTransferred,
            bytesTotal: bytesTotal,
            updatedAt: .now,
            message: message
        )
        guard let data = try? JSONEncoder().encode(status) else { return }
        try? data.write(to: url, options: [.atomic])
    }

    private func fetchProgressSnapshot(
        partialURL: URL,
        remotePath: String
    ) async -> (bytesTransferred: Int64, bytesTotal: Int64) {
        let localBytes = fileSize(at: partialURL)
        let partialName = partialURL.lastPathComponent
        let sourceName = (remotePath as NSString).lastPathComponent

        guard let stats = try? await TransferService.shared.coreStats(),
              let match = stats.transferring.first(where: { transfer in
                  transfer.name == partialName
                      || transfer.name.hasSuffix("/\(partialName)")
                      || transfer.name == sourceName
                      || transfer.name.hasSuffix("/\(sourceName)")
              }) else {
            return (localBytes, 0)
        }

        return (
            max(localBytes, match.bytesTransferred),
            max(match.bytesTotal, 0)
        )
    }

    private func fileSize(at url: URL) -> Int64 {
        (try? FileManager.default
            .attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
    }
}

/// Télécharge un fichier depuis le bridge loopback via `URLSession` (chemin SANS
/// saturation du pont RC de librclone), avec progression LOCALE (didWriteData,
/// throttlée) et déplacement atomique vers `dest` à la fin. Remplace
/// `operations/copyfile` + le polling `job/status`/`core/stats` qui figeait l'app.
final class BridgeFileDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
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
                config.timeoutIntervalForRequest = 60
                config.requestCachePolicy = .reloadIgnoringLocalCacheData
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
        // Throttle : didWriteData arrive très souvent ; on ne réécrit le statut
        // (fichier disque lu par l'extension) qu'au plus toutes les 0,5 s.
        let now = Date()
        if now.timeIntervalSince(lastProgressAt) >= 0.5 {
            lastProgressAt = now
            onProgress(totalBytesWritten, max(0, totalBytesExpectedToWrite))
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        // location est supprimé au retour → on déplace SYNCHRONEMENT ici.
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
            cont?.resume(throwing: RcloneError.rcloneError(
                code: http.statusCode, method: "bridge/download",
                message: "HTTP \(http.statusCode) en téléchargeant via le bridge (FileProvider)"
            ))
            return
        }
        cont?.resume(returning: ())
    }
}
