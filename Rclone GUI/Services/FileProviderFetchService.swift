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

@MainActor
public final class FileProviderFetchService {
    public static let shared = FileProviderFetchService()
    private init() {}

    private var observerToken: UnsafeMutableRawPointer?
    private var processing: Set<String> = []

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
        let dir = AppGroup.pendingFetchesDir
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return
        }
        let jsons = entries.filter { $0.pathExtension == "json" }
        if jsons.isEmpty { return }

        await LogService.shared.log(
            .debug,
            category: "fileprovider",
            message: "FetchService scan (\(reason)) : \(jsons.count) demande(s)"
        )

        for url in jsons {
            await handlePendingURL(url)
        }
    }

    private func handlePendingURL(_ url: URL) async {
        guard let data = try? Data(contentsOf: url),
              let pending = try? JSONDecoder().decode(AppGroupPendingFetch.self, from: data) else {
            await LogService.shared.log(
                .error,
                category: "fileprovider",
                message: "FetchService : pending illisible \(url.lastPathComponent)"
            )
            try? FileManager.default.removeItem(at: url)
            return
        }

        // Déduplication : si plusieurs notifs Darwin arrivent en série pendant
        // que le download tourne, on évite de relancer le même request.
        if processing.contains(pending.requestID) { return }
        processing.insert(pending.requestID)
        defer { processing.remove(pending.requestID) }

        switch pending.kind {
        case "stream-url":
            await handleStreamURLRequest(pending: pending, pendingURL: url)
        case "list":
            await handleListRequest(pending: pending, pendingURL: url)
        default:
            await handleFullDownload(pending: pending, pendingURL: url)
        }
    }

    private func handleListRequest(pending: AppGroupPendingFetch, pendingURL: URL) async {
        await LogService.shared.log(
            .info,
            category: "fileprovider",
            message: "FetchService list \(pending.remote):\(pending.path)"
        )

        do {
            let entries = try await RemoteService.shared.list(
                remote: pending.remote,
                path: pending.path
            )
            // FileProviderManager écrit le manifest au bon path et signale
            // l'enumerator (que iOS ignorera pour cette requete-ci, mais utile
            // pour les rafraîchissements futurs).
            await FileProviderManager.shared.writeFolderManifest(
                remote: pending.remote,
                path: pending.path,
                entries: entries
            )
            await LogService.shared.log(
                .info,
                category: "fileprovider",
                message: "FetchService list done \(pending.remote):\(pending.path) (\(entries.count) entrées)"
            )
            try? FileManager.default.removeItem(at: pendingURL)
        } catch {
            let message = error.localizedDescription
            await LogService.shared.log(
                .error,
                category: "fileprovider",
                message: "FetchService list failed \(pending.remote):\(pending.path) : \(message)"
            )
            let errorURL = pendingURL.appendingPathExtension("error")
            try? Data(message.utf8).write(to: errorURL, options: [.atomic])
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
        }
        #else
        let message = "RcloneKit indisponible pour streaming"
        await LogService.shared.log(.error, category: "fileprovider", message: message)
        let errorURL = pendingURL.appendingPathExtension("error")
        try? Data(message.utf8).write(to: errorURL, options: [.atomic])
        #endif
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
