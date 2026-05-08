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

    public func initialize() async throws {
        RclonebridgeInitialize()
    }

    public func rpcRaw(method: String, inputJSON: String) async throws -> String {
        guard let result = RclonebridgeRPC(method, inputJSON) else {
            throw RcloneError.rcloneError(
                code: 0,
                method: method,
                message: "rclonebridge returned nil — bridge not initialised?"
            )
        }
        let output = result.output
        let status = Int(result.status)
        if (200..<300).contains(status) {
            return output
        }
        throw RcloneError.rcloneError(code: status, method: method, message: output)
    }
}
#endif
