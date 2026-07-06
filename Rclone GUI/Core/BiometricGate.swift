//
//  BiometricGate.swift
//  Rclone GUI — Core
//
//  Thin wrapper around LocalAuthentication. Requests FaceID / TouchID
//  before unlocking the encrypted rclone.conf or other sensitive ops.
//
//  Requires NSFaceIDUsageDescription in Info.plist.
//

import Foundation
import LocalAuthentication

public enum BiometricReason: Sendable {
    case appOpen
    case configRead
    case configWrite
    case revealRemoteCredentials

    nonisolated var localized: String {
        switch self {
        case .appOpen:
            return NSLocalizedString("Déverrouiller Rclone GUI", comment: "FaceID prompt at app open")
        case .configRead:
            return NSLocalizedString("Accéder à votre configuration rclone", comment: "FaceID prompt before reading rclone.conf")
        case .configWrite:
            return NSLocalizedString("Sauvegarder votre configuration rclone", comment: "FaceID prompt before writing rclone.conf")
        case .revealRemoteCredentials:
            return NSLocalizedString("Afficher les identifiants de ce remote", comment: "FaceID prompt before showing credentials")
        }
    }
}

public enum BiometricResult: Sendable {
    case authenticated
    case userCancelled
    case fallback
    case unavailable(String)
}

public actor BiometricGate {
    public static let shared = BiometricGate()

    private init() {}

    /// Returns whether the device supports biometric auth right now (enrolled, not locked out).
    public func isAvailable() -> Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    /// Trigger a biometric prompt. Falls back to passcode if biometrics fail or are unavailable.
    public func authenticate(reason: BiometricReason) async -> BiometricResult {
        #if DEBUG
        // Simulators used for App Store screenshot automation have no enrolled
        // Face ID / passcode, which would otherwise block every launch behind
        // the system auth sheet. Skip only when the same --seed-demo flag that
        // seeds fixture data (DemoSeeder.isRequested) is present.
        if await DemoSeeder.isRequested {
            return .authenticated
        }
        #endif

        let context = LAContext()
        var nsError: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &nsError) else {
            let msg = nsError?.localizedDescription ?? String(localized: "Biométrie non disponible")
            return .unavailable(msg)
        }

        let localizedReason = reason.localized
        return await withCheckedContinuation { continuation in
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: localizedReason) { success, error in
                if success {
                    continuation.resume(returning: .authenticated)
                    return
                }
                guard let laError = error as? LAError else {
                    continuation.resume(returning: .unavailable(error?.localizedDescription ?? String(localized: "Erreur biométrie inconnue")))
                    return
                }
                switch laError.code {
                case .userCancel, .systemCancel, .appCancel:
                    continuation.resume(returning: .userCancelled)
                case .userFallback:
                    continuation.resume(returning: .fallback)
                default:
                    continuation.resume(returning: .unavailable(laError.localizedDescription))
                }
            }
        }
    }
}
