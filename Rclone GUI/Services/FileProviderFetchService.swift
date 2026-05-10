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
            // Si un fichier traîne (re-tentative), on repart propre.
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
            // L'extension polle destination ; rien à signaler à iOS depuis ici.
            // On supprime juste le pending pour signaler "traité".
            try? FileManager.default.removeItem(at: url)
        } catch {
            let message = error.localizedDescription
            await LogService.shared.log(
                .error,
                category: "fileprovider",
                message: "FetchService failed \(pending.remote):\(pending.path) : \(message)"
            )
            // Sibling .error pour que l'extension propage l'erreur à iOS.
            let errorURL = url.appendingPathExtension("error")
            try? Data(message.utf8).write(to: errorURL, options: [.atomic])
        }
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
