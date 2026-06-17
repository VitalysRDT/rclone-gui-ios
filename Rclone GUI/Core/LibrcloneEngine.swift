//
//  LibrcloneEngine.swift
//  Rclone GUI — Core
//
//  Real engine bridging to librclone via the gomobile-generated
//  RcloneKit.xcframework. Wired against the `rclonebridge` Go package
//  (scripts/rclone-bridge/) which wraps librclone with a struct return
//  type because gomobile can't bind functions returning (string, int).
//
//  Compiled only when `RcloneKit` can be imported — when the xcframework
//  is missing, the project falls back to MockRcloneEngine automatically
//  (see RcloneCore.makeShared()).
//
//  IMPORTANT — environment variables:
//  gomobile boots the Go runtime at framework-load time and caches
//  `environ` in an internal table. Host-side `setenv(3)` from Swift is
//  NOT visible to `os.Getenv` after that point. Always go through
//  `setEnv(name:value:)`, which routes through the Go bridge so the
//  rclone runtime sees the value before `Initialize()` reads it.
//

#if canImport(RcloneKit)
import Foundation
import RcloneKit

public struct LibrcloneEngine: RcloneEngine {
    public nonisolated init() {}

    public nonisolated func setEnv(name: String, value: String) {
        RclonebridgeSetEnv(name, value)
    }

    public nonisolated func diagnosticJSON() -> String {
        RclonebridgeDiagnostic()
    }

    public nonisolated func initialize() async throws {
        // RclonebridgeInitialize est synchrone et peut prendre quelques
        // ms — on le pousse hors du main thread pour ne pas freezer l'UI
        // au tout premier RPC.
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                RclonebridgeInitialize()
                // Phase E2 — démarre la capture des logs internes rclone (slog)
                // pour que Réglages → Logs montre l'activité réelle du moteur.
                RclonebridgeStartLogCapture()
                continuation.resume()
            }
        }
    }

    public nonisolated func decryptConfig(path: String, password: String) async throws -> String {
        // Même contrainte que rpcRaw : appel Go/cgo synchrone, on sort du
        // MainActor pour ne pas bloquer l'UI pendant le déchiffrement.
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let result = RclonebridgeDecryptConfig(path, password) else {
                    continuation.resume(throwing: RcloneError.rcloneError(
                        code: 0,
                        method: "bridge/decryptConfig",
                        message: "rclonebridge returned nil — bridge not initialised?"
                    ))
                    return
                }
                if (200..<300).contains(Int(result.status)) {
                    continuation.resume(returning: result.output)
                } else {
                    continuation.resume(throwing: RcloneError.configPasswordIncorrect)
                }
            }
        }
    }

    public nonisolated func rpcRaw(method: String, inputJSON: String) async throws -> String {
        // RclonebridgeRPC est un appel Go/cgo synchrone qui bloque le
        // thread appelant pendant toute la durée du RPC (qui peut être
        // 10+ secondes pour un Drive qui ne répond pas). Sans ce hop
        // explicite sur DispatchQueue.global, l'appel s'exécutait sur
        // le MainActor (le projet utilise MainActor par défaut) et
        // freezait l'UI + toutes les autres tâches Swift, donnant
        // l'illusion d'une app qui « tourne en rond ».
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let result = RclonebridgeRPC(method, inputJSON) else {
                    continuation.resume(throwing: RcloneError.rcloneError(
                        code: 0,
                        method: method,
                        message: "rclonebridge returned nil — bridge not initialised?"
                    ))
                    return
                }
                let output = result.output
                let status = Int(result.status)
                if (200..<300).contains(status) {
                    continuation.resume(returning: output)
                } else {
                    continuation.resume(throwing: RcloneError.rcloneError(
                        code: status,
                        method: method,
                        message: output
                    ))
                }
            }
        }
    }
}
#endif
