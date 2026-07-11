//
//  RemoteRangeReader.swift
//  Rclone GUI — Services
//
//  Primitive de lecture PARTIELLE d'un fichier distant via le bridge loopback
//  range-capable (`RcloneStreamingService.liveSession` → serveur Go
//  `StartFileHTTP`, qui gère HEAD + `Range: bytes=` + 206). Une seule session
//  loopback est ouverte pour toute la durée de `withSession` (jamais un serveur
//  par plage), puis arrêtée en `defer`.
//
//  `RangeByteSource` est une petite abstraction Sendable (closures) avec deux
//  fabriques : `.loopback` (réseau) et `.inMemory` (tests, sans réseau).
//

import Foundation

/// Source d'octets adressable par plage. Type-erased (closures) pour rester
/// Sendable et testable sans réseau via `.inMemory`.
public nonisolated struct RangeByteSource: Sendable {
    private let _size: @Sendable () async -> Int64?
    private let _read: @Sendable (ClosedRange<Int64>) async -> Data?

    public init(
        size: @escaping @Sendable () async -> Int64?,
        read: @escaping @Sendable (ClosedRange<Int64>) async -> Data?
    ) {
        self._size = size
        self._read = read
    }

    /// Taille totale du fichier en octets (nil si inconnue/erreur).
    public func size() async -> Int64? { await _size() }

    /// Lit la plage `[a, b]` (bornes incluses). Renvoie nil sur erreur.
    public func read(_ range: ClosedRange<Int64>) async -> Data? { await _read(range) }

    // MARK: - Fabriques

    /// Source réseau : HEAD pour la taille, GET `Range: bytes=a-b` pour les plages.
    public static func loopback(baseURL: URL, urlSession: URLSession = .shared) -> RangeByteSource {
        RangeByteSource(
            size: {
                var req = URLRequest(url: baseURL)
                req.httpMethod = "HEAD"
                req.cachePolicy = .reloadIgnoringLocalCacheData
                guard let (_, resp) = try? await urlSession.data(for: req),
                      let http = resp as? HTTPURLResponse else { return nil }
                if let len = http.value(forHTTPHeaderField: "Content-Length"),
                   let n = Int64(len), n >= 0 { return n }
                let expected = http.expectedContentLength
                return expected >= 0 ? expected : nil
            },
            read: { range in
                var req = URLRequest(url: baseURL)
                req.httpMethod = "GET"
                req.setValue("bytes=\(range.lowerBound)-\(range.upperBound)",
                             forHTTPHeaderField: "Range")
                req.cachePolicy = .reloadIgnoringLocalCacheData
                guard let (data, _) = try? await urlSession.data(for: req) else { return nil }
                // Défensif : si le serveur ignore le Range et renvoie tout (200),
                // on ne garde que la plage demandée.
                let want = range.upperBound - range.lowerBound + 1
                if Int64(data.count) > want, want > 0, want <= Int64(Int.max) {
                    return data.prefix(Int(want))
                }
                return data
            }
        )
    }

    /// Source en mémoire (tests, aperçu depuis des octets déjà en main).
    public static func inMemory(_ data: Data) -> RangeByteSource {
        let total = Int64(data.count)
        return RangeByteSource(
            size: { total },
            read: { range in
                guard range.lowerBound >= 0, range.lowerBound < total else { return nil }
                let end = min(range.upperBound, total - 1)
                let lo = Int(range.lowerBound)
                let hi = Int(end)
                return data.subdata(in: lo..<(hi + 1))
            }
        )
    }
}

/// Ouvre une session loopback pour `remote:path`, exécute `body` avec une
/// `RangeByteSource` réseau, puis arrête la session. Renvoie nil si le bridge
/// est indisponible.
public nonisolated enum RemoteRangeReader {
    public static func withSession<T>(
        remote: String,
        path: String,
        _ body: (RangeByteSource) async throws -> T
    ) async rethrows -> T? {
        guard let session = await RcloneStreamingService.shared.liveSession(
            remote: remote, path: path
        ) else { return nil }
        defer { Task { await RcloneStreamingService.shared.stop(session) } }
        return try await body(.loopback(baseURL: session.url))
    }
}
