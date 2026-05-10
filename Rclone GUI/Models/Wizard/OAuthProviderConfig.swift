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

/// OAuth configuration for one backend.
struct OAuthProviderConfig: Sendable, Hashable {
    /// Rclone backend name (e.g. "drive", "dropbox").
    let backendName: String

    /// Authorization endpoint (where the user logs in).
    let authURL: URL

    /// Token endpoint (where we exchange the auth code for tokens).
    let tokenURL: URL

    /// Default rclone-shared client_id (public, baked into rclone CLI).
    /// Users may override this with their own client_id in the wizard.
    let defaultClientID: String

    /// Some providers (Google, Microsoft) also require a client_secret.
    /// rclone keeps a known secret bundled for the default client_id.
    let defaultClientSecret: String?

    /// OAuth scopes requested at authorize time.
    let defaultScopes: [String]

    /// How the redirect URI is configured for this provider.
    let strategy: OAuthStrategy

    /// Whether to use PKCE (recommended for Google, Microsoft).
    let usePKCE: Bool
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
struct RcloneTokenJSON: Codable, Sendable, Hashable {
    let accessToken: String
    let tokenType: String
    let refreshToken: String
    let expiry: String
    let expiresIn: Int?

    enum CodingKeys: String, CodingKey {
        case accessToken  = "access_token"
        case tokenType    = "token_type"
        case refreshToken = "refresh_token"
        case expiry
        case expiresIn    = "expires_in"
    }

    /// Encode to a JSON string that can be passed verbatim to
    /// `config/create parameters.token`.
    func encodeToJSON() throws -> String {
        let data = try JSONEncoder().encode(self)
        return String(decoding: data, as: UTF8.self)
    }
}
