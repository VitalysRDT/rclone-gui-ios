//
//  RcloneEngine.swift
//  Rclone GUI — Core
//
//  Protocol abstracting a backend that can run rclone RPC calls.
//  Two implementations:
//    - LibrcloneEngine (production, requires RcloneKit.xcframework)
//    - MockRcloneEngine (test/dev, returns canned responses)
//
//  Methods are explicitly `nonisolated` because the project uses
//  `MainActor` as the default isolation. Without that, the engine
//  would inherit @MainActor on every method, and `RcloneCore` (a
//  custom actor) could not invoke them without hopping to the main
//  actor — which would deadlock the import flow during early init.
//

import Foundation

public protocol RcloneEngine: Sendable {
    /// Set a process environment variable from inside the engine's runtime.
    /// On gomobile-backed engines this routes through Go's `os.Setenv` so
    /// the value is visible to `os.Getenv` (the host's `setenv(3)` is not).
    /// Must be called before `initialize()` for variables that influence
    /// engine startup (e.g. `RCLONE_CONFIG`).
    nonisolated func setEnv(name: String, value: String)

    /// Return a small JSON document describing the runtime environment as
    /// seen from inside the engine. Used for diagnostics.
    nonisolated func diagnosticJSON() -> String

    /// One-time engine initialization. Idempotent.
    nonisolated func initialize() async throws

    /// Send a raw JSON-RPC request to rclone.
    /// - Parameters:
    ///   - method: rclone rc method, e.g. `core/version`, `operations/list`.
    ///   - inputJSON: JSON-encoded request body. Use `"{}"` for empty.
    /// - Returns: JSON-encoded response body.
    nonisolated func rpcRaw(method: String, inputJSON: String) async throws -> String
}
