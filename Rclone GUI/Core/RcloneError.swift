//
//  RcloneError.swift
//  Rclone GUI — Core
//

import Foundation

public enum RcloneError: Error, LocalizedError, Sendable {
    /// The configured engine cannot be reached (e.g. xcframework missing or not yet wired).
    case engineNotAvailable(String)

    /// The RPC call failed before reaching librclone (transport / Swift-side error).
    case rpcFailed(method: String, message: String)

    /// librclone returned a non-2xx status with a message.
    case rcloneError(code: Int, method: String, message: String)

    /// Could not parse the JSON returned by librclone.
    case invalidJSON(method: String, raw: String, underlying: Error?)

    /// The response shape did not match the expected typed result.
    case unexpectedResponseShape(method: String, expected: String, raw: String)

    public var errorDescription: String? {
        switch self {
        case .engineNotAvailable(let msg):
            return "Rclone engine not available: \(msg)"
        case .rpcFailed(let method, let msg):
            return "RPC '\(method)' failed: \(msg)"
        case .rcloneError(let code, let method, let msg):
            return "rclone error \(code) on '\(method)': \(msg)"
        case .invalidJSON(let method, _, _):
            return "Invalid JSON from rclone for '\(method)'"
        case .unexpectedResponseShape(let method, let expected, _):
            return "Unexpected response shape for '\(method)' (expected \(expected))"
        }
    }
}
