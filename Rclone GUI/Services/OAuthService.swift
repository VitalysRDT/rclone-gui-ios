//
//  OAuthService.swift
//  Rclone GUI — Services
//
//  Phase E v1 stub — defines the API surface for OAuth interactive
//  (FR-007 of the PRD). The actual ASWebAuthenticationSession flow,
//  per-backend client_id management, and exchange-with-rclone wiring
//  land in Phase E2.
//
//  Backends that require interactive OAuth :
//    - Google Drive
//    - Dropbox
//    - OneDrive
//    - Box
//    - pCloud
//    - Yandex Disk
//

import Foundation
#if canImport(AuthenticationServices)
import AuthenticationServices
#endif

public enum OAuthBackend: String, CaseIterable, Sendable, Codable {
    case drive
    case dropbox
    case onedrive
    case box
    case pcloud
    case yandex

    public var displayName: String {
        switch self {
        case .drive:    return "Google Drive"
        case .dropbox:  return "Dropbox"
        case .onedrive: return "OneDrive"
        case .box:      return "Box"
        case .pcloud:   return "pCloud"
        case .yandex:   return "Yandex Disk"
        }
    }
}

public enum OAuthError: LocalizedError {
    case notImplementedYet(OAuthBackend)
    case userCancelled
    case missingClientID
    case rcloneCallFailed(String)

    public var errorDescription: String? {
        switch self {
        case .notImplementedYet(let backend):
            return "Le flow OAuth pour \(backend.displayName) sera disponible en Phase E2."
        case .userCancelled:
            return "Authentification annulée."
        case .missingClientID:
            return "Client ID manquant pour ce backend (à configurer dans Settings → OAuth)."
        case .rcloneCallFailed(let msg):
            return "Échec côté rclone : \(msg)"
        }
    }
}

@MainActor
public final class OAuthService: NSObject {
    public static let shared = OAuthService()
    private override init() { super.init() }

    /// Launch the OAuth dance for the given backend and return the
    /// resulting refresh token (already stored in rclone.conf via
    /// rclone's `config/create` rc method).
    ///
    /// **Phase E v1** : not implemented — throws `notImplementedYet`.
    public func authenticate(backend: OAuthBackend, remoteName: String) async throws -> String {
        // Phase E2 plan:
        // 1. Build authorize URL via rclone rc `config/setupauth` or hard-coded per backend
        // 2. Launch ASWebAuthenticationSession with callback scheme "rclone-gui://oauth"
        // 3. Receive code → call `config/create` rclone rc method with `parameters.token = ...`
        // 4. Token stored encrypted in rclone.conf via librclone
        throw OAuthError.notImplementedYet(backend)
    }
}

#if canImport(AuthenticationServices)
extension OAuthService: ASWebAuthenticationPresentationContextProviding {
    public func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        #if canImport(UIKit)
        // Prefer the key window of the foreground active scene; fall back to
        // a windowScene-bound anchor (iOS 26 deprecates ASPresentationAnchor()).
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let keyWindow = scenes
            .flatMap(\.windows)
            .first(where: { $0.isKeyWindow }) {
            return keyWindow
        }
        if let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first {
            return ASPresentationAnchor(windowScene: scene)
        }
        // Pathological: app is foreground but has no UIWindowScene. An
        // ASWebAuthenticationSession cannot present without a scene anyway,
        // so crash explicitly rather than returning a dangling anchor.
        preconditionFailure("OAuthService.presentationAnchor called without an active UIWindowScene")
        #else
        return ASPresentationAnchor()
        #endif
    }
}
#endif
