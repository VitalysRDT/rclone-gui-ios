//
//  RcloneEngine.swift
//  Rclone GUI — Core
//
//  Protocol abstracting a backend that can run rclone RPC calls.
//  Two implementations:
//    - LibrcloneEngine (production, requires RcloneKit.xcframework)
//    - MockRcloneEngine (test/dev, returns canned responses)
//

import Foundation

public protocol RcloneEngine: Sendable {
    /// One-time engine initialization. Idempotent.
    func initialize() async throws

    /// Send a raw JSON-RPC request to rclone.
    /// - Parameters:
    ///   - method: rclone rc method, e.g. `core/version`, `operations/list`.
    ///   - inputJSON: JSON-encoded request body. Use `"{}"` for empty.
    /// - Returns: JSON-encoded response body.
    func rpcRaw(method: String, inputJSON: String) async throws -> String
}
