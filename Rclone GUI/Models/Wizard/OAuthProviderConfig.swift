//
//  OAuthProviderConfig.swift
//  Rclone GUI — Models/Wizard
//
//  Static OAuth metadata for backends that need an interactive auth flow.
//  These constants live in `BackendOverrides.oauthConfigs` because they
//  are *not* part of the JSON returned by `config/providers` — the JSON
//  describes the rclone option itself (e.g. "token") but does not tell
//  us which provider URL to open or which scopes to request.
//

import Foundation

/// Auth guide for one backend. The wizard does NOT run OAuth interactively
/// — instead, it points the user at the provider's developer console,
/// walks them through the steps to mint an API key / app token / service
/// account file, and asks them to paste the resulting value.
///
/// The OAuth-specific fields (authURL, tokenURL, client_id, scopes,
/// strategy) are kept around for a possible future P2 switch back to a
/// real OAuth flow, but are unused in P1.
struct OAuthProviderConfig: Sendable, Hashable {
    /// Rclone backend name (e.g. "drive", "dropbox").
    let backendName: String

    /// Authorization endpoint (kept for P2; unused in the manual guide).
    let authURL: URL

    /// Token endpoint (kept for P2; unused in the manual guide).
    let tokenURL: URL

    /// Default rclone-shared client_id (kept for P2 reference).
    let defaultClientID: String

    /// Some providers also require a client_secret (kept for P2).
    let defaultClientSecret: String?

    /// OAuth scopes requested at authorize time (kept for P2).
    let defaultScopes: [String]

    /// How the redirect URI is configured (kept for P2). All backends
    /// currently use `.manual`.
    let strategy: OAuthStrategy

    /// Whether to use PKCE (kept for P2).
    let usePKCE: Bool

    // MARK: - Manual auth guide (P1 — what the wizard actually shows)

    /// Direct link to the provider page where the user can mint a token /
    /// API key / app password. Opens in Safari from the wizard.
    let setupURL: URL?

    /// Numbered step-by-step instructions shown above the token input.
    /// Keep each step short (≤ 80 chars) and actionable.
    let setupSteps: [String]

    /// Display label for the input field (e.g. "Token rclone JSON",
    /// "App access token", "Service Account JSON").
    let tokenLabel: String

    /// Rclone option name where the pasted value will be stored. Most
    /// backends use "token"; some special cases use "access_token",
    /// "service_account_credentials", etc.
    let tokenFieldName: String

    /// Hint shown under the input ("Doit commencer par sl.B...", etc.).
    let tokenHint: String?
}

/// Where the OAuth callback should land. iOS does not allow loopback
/// HTTP servers like the desktop rclone CLI uses, so we either rely on
/// a custom URL scheme registered for the app, an Apple Universal Link
/// pointing at our domain, or — as a last-resort fallback — let the
/// user paste the JSON token by hand.
enum OAuthStrategy: Sendable, Hashable {
    case customScheme(scheme: String)
    case universalLink(host: String, path: String)
    case manual
}

/// Minimal token JSON expected by rclone in `parameters.token`.
/// rclone re-uses the standard OAuth2 response format produced by
/// golang.org/x/oauth2 — we mirror it exactly here.
struct RcloneTokenJSON: Sendable, Hashable {
    let accessToken: String
    let tokenType: String
    let refreshToken: String
    let expiry: String
    let expiresIn: Int?

    nonisolated init(
        accessToken: String,
        tokenType: String,
        refreshToken: String,
        expiry: String,
        expiresIn: Int? = nil
    ) {
        self.accessToken = accessToken
        self.tokenType = tokenType
        self.refreshToken = refreshToken
        self.expiry = expiry
        self.expiresIn = expiresIn
    }

    enum CodingKeys: String, CodingKey {
        case accessToken  = "access_token"
        case tokenType    = "token_type"
        case refreshToken = "refresh_token"
        case expiry
        case expiresIn    = "expires_in"
    }

    /// Encode to a JSON string that can be passed verbatim to
    /// `config/create parameters.token`.
    nonisolated func encodeToJSON() throws -> String {
        let data = try JSONEncoder().encode(self)
        return String(decoding: data, as: UTF8.self)
    }
}

// Conformance Codable via extension nonisolated avec init/encode
// manuels : la conformance synthétisée hériterait du MainActor
// (default actor isolation du projet) et empêcherait l'usage depuis
// OAuthBrokerService.parseManualToken qui est nonisolated.
extension RcloneTokenJSON: Codable {
    nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            accessToken: try c.decode(String.self, forKey: .accessToken),
            tokenType: try c.decode(String.self, forKey: .tokenType),
            refreshToken: try c.decode(String.self, forKey: .refreshToken),
            expiry: try c.decode(String.self, forKey: .expiry),
            expiresIn: try c.decodeIfPresent(Int.self, forKey: .expiresIn)
        )
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(accessToken, forKey: .accessToken)
        try c.encode(tokenType, forKey: .tokenType)
        try c.encode(refreshToken, forKey: .refreshToken)
        try c.encode(expiry, forKey: .expiry)
        try c.encodeIfPresent(expiresIn, forKey: .expiresIn)
    }
}
