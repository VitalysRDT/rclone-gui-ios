//
//  ConfigCreateModels.swift
//  Rclone GUI — Models/Wizard
//
//  Encodable inputs and Decodable response for the rclone `config/create`
//  and `config/update` RPC methods. Both methods share the same response
//  shape because they participate in the same non-interactive state
//  machine: a non-empty `state` field means rclone needs another answer
//  from the host.
//

import Foundation

/// Body of `config/create` (and `config/update` when `continue=true`).
struct ConfigCreateInput: nonisolated Encodable, Sendable {
    let name: String
    let type: String
    let parameters: [String: String]
    let opt: ConfigCreateOpt?
}

/// Optional flags for the non-interactive state machine.
///
/// - `nonInteractive`: tells rclone NOT to spawn a browser/loopback
///   when an OAuth-style backend needs the user. Required for iOS.
/// - `all`: ask the full set of questions (otherwise only post-config).
/// - `obscure` / `noObscure`: control automatic password obfuscation.
/// - `continue` / `state` / `result`: drive the state machine after
///   the first call returns an `Option` payload.
struct ConfigCreateOpt: nonisolated Encodable, Sendable {
    var nonInteractive: Bool? = nil
    var all: Bool? = nil
    var obscure: Bool? = nil
    var noObscure: Bool? = nil
    var `continue`: Bool? = nil
    var state: String? = nil
    var result: String? = nil

    enum CodingKeys: String, CodingKey {
        case nonInteractive
        case all
        case obscure
        case noObscure
        case `continue`
        case state
        case result
    }
}

/// Result of `config/create` / `config/update`.
///
/// Two shapes are possible:
/// - **Done:** `state` empty (or nil) and `option` nil → the remote was
///   written to rclone.conf successfully.
/// - **Question:** `state` is set and `option` describes what rclone
///   needs next. The host should ask the user, then re-call
///   `config/update` with `continue=true, state=…, result=…`.
struct ConfigCreateResponse: Decodable, Sendable {
    let state: String?
    let option: RcloneOptionSchema?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case state = "State"
        case option = "Option"
        case error = "Error"
    }

    /// `true` when rclone is done and the remote has been persisted.
    var isComplete: Bool {
        let stateEmpty = (state ?? "").isEmpty
        return stateEmpty && option == nil
    }
}
