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

    /// The stored/imported rclone.conf is rclone-encrypted (RCLONE_ENCRYPT_V0)
    /// and a password is required before librclone may read it. Feeding the
    /// encrypted blob to librclone is fatal (fs.Fatalf → os.Exit), hence this
    /// guard error.
    case configPasswordRequired

    /// The provided rclone configuration password did not decrypt the file.
    case configPasswordIncorrect

    public var errorDescription: String? {
        switch self {
        case .engineNotAvailable(let msg):
            return "Rclone engine not available: \(msg)"
        case .configPasswordRequired:
            return String(localized: "Cette configuration rclone est chiffrée. Saisis ton mot de passe rclone pour l’importer.")
        case .configPasswordIncorrect:
            return String(localized: "Mot de passe rclone incorrect — la configuration n’a pas pu être déchiffrée.")
        case .rpcFailed(let method, let msg):
            return "RPC '\(method)' failed: \(msg)"
        case .rcloneError(let code, let method, let msg):
            return "rclone error \(code) on '\(method)': \(msg)"
        case .invalidJSON(let method, let raw, _):
            // Include a short sample of the raw payload — invaluable for
            // diagnosing librclone returning text instead of JSON (e.g.
            // misconfigured conf path producing "Config file not found"
            // notices in the response stream).
            let sample = raw.prefix(200).replacingOccurrences(of: "\n", with: " ")
            let suffix = raw.count > 200 ? "…(\(raw.count) chars total)" : ""
            return "Invalid JSON from rclone for '\(method)': \(sample)\(suffix)"
        case .unexpectedResponseShape(let method, let expected, _):
            return "Unexpected response shape for '\(method)' (expected \(expected))"
        }
    }
}
