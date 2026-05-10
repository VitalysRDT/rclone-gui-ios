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
//      via TransferService.copyFileAsync (qui hit operations/copyfile),
//      puis supprime le pending.
//   3. L'extension polle destPath toutes les 250ms ; quand le fichier
//      apparaît elle le retourne à iOS via fetchContents completion.
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
        do {
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? FileManager.default.removeItem(at: destination)

            let jobID = try await TransferService.shared.copyFileAsync(
                srcFs: "\(pending.remote):",
                srcPath: pending.path,
                dstFs: destination.deletingLastPathComponent().path,
                dstPath: destination.lastPathComponent
            )
            try await waitForJob(jobID: jobID, method: "operations/copyfile")

            await LogService.shared.log(
                .info,
                category: "fileprovider",
                message: "FetchService done \(pending.remote):\(pending.path) → \(destination.lastPathComponent)"
            )
            try? FileManager.default.removeItem(at: pendingURL)
        } catch {
            let message = error.localizedDescription
            await LogService.shared.log(
                .error,
                category: "fileprovider",
                message: "FetchService failed \(pending.remote):\(pending.path) : \(message)"
            )
            let errorURL = pendingURL.appendingPathExtension("error")
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

    private func waitForJob(jobID: Int, method: String) async throws {
        while !Task.isCancelled {
            try await Task.sleep(for: .milliseconds(500))
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
}
