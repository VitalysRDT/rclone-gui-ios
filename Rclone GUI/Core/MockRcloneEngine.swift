//
//  MockRcloneEngine.swift
//  Rclone GUI — Core
//
//  Fake engine used while the RcloneKit.xcframework is not yet wired.
//  Returns canned JSON responses for the most common rc methods.
//

import Foundation

public struct MockRcloneEngine: RcloneEngine {
    public init() {}

    public func initialize() async throws {
        // no-op
    }

    public func rpcRaw(method: String, inputJSON: String) async throws -> String {
        switch method {
        case "core/version":
            return #"{"version":"v1.68.0-mock","isGit":false,"goVersion":"go1.22.0","os":"ios","arch":"arm64"}"#

        case "config/listremotes":
            return #"{"remotes":[]}"#

        case "operations/list":
            return #"{"list":[]}"#

        case "core/quit":
            return #"{}"#

        default:
            throw RcloneError.rpcFailed(
                method: method,
                message: "MockRcloneEngine has no canned response for '\(method)'. Build and integrate RcloneKit.xcframework to use the real engine."
            )
        }
    }
}
