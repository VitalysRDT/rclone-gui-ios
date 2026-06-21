//
//  MediaCacheService.swift
//  Rclone GUI — Services
//
//  Media playback cache. Phase D v1 strategy: "download-then-play".
//  Hits operations/copyfile to land the source in a local cache file,
//  then plays it with AVPlayer. Crypt fully transparent because rclone
//  unwraps before writing the local copy.
//
//  Phase D2 (P1) will replace this with `AVAssetResourceLoaderDelegate`
//  + librclone range reads for true streaming (FR-030b in the PRD).
//

import Foundation
import AVFoundation
import Network

public actor MediaCacheService {
    public static let shared = MediaCacheService()
    private init() {}

    // Limite LRU configurable via Settings → Cache. Default 5GB :
    // confortable pour quelques films + photos sans saturer le device.
    // Stocké en UserDefaults pour survivre aux relaunchs.
    private static let defaultMaxSizeBytes: Int64 = 5 * 1024 * 1024 * 1024
    private static let maxSizeKey = "mediaCache.maxSizeBytes"
    private static let staleAfter: TimeInterval = 24 * 60 * 60

    /// Plafond de débit appliqué pendant un téléchargement pour lecture (octets/s).
    /// ~8 Mbit/s : laisse de la marge à rclone pour que l'app reste fluide (un
    /// download plein débit le saturait et figeait l'UI). Ajustable.
    static let mediaDownloadCapBytes: Int64 = 1_048_576

    public var maxSizeBytes: Int64 {
        let stored = UserDefaults.standard.object(forKey: Self.maxSizeKey) as? Int64
        return stored.flatMap { $0 > 0 ? $0 : nil } ?? Self.defaultMaxSizeBytes
    }

    public func setMaxSizeBytes(_ bytes: Int64) {
        UserDefaults.standard.set(bytes, forKey: Self.maxSizeKey)
    }

    /// Returns a local URL ready to feed to `AVPlayer`. Will download
    /// the file (cached on subsequent calls if `policy == .reuseIfCached`).
    public func localPlayableURL(
        remote: String,
        path: String,
        sizeHint: Int64? = nil,
        policy: CachePolicy = .reuseIfCached
    ) async throws -> URL {
        let cacheURL = Self.cacheURL(remote: remote, path: path)
        let fm = FileManager.default

        if policy == .reuseIfCached, fm.fileExists(atPath: cacheURL.path) {
            // Bumper la date d'accès pour préserver la fraîcheur LRU.
            try? fm.setAttributes([.modificationDate: Date()], ofItemAtPath: cacheURL.path)
            return cacheURL
        }

        try fm.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        // Anticipation : si on sait que ce nouveau fichier dépasserait la
        // limite, on évince d'abord.
        if let sizeHint, sizeHint > 0 {
            try? evictIfNeeded(reservingBytes: sizeHint)
        }

        // Plafonne le débit du download le temps du transfert : un download plein
        // débit sature le process rclone et FIGE l'app (même à l'inactivité, où le
        // throttle d'activité repasse au ceiling utilisateur illimité). Le cap
        // laisse de la marge → l'app reste fluide. Retiré à la fin (defer).
        await TransferQueue.shared.setMediaDownloadCap(Self.mediaDownloadCapBytes)
        defer { Task { await TransferQueue.shared.setMediaDownloadCap(0) } }

        // PRÉFÉRÉ : télécharger via le bridge loopback HTTP + URLSession natif,
        // PAS via operations/copyfile + polling job/status. Le copyfile + le poll
        // saturent le pont RC de librclone et FIGENT l'app (cf. revue multi-IA) ;
        // le bridge sert le fichier en un GET séquentiel et iOS gère l'écriture
        // disque + la backpressure côté noyau → plus de contention RPC.
        do {
            try await downloadViaBridge(remote: remote, path: path, to: cacheURL)
        } catch is BridgeUnavailable {
            // Repli : copyfile RC classique si le bridge n'a pas pu démarrer.
            let jobID = try await TransferService.shared.copyFileAsync(
                srcFs: "\(remote):",
                srcPath: path,
                dstFs: cacheURL.deletingLastPathComponent().path,
                dstPath: cacheURL.lastPathComponent
            )
            try await waitForJob(jobID: jobID)
        }
        // Post-download : éviction au cas où le fichier réel est plus gros
        // que sizeHint (ou qu'il n'y avait pas de hint).
        try? evictIfNeeded(reservingBytes: 0)
        return cacheURL
    }

    private struct BridgeUnavailable: Error {}

    /// Télécharge le fichier distant via le bridge loopback HTTP (déjà utilisé
    /// pour le streaming) + URLSession natif. Remplace operations/copyfile + le
    /// polling job/status, qui saturaient le pont RC de librclone et figeaient
    /// l'app. Foreground (URLSession.background ne sait pas atteindre localhost).
    private func downloadViaBridge(remote: String, path: String, to dest: URL) async throws {
        guard let session = await RcloneStreamingService.shared.liveSession(
            remote: remote, path: path
        ) else {
            throw BridgeUnavailable()
        }
        defer { Task { await RcloneStreamingService.shared.stop(session) } }

        let (tempURL, response) = try await URLSession.shared.download(from: session.url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw RcloneError.rcloneError(
                code: http.statusCode, method: "bridge/download",
                message: "HTTP \(http.statusCode) en téléchargeant via le bridge"
            )
        }
        let fm = FileManager.default
        if fm.fileExists(atPath: dest.path) { try? fm.removeItem(at: dest) }
        try fm.moveItem(at: tempURL, to: dest)
    }

    /// Supprime les fichiers les moins récemment accédés jusqu'à passer
    /// sous `maxSizeBytes - reservingBytes`. Appelé avant + après chaque
    /// download pour borner le cache (Phase E2).
    public func evictIfNeeded(reservingBytes: Int64 = 0) throws {
        let fm = FileManager.default
        let root = Self.cacheRoot
        guard fm.fileExists(atPath: root.path) else { return }
        let target = max(0, maxSizeBytes - reservingBytes)

        struct Entry { let url: URL; let size: Int64; let mtime: Date }
        var entries: [Entry] = []
        var total: Int64 = 0
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: keys) else { return }
        for case let url as URL in enumerator {
            let res = try? url.resourceValues(forKeys: Set(keys))
            guard res?.isRegularFile == true else { continue }
            let size = Int64(res?.fileSize ?? 0)
            let mtime = res?.contentModificationDate ?? .distantPast
            entries.append(Entry(url: url, size: size, mtime: mtime))
            total += size
        }
        guard total > target else { return }

        // Évince du plus ancien au plus récent jusqu'à passer sous la cible.
        entries.sort { $0.mtime < $1.mtime }
        for entry in entries {
            if total <= target { break }
            try? fm.removeItem(at: entry.url)
            total -= entry.size
        }
    }

    /// Supprime les fichiers temporaires `.partial-*` plus vieux que 24h.
    /// Ces partials sont laissés par les downloads interrompus côté
    /// AppGroupBridge — sans cleanup, ils s'accumulent.
    @discardableResult
    public func cleanupStalePartials() throws -> Int {
        let fm = FileManager.default
        let root = Self.cacheRoot
        guard fm.fileExists(atPath: root.path) else { return 0 }
        let now = Date()
        var removed = 0
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: keys) else { return 0 }
        for case let url as URL in enumerator {
            let name = url.lastPathComponent
            guard name.hasPrefix(".partial-") || name.hasSuffix(".partial") else { continue }
            let res = try? url.resourceValues(forKeys: Set(keys))
            guard res?.isRegularFile == true else { continue }
            let mtime = res?.contentModificationDate ?? now
            if now.timeIntervalSince(mtime) > Self.staleAfter {
                try? fm.removeItem(at: url)
                removed += 1
            }
        }
        return removed
    }

    public func purge() throws {
        let fm = FileManager.default
        let root = Self.cacheRoot
        if fm.fileExists(atPath: root.path) {
            try fm.removeItem(at: root)
        }
    }

    public func currentSize() throws -> Int64 {
        let fm = FileManager.default
        let root = Self.cacheRoot
        guard fm.fileExists(atPath: root.path) else { return 0 }
        var total: Int64 = 0
        if let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey]) {
            for case let url as URL in enumerator {
                let res = try url.resourceValues(forKeys: [.fileSizeKey])
                total += Int64(res.fileSize ?? 0)
            }
        }
        return total
    }

    public enum CachePolicy: Sendable {
        case reuseIfCached
        case alwaysFresh
    }

    // MARK: - Internals

    private func waitForJob(jobID: Int) async throws {
        while !Task.isCancelled {
            // 2 s (et non 500 ms) : pendant un gros download rclone est saturé,
            // chaque job/status met 1–4 s et un poll trop fréquent monopolise le
            // bridge RPC → l'app rame. 2 s suffit largement pour un transfert long.
            try await Task.sleep(for: .seconds(2))
            let info = try await TransferService.shared.jobStatus(jobID: jobID)
            if info.finished {
                if info.success { return }
                throw RcloneError.rcloneError(
                    code: -1,
                    method: "operations/copyfile",
                    message: info.error ?? "Échec téléchargement pour lecture"
                )
            }
        }
        throw CancellationError()
    }

    static var cacheRoot: URL {
        let caches = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return caches.appending(path: "MediaCache", directoryHint: .isDirectory)
    }

    static func cacheURL(remote: String, path: String) -> URL {
        // Encode the remote name + path into a flat filename to avoid
        // surprises when the path contains "/" or special characters.
        let safe = (remote + ":" + path).addingPercentEncoding(
            withAllowedCharacters: .alphanumerics
        ) ?? UUID().uuidString
        let ext = (path as NSString).pathExtension
        var url = cacheRoot.appending(path: safe)
        if !ext.isEmpty {
            url = url.appendingPathExtension(ext)
        }
        return url
    }
}

// MARK: - Cache progressif (download-ahead)

/// Télécharge un média distant SÉQUENTIELLEMENT dans un fichier de cache local
/// et le sert simultanément via un petit proxy HTTP loopback. Le lecteur (VLC)
/// lit le proxy comme un fichier complet (`Content-Length` = taille totale) ;
/// les octets pas encore téléchargés font patienter la connexion jusqu'à leur
/// arrivée (avec un plafond de 10 s pour ne pas bloquer un seek hors-zone).
///
/// But : « précharge ~1 min puis lit en LOCAL pendant que le reste continue de
/// se télécharger ». Comme le download est SÉQUENTIEL depuis le bridge (zéro
/// re-seek SFTP) et plus rapide que la lecture temps-réel, le buffer ne se vide
/// plus → fini les saccades, et les seeks dans la zone téléchargée sont
/// instantanés (données locales). À la fin, le `.partial` devient le fichier de
/// cache final (lecture instantanée à la prochaine ouverture).
final class ProgressiveMediaCache: NSObject, @unchecked Sendable {
    private let sourceURL: URL      // bridge loopback servant le fichier distant
    private let partialURL: URL     // fichier local en cours de remplissage
    private let finalURL: URL       // destination cache une fois complet
    private let fileName: String    // pour donner l'extension au lecteur

    private let lock = NSLock()
    private var _available: Int64 = 0
    private var _total: Int64 = -1
    private enum DLState { case downloading, complete, failed }
    private var _state: DLState = .downloading

    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var writeHandle: FileHandle?
    private var listener: NWListener?
    private let serverQueue = DispatchQueue(label: "rclone.progressivecache.server", attributes: .concurrent)
    private var stopped = false

    var available: Int64 { lock.lock(); defer { lock.unlock() }; return _available }
    var total: Int64 { lock.lock(); defer { lock.unlock() }; return _total }
    var isComplete: Bool { lock.lock(); defer { lock.unlock() }; return _state == .complete }
    var isFailed: Bool { lock.lock(); defer { lock.unlock() }; return _state == .failed }

    init(sourceURL: URL, finalURL: URL, fileName: String) {
        self.sourceURL = sourceURL
        self.finalURL = finalURL
        self.partialURL = finalURL.appendingPathExtension("partial")
        self.fileName = fileName
        super.init()
    }

    /// Démarre le proxy + le téléchargement. Renvoie l'URL loopback à donner au
    /// lecteur. Lève si le proxy ne peut pas démarrer (→ repli streaming direct).
    func start() throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: partialURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: partialURL.path) { try? fm.removeItem(at: partialURL) }
        fm.createFile(atPath: partialURL.path, contents: nil)
        writeHandle = try FileHandle(forWritingTo: partialURL)

        // Proxy HTTP loopback (port éphémère)
        let params = NWParameters.tcp
        params.requiredInterfaceType = .loopback
        let listener = try NWListener(using: params, on: .any)
        self.listener = listener
        listener.newConnectionHandler = { [weak self] conn in
            conn.start(queue: self?.serverQueue ?? .global())
            self?.receiveRequest(conn, buffer: Data())
        }
        let ready = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready, .failed, .cancelled: ready.signal()
            default: break
            }
        }
        listener.start(queue: serverQueue)
        _ = ready.wait(timeout: .now() + 5)
        guard let port = listener.port?.rawValue else {
            listener.cancel()
            throw RcloneError.rcloneError(code: -1, method: "progressivecache", message: "proxy loopback indisponible")
        }

        // Téléchargement séquentiel depuis le bridge (un seul GET, pas de re-seek)
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 60
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        self.session = session
        var req = URLRequest(url: sourceURL)
        req.setValue("bytes=0-", forHTTPHeaderField: "Range")
        let task = session.dataTask(with: req)
        self.task = task
        task.resume()

        let encodedName = fileName.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "media"
        return URL(string: "http://127.0.0.1:\(port)/\(encodedName)")!
    }

    /// Attend que `bytes` octets soient disponibles (précharge), ou que le
    /// téléchargement se termine/échoue.
    func waitForPrefill(bytes: Int64) async {
        while !Task.isCancelled {
            if isFailed || isComplete { return }
            let avail = available
            if avail >= bytes { return }
            let t = total
            if t >= 0 && avail >= t { return }
            try? await Task.sleep(for: .milliseconds(150))
        }
    }

    func stop() {
        lock.lock(); let wasStopped = stopped; stopped = true; let complete = _state == .complete; lock.unlock()
        guard !wasStopped else { return }
        task?.cancel(); task = nil
        session?.invalidateAndCancel(); session = nil
        listener?.cancel(); listener = nil
        try? writeHandle?.close(); writeHandle = nil
        let fm = FileManager.default
        if complete {
            // partial → final : cache hit à la prochaine ouverture.
            try? fm.removeItem(at: finalURL)
            try? fm.moveItem(at: partialURL, to: finalURL)
        } else {
            // Incomplet : NE PAS le laisser passer pour un cache complet.
            try? fm.removeItem(at: partialURL)
        }
    }

    // MARK: Serveur HTTP loopback

    private func receiveRequest(_ conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { conn.cancel(); return }
            var buf = buffer
            if let data { buf.append(data) }
            if let r = buf.range(of: Data("\r\n\r\n".utf8)) {
                let head = String(decoding: buf.subdata(in: buf.startIndex..<r.lowerBound), as: UTF8.self)
                self.respond(conn, head: head, attempt: 0)
                return
            }
            if error != nil || isComplete || buf.count > 64 * 1024 { conn.cancel(); return }
            self.receiveRequest(conn, buffer: buf)
        }
    }

    private func respond(_ conn: NWConnection, head: String, attempt: Int) {
        // La taille totale n'est connue qu'après la 1re réponse du bridge :
        // on patiente brièvement (non bloquant) si besoin.
        if total < 0 {
            if isFailed || attempt > 200 { sendStatus(conn, "503 Service Unavailable"); return }
            serverQueue.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.respond(conn, head: head, attempt: attempt + 1)
            }
            return
        }
        let totalBytes = total
        guard totalBytes > 0 else { sendStatus(conn, "503 Service Unavailable"); return }

        var start: Int64 = 0
        var end: Int64 = totalBytes - 1
        for line in head.split(separator: "\r\n") where line.lowercased().hasPrefix("range:") {
            let spec = line.drop(while: { $0 != "=" }).dropFirst()
            let parts = spec.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
            if let s = parts.first, let v = Int64(s.trimmingCharacters(in: .whitespaces)) { start = v }
            if parts.count > 1, let e = Int64(parts[1].trimmingCharacters(in: .whitespaces)) { end = min(e, totalBytes - 1) }
        }
        start = max(0, min(start, totalBytes - 1))
        if end < start { end = totalBytes - 1 }
        let length = end - start + 1

        var header = "HTTP/1.1 206 Partial Content\r\n"
        header += "Content-Type: application/octet-stream\r\n"
        header += "Accept-Ranges: bytes\r\n"
        header += "Content-Length: \(length)\r\n"
        header += "Content-Range: bytes \(start)-\(end)/\(totalBytes)\r\n"
        header += "Connection: close\r\n\r\n"
        conn.send(content: Data(header.utf8), completion: .contentProcessed { [weak self] err in
            guard let self, err == nil else { conn.cancel(); return }
            guard let readHandle = try? FileHandle(forReadingFrom: self.partialURL) else { conn.cancel(); return }
            self.pump(conn, readHandle, pos: start, end: end, waited: 0)
        })
    }

    /// Envoie les octets [pos, end] par chunks, en patientant (non bloquant) que
    /// le téléchargement atteigne `pos`. Plafond d'attente 10 s → un seek dans une
    /// zone pas encore téléchargée échoue proprement au lieu de bloquer.
    private func pump(_ conn: NWConnection, _ readHandle: FileHandle, pos: Int64, end: Int64, waited: Double) {
        if pos > end { try? readHandle.close(); conn.cancel(); return }
        let avail = available
        if avail <= pos {
            if isFailed || isComplete || waited > 10 { try? readHandle.close(); conn.cancel(); return }
            serverQueue.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.pump(conn, readHandle, pos: pos, end: end, waited: waited + 0.05)
            }
            return
        }
        let chunkEnd = min(end, avail - 1)
        let want = Int(min(chunkEnd - pos + 1, 256 * 1024))
        try? readHandle.seek(toOffset: UInt64(pos))
        let data = (try? readHandle.read(upToCount: want)) ?? Data()
        if data.isEmpty {
            serverQueue.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.pump(conn, readHandle, pos: pos, end: end, waited: waited + 0.05)
            }
            return
        }
        conn.send(content: data, completion: .contentProcessed { [weak self] err in
            guard let self, err == nil else { try? readHandle.close(); conn.cancel(); return }
            self.pump(conn, readHandle, pos: pos + Int64(data.count), end: end, waited: 0)
        })
    }

    private func sendStatus(_ conn: NWConnection, _ status: String) {
        let header = "HTTP/1.1 \(status)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        conn.send(content: Data(header.utf8), completion: .contentProcessed { _ in conn.cancel() })
    }
}

extension ProgressiveMediaCache: URLSessionDataDelegate {
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        let len = response.expectedContentLength
        lock.lock(); if _total < 0, len > 0 { _total = len }; lock.unlock()
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        let stopped = stopped
        lock.unlock()
        guard !stopped else { return }
        // Écrit sur disque PUIS publie le nouveau disponible (les lecteurs ne
        // lisent jamais au-delà de `_available` = octets garantis écrits).
        do {
            try writeHandle?.write(contentsOf: data)
        } catch {
            lock.lock(); _state = .failed; lock.unlock()
            return
        }
        lock.lock(); _available += Int64(data.count); lock.unlock()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        try? writeHandle?.synchronize()
        lock.lock()
        if let error {
            // L'annulation volontaire (stop) n'est pas un échec à reporter.
            if (error as NSError).code != NSURLErrorCancelled { _state = .failed }
        } else {
            _state = .complete
            if _total < 0 { _total = _available }
        }
        lock.unlock()
    }
}
