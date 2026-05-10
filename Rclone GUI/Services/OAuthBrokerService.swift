//
//  OAuthBrokerService.swift
//  Rclone GUI — Services
//
//  Generic OAuth 2.0 broker for the add-remote wizard. Speaks PKCE +
//  ASWebAuthenticationSession. Returns a `RcloneTokenJSON` ready to
//  inject into `parameters.token` of `config/create`.
//
//  Strategies supported (cf. OAuthProviderConfig.strategy):
//  - `.customScheme(scheme:)`  → app:// callback. Works for ~15 of the
//    22 OAuth backends (Dropbox, Box, pCloud, Yandex, Putio, …).
//  - `.universalLink(host:path:)` → https:// callback via Apple Universal
//    Links. Required for Google, Microsoft (forbid custom schemes).
//    P0 ships the plumbing but no domain — backends configured this
//    way will throw `.strategyNotConfigured`.
//  - `.manual` → user pastes a JSON token obtained out-of-band (e.g.
//    via `rclone authorize drive` on a desktop). Always available as
//    fallback for backends without a custom-scheme-friendly config.
//
//  The legacy `OAuthService.shared` (Phase E v1 stub) remains in place
//  for the existing call sites; this service is the new wizard-side
//  broker.
//

import Foundation
import CryptoKit
#if canImport(AuthenticationServices)
import AuthenticationServices
#endif

@MainActor
public final class OAuthBrokerService: NSObject {

    // MARK: - Errors

    enum BrokerError: LocalizedError, Equatable {
        case canceled
        case strategyNotConfigured(String)
        case missingCallbackParam(String)
        case stateMismatch
        case tokenExchangeFailed(Int, String)
        case decodingFailed(String)

        var errorDescription: String? {
            switch self {
            case .canceled:
                return "Authentification annulée."
            case .strategyNotConfigured(let detail):
                return "Stratégie OAuth non configurée : \(detail)"
            case .missingCallbackParam(let key):
                return "Paramètre OAuth manquant : \(key)"
            case .stateMismatch:
                return "Le code OAuth reçu ne correspond pas à la requête."
            case .tokenExchangeFailed(let status, let body):
                return "Échange de token échoué (HTTP \(status)) : \(body)"
            case .decodingFailed(let detail):
                return "Réponse OAuth invalide : \(detail)"
            }
        }
    }

    // MARK: - Singleton

    public static let shared = OAuthBrokerService()
    private override init() { super.init() }

    // Strong reference held while a session is in-flight. Without it, ARC
    // can release the locally-scoped ASWebAuthenticationSession after
    // start() returns and the callback never fires (.canceledLogin
    // delivered silently to the continuation). This is a known iOS pitfall.
    #if canImport(AuthenticationServices)
    private var activeSession: ASWebAuthenticationSession?
    #endif

    // MARK: - Authenticate

    /// Runs the full PKCE OAuth flow for `config` and returns a token
    /// JSON that can be passed to rclone's `config/create parameters.token`.
    func authenticate(
        config: OAuthProviderConfig,
        customClientID: String? = nil,
        customClientSecret: String? = nil
    ) async throws -> RcloneTokenJSON {

        switch config.strategy {
        case .customScheme(let scheme):
            return try await authenticateWithScheme(
                config: config,
                scheme: scheme,
                customClientID: customClientID,
                customClientSecret: customClientSecret
            )

        case .universalLink:
            // Universal Links require apple-app-site-association on a
            // controlled domain + the corresponding Associated Domains
            // entitlement. Not configured in P0.
            throw BrokerError.strategyNotConfigured(
                "Universal Links requis pour ce backend (Drive/OneDrive). Utilise « Coller token » en attendant."
            )

        case .manual:
            // The caller (OAuthView) should never invoke `authenticate`
            // for manual strategy — it should accept a pasted JSON
            // token directly.
            throw BrokerError.strategyNotConfigured(
                "Mode manuel : colle le token JSON obtenu via `rclone authorize \(config.backendName)` sur un poste avec un navigateur."
            )
        }
    }

    /// Validates that a user-pasted JSON blob is a well-formed rclone
    /// token. Used by the OAuthView "manual" mode. Marked `nonisolated`
    /// so the JSON decode runs off the MainActor — keeps the UI smooth
    /// even if a future revision adds heavier validation.
    nonisolated func parseManualToken(_ raw: String) throws -> RcloneTokenJSON {
        guard let data = raw.data(using: .utf8) else {
            throw BrokerError.decodingFailed("Texte non UTF-8")
        }
        do {
            return try JSONDecoder().decode(RcloneTokenJSON.self, from: data)
        } catch {
            throw BrokerError.decodingFailed(error.localizedDescription)
        }
    }

    // MARK: - Custom-scheme flow

    private func authenticateWithScheme(
        config: OAuthProviderConfig,
        scheme: String,
        customClientID: String?,
        customClientSecret: String?
    ) async throws -> RcloneTokenJSON {

        #if canImport(AuthenticationServices)
        let clientID = customClientID?.isEmpty == false ? customClientID! : config.defaultClientID
        let clientSecret = customClientSecret?.isEmpty == false ? customClientSecret : config.defaultClientSecret

        let state = randomURLSafeString(byteCount: 16)
        let codeVerifier = randomURLSafeString(byteCount: 64)
        let codeChallenge = pkceChallenge(from: codeVerifier)
        let redirectURI = "\(scheme)://oauth"

        guard var components = URLComponents(url: config.authURL, resolvingAgainstBaseURL: false) else {
            throw BrokerError.strategyNotConfigured("auth_url invalide")
        }
        var queryItems: [URLQueryItem] = [
            .init(name: "client_id", value: clientID),
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "response_type", value: "code"),
            .init(name: "state", value: state),
        ]
        if !config.defaultScopes.isEmpty {
            queryItems.append(.init(name: "scope", value: config.defaultScopes.joined(separator: " ")))
        }
        if config.usePKCE {
            queryItems.append(.init(name: "code_challenge", value: codeChallenge))
            queryItems.append(.init(name: "code_challenge_method", value: "S256"))
        }
        components.queryItems = queryItems

        guard let authURL = components.url else {
            throw BrokerError.strategyNotConfigured("auth_url construit invalide")
        }

        // Run the ASWebAuthenticationSession. We retain it on `self` for
        // the duration of the await; if we kept only a local `let session`
        // ARC could release it after `start()` returns and the callback
        // would deliver `.canceledLogin` silently in optimized builds.
        let callbackURL: URL = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: scheme
            ) { [weak self] url, error in
                self?.activeSession = nil
                if let url {
                    continuation.resume(returning: url)
                } else if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    continuation.resume(throwing: BrokerError.canceled)
                } else if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(throwing: BrokerError.canceled)
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = true
            self.activeSession = session
            if !session.start() {
                self.activeSession = nil
                continuation.resume(throwing: BrokerError.strategyNotConfigured("Impossible de démarrer ASWebAuthenticationSession"))
            }
        }

        // Validate state + extract code.
        let callbackComponents = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)
        let returnedState = callbackComponents?.queryItems?.first(where: { $0.name == "state" })?.value
        let returnedCode = callbackComponents?.queryItems?.first(where: { $0.name == "code" })?.value

        guard returnedState == state else { throw BrokerError.stateMismatch }
        guard let code = returnedCode else { throw BrokerError.missingCallbackParam("code") }

        // Exchange the code for a token.
        return try await exchangeCodeForToken(
            code: code,
            redirectURI: redirectURI,
            tokenURL: config.tokenURL,
            clientID: clientID,
            clientSecret: clientSecret,
            codeVerifier: config.usePKCE ? codeVerifier : nil
        )
        #else
        throw BrokerError.strategyNotConfigured("AuthenticationServices indisponible sur cette plateforme")
        #endif
    }

    // MARK: - Token exchange

    private func exchangeCodeForToken(
        code: String,
        redirectURI: String,
        tokenURL: URL,
        clientID: String,
        clientSecret: String?,
        codeVerifier: String?
    ) async throws -> RcloneTokenJSON {

        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var bodyItems: [URLQueryItem] = [
            .init(name: "grant_type", value: "authorization_code"),
            .init(name: "code", value: code),
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "client_id", value: clientID),
        ]
        if let clientSecret, !clientSecret.isEmpty {
            bodyItems.append(.init(name: "client_secret", value: clientSecret))
        }
        if let codeVerifier {
            bodyItems.append(.init(name: "code_verifier", value: codeVerifier))
        }

        var components = URLComponents()
        components.queryItems = bodyItems
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw BrokerError.tokenExchangeFailed(0, "Réponse non-HTTP")
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "<binary>"
            throw BrokerError.tokenExchangeFailed(http.statusCode, body)
        }

        // Standard OAuth2 response — exactly what golang.org/x/oauth2
        // produces and rclone expects (+ ISO8601 expiry).
        struct OAuthTokenResponse: Decodable {
            let access_token: String
            let token_type: String?
            let refresh_token: String?
            let expires_in: Int?
        }
        let token: OAuthTokenResponse
        do {
            token = try JSONDecoder().decode(OAuthTokenResponse.self, from: data)
        } catch {
            throw BrokerError.decodingFailed(error.localizedDescription)
        }

        let expiry: String
        if let expiresIn = token.expires_in {
            let date = Date().addingTimeInterval(TimeInterval(expiresIn))
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            expiry = formatter.string(from: date)
        } else {
            // Some providers omit expires_in (e.g. Dropbox). Use a far-future
            // expiry so rclone won't try to refresh prematurely.
            expiry = "2099-12-31T23:59:59Z"
        }

        return RcloneTokenJSON(
            accessToken: token.access_token,
            tokenType: token.token_type ?? "Bearer",
            refreshToken: token.refresh_token ?? "",
            expiry: expiry,
            expiresIn: token.expires_in
        )
    }

    // MARK: - PKCE helpers

    private func randomURLSafeString(byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        _ = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func pkceChallenge(from verifier: String) -> String {
        let hash = SHA256.hash(data: Data(verifier.utf8))
        return Data(hash).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

#if canImport(AuthenticationServices)
extension OAuthBrokerService: ASWebAuthenticationPresentationContextProviding {
    public func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        #if canImport(UIKit)
        // Reuse the same logic as OAuthService.presentationAnchor —
        // pick the keyWindow of the foreground active scene.
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let keyWindow = scenes.flatMap(\.windows).first(where: { $0.isKeyWindow }) {
            return keyWindow
        }
        if let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first {
            return ASPresentationAnchor(windowScene: scene)
        }
        preconditionFailure("OAuthBrokerService.presentationAnchor: no active UIWindowScene")
        #else
        return ASPresentationAnchor()
        #endif
    }
}
#endif
