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

#if canImport(RcloneKit)
import Foundation
import RcloneKit

public struct LibrcloneEngine: RcloneEngine {
    public nonisolated init() {}

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
