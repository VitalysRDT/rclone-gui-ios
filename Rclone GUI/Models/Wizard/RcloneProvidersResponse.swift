//
//  RcloneProvidersResponse.swift
//  Rclone GUI — Models/Wizard
//
//  Codable mirror of the JSON returned by the rclone RPC `config/providers`.
//  Field names use the Go PascalCase convention as exposed in the JSON; we
//  remap to Swift camelCase via CodingKeys so the rest of the app reads
//  natural Swift property names.
//

import Foundation

/// Response wrapper for the rclone `config/providers` RPC.
struct RcloneProvidersResponse: Decodable, Sendable {
    let providers: [RcloneBackendSchema]
}

/// One backend (= storage type) as advertised by the embedded rclone runtime.
/// The bridge exposes the full set of 69+ backends compiled in via
/// `_ "github.com/rclone/rclone/backend/all"`.
struct RcloneBackendSchema: Decodable, Sendable, Hashable {
    let name: String
    let description: String
    let prefix: String
    let options: [RcloneOptionSchema]

    enum CodingKeys: String, CodingKey {
        case name = "Name"
        case description = "Description"
        case prefix = "Prefix"
        case options = "Options"
    }
}

/// A single option (= field) of a backend. The shape mirrors what
/// rclone returns AND what `config/create --non-interactive` returns
/// when asking the host a follow-up question.
struct RcloneOptionSchema: Decodable, Sendable, Hashable {
    let name: String
    let help: String
    let type: String
    let defaultStr: String
    let valueStr: String?
    let required: Bool
    let isPassword: Bool
    let sensitive: Bool
    let advanced: Bool
    let exclusive: Bool
    let hide: Int
    let noPrefix: Bool
    let examples: [RcloneExampleValue]?
    let provider: String?

    enum CodingKeys: String, CodingKey {
        case name = "Name"
        case help = "Help"
        case type = "Type"
        case defaultStr = "DefaultStr"
        case valueStr = "ValueStr"
        case required = "Required"
        case isPassword = "IsPassword"
        case sensitive = "Sensitive"
        case advanced = "Advanced"
        case exclusive = "Exclusive"
        case hide = "Hide"
        case noPrefix = "NoPrefix"
        case examples = "Examples"
        case provider = "Provider"
    }

    /// Some backends omit ValueStr entirely; treat as empty.
    var resolvedValueStr: String { valueStr ?? "" }
}

/// One suggested value for an option. When `Exclusive=true` on the
/// parent option, the user MUST pick from this list; otherwise the
/// list is treated as suggestions and free-form input is allowed.
struct RcloneExampleValue: Decodable, Sendable, Hashable {
    let value: String
    let help: String
    let provider: String?

    enum CodingKeys: String, CodingKey {
        case value = "Value"
        case help = "Help"
        case provider = "Provider"
    }
}
