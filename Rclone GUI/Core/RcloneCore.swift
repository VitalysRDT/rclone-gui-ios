//
//  RcloneCore.swift
//  Rclone GUI — Core
//
//  Singleton actor that exposes typed and raw access to rclone RPC.
//  Delegates to a concrete RcloneEngine (Librclone or Mock).
//
//  Usage:
//    let version = try await RcloneCore.shared.version()
//    let listJSON = try await RcloneCore.shared.rpcRaw("config/listremotes")
//

import Foundation

public actor RcloneCore {
    public static let shared = makeShared()

    private let engine: any RcloneEngine
    private var initialized = false

    /// Empty payload used by rc methods that accept no input.
    /// Defined at the actor level (not nested in a generic function,
    /// which Swift forbids).
    private struct EmptyInput: Encodable {}

    /// `true` when the in-process engine is the mock (no real librclone).
    /// Used by the UI to show a "mock mode" banner.
    public var isMockEngine: Bool {
        engine is MockRcloneEngine
    }

    public init(engine: any RcloneEngine) {
        self.engine = engine
    }

    // MARK: - Raw RPC

    /// Send a raw RPC call. Lazily initializes the engine on first use.
    public func rpcRaw(_ method: String, _ inputJSON: String = "{}") async throws -> String {
        try await ensureInit()
        return try await engine.rpcRaw(method: method, inputJSON: inputJSON)
    }

    // MARK: - Typed RPC helpers

    /// Send an RPC with `Codable` input/output.
    public func rpc<I: Encodable, O: Decodable>(_ method: String, input: I) async throws -> O {
        try await ensureInit()
        let inputData = try JSONEncoder().encode(input)
        let inputJSON = String(decoding: inputData, as: UTF8.self)
        let outputJSON = try await engine.rpcRaw(method: method, inputJSON: inputJSON)
        let outputData = Data(outputJSON.utf8)
        do {
            return try JSONDecoder().decode(O.self, from: outputData)
        } catch {
            throw RcloneError.invalidJSON(method: method, raw: outputJSON, underlying: error)
        }
    }

    /// Send an RPC with no input.
    public func rpc<O: Decodable>(_ method: String) async throws -> O {
        return try await rpc(method, input: EmptyInput())
    }

    // MARK: - Convenience

    /// `core/version` → `version` field.
    public func version() async throws -> String {
        struct Response: Decodable { let version: String }
        let resp: Response = try await rpc("core/version")
        return resp.version
    }

    /// `config/listremotes` → array of remote names.
    public func listRemoteNames() async throws -> [String] {
        struct Response: Decodable { let remotes: [String] }
        let resp: Response = try await rpc("config/listremotes")
        return resp.remotes
    }

    // MARK: - Init

    private func ensureInit() async throws {
        guard !initialized else { return }
        // Point librclone at the imported rclone.conf via RCLONE_CONFIG.
        // We MUST go through engine.setEnv (which calls os.Setenv inside
        // the Go runtime) — host-side setenv(3) is invisible because
        // gomobile caches environ at framework-load time. The previous
        // implementation used POSIX setenv and rclone fell back to its
        // default path, logging "Config file not found - using defaults".
        do {
            let confURL = try await ConfigStore.shared.writeDecryptedToTempFile()
            engine.setEnv(name: "RCLONE_CONFIG", value: confURL.path)
        } catch {
            // No config yet — librclone will start with defaults but the
            // app should already be on the import screen, so RPCs aren't
            // expected before a conf is stored. Surface a clear error.
            throw RcloneError.engineNotAvailable(
                "Aucune configuration rclone importée. Importe d'abord depuis Réglages."
            )
        }
        try await engine.initialize()
        initialized = true
    }

    /// Returns the engine's diagnostic JSON. Surfaced in Settings → Diagnostic
    /// to help confirm that `RCLONE_CONFIG` is wired through to the Go runtime.
    public func diagnosticJSON() -> String {
        engine.diagnosticJSON()
    }



    // MARK: - Factory

    private static func makeShared() -> RcloneCore {
        #if canImport(RcloneKit)
        return RcloneCore(engine: LibrcloneEngine())
        #else
        return RcloneCore(engine: MockRcloneEngine())
        #endif
    }
}
