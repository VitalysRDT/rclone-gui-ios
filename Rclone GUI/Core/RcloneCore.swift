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
        // Resolve the imported rclone.conf path. ConfigStore decrypts the
        // ChaChaPoly envelope and writes a plaintext copy to Caches/.
        let confPath: String
        do {
            let confURL = try await ConfigStore.shared.writeDecryptedToTempFile()
            confPath = confURL.path
        } catch {
            throw RcloneError.engineNotAvailable(
                "Aucune configuration rclone importée. Importe d'abord depuis Réglages."
            )
        }
        // RCLONE_CONFIG is intentionally set even though rclone v1.68 does
        // NOT honor it as a config path (it's only consulted at package
        // init() as a boolean to decide whether to skip mkdir of the
        // default config dir — see fs/config/config.go:254). We set it
        // anyway so the Diagnostic JSON surfaces the intended path.
        engine.setEnv(name: "RCLONE_CONFIG", value: confPath)
        try await engine.initialize()
        // The actual override that makes rclone read OUR file: invoke the
        // built-in `config/setpath` RPC, which calls config.SetConfigPath.
        // Initialize() only installs the storage handler; the file isn't
        // read until first config access, so setpath here is in time.
        struct SetPathInput: Encodable { let path: String }
        let payloadData = try JSONEncoder().encode(SetPathInput(path: confPath))
        let pathPayload = String(decoding: payloadData, as: UTF8.self)
        _ = try await engine.rpcRaw(method: "config/setpath", inputJSON: pathPayload)
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
