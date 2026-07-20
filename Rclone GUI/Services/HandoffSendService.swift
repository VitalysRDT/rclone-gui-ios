//
//  HandoffSendService.swift
//  Rclone GUI — Services/Handoff
//
//  Orchestrates "Handoff P2P — envoyer". Reads the current rclone.conf
//  (already decrypted in memory by `ConfigStore`), generates a fresh
//  Diceware passphrase, seals the conf into a GhostVault v1 envelope,
//  and produces a single ASCII transport payload (`HND1:…`) suitable
//  for QR / AirDrop / clipboard.
//
//  The service is stateless — each call to `prepare()` produces one
//  brand-new envelope and passphrase. Multiple recipients must each
//  open a separate Handoff (the passphrase is single-use by design).
//
//  FaceID gate: required. We never expose the encrypted config without
//  proving the user authorized the operation, same as Ghost Vault.
//

import Foundation
import CryptoKit

public enum HandoffSendServiceError: Error, LocalizedError, Sendable {
    case noConfigImported
    case notAuthorized

    public var errorDescription: String? {
        switch self {
        case .noConfigImported:
            return String(localized: "Aucune configuration à envoyer. Importe un rclone.conf d'abord.")
        case .notAuthorized:
            return String(localized: "Authentification biométrique requise pour préparer le Handoff.")
        }
    }
}

public struct HandoffPrepared: Sendable {
    public let payload: String
    public let passphraseWords: [String]
    public let passphraseLanguage: HandoffPassphraseLanguage
    public let envelope: GhostVaultEnvelope
    public let rcloneConfBytes: Int
    public let qrDecision: QRPayloadBuilder.QRDecision

    public var passphraseString: String {
        HandoffPassphrase.join(passphraseWords)
    }
}

public actor HandoffSendService {
    public static let shared = HandoffSendService()

    private init() {}

    public struct PrepareRequest: Sendable {
        public var passphraseLanguage: HandoffPassphraseLanguage
        public var passphraseWords: Int
        public init(
            language: HandoffPassphraseLanguage = .french,
            words: Int = HandoffPassphrase.defaultWords
        ) {
            self.passphraseLanguage = language
            self.passphraseWords = words
        }
    }

    public func prepare(
        request: PrepareRequest = PrepareRequest(),
        biometricReason: BiometricReason = .handoffSend
    ) async throws -> HandoffPrepared {
        let bio = await BiometricGate.shared.authenticate(reason: biometricReason)
        guard bio == .authenticated else {
            throw HandoffSendServiceError.notAuthorized
        }
        guard let plaintext = try await ConfigStore.shared.load() else {
            throw HandoffSendServiceError.noConfigImported
        }
        let passphrase = HandoffPassphrase.generate(
            language: request.passphraseLanguage,
            words: request.passphraseWords
        )
        let remoteSummaries = (try? await RemoteService.shared.listRemoteSummaries()) ?? []
        let meta = GhostVaultMeta(
            sizeBytes: plaintext.count,
            remoteCount: remoteSummaries.count,
            createdAt: Date(),
            deviceName: await GhostVault.currentDeviceName(),
            rcloneVersion: "rclone-gui-handoff-v1"
        )
        let envelope = try GhostVault.seal(
            rcloneConf: plaintext,
            passphrase: HandoffPassphrase.join(passphrase),
            meta: meta,
            rcloneVersion: meta.rcloneVersion
        )
        let payload = try HandoffEnvelope.encode(envelope)
        let decision = QRPayloadBuilder.build(fromEncodedPayload: payload)
        return HandoffPrepared(
            payload: payload,
            passphraseWords: passphrase,
            passphraseLanguage: request.passphraseLanguage,
            envelope: envelope,
            rcloneConfBytes: plaintext.count,
            qrDecision: decision
        )
    }

    /// Materialize a transport payload as a `.rclonebackup` file in the
    /// iOS / macOS temp directory, suitable for AirDrop via
    /// `UIActivityViewController`. Returns the URL — caller is
    /// responsible for cleanup.
    public nonisolated func materializeAirDropFile(payload: String) throws -> URL {
        let filename = "rclone-gui-handoff-\(ISO8601DateFormatter().string(from: Date())).\(GhostVault.fileExtension)"
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "rclone-gui-handoff-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: filename)
        let body = Data(payload.utf8)
        // .completeUntilFirstUserAuthentication (pas .completeFileProtection) :
        // AirDrop et l'aperçu de la share sheet lisent le fichier depuis un
        // process hors-app (sharingd). Sous .completeFileProtection ce process
        // échoue à le lire → share sheet vide, aucune cible AirDrop. Le payload
        // est déjà chiffré (ChaCha20-Poly1305), la protection fichier n'est que
        // de la défense en profondeur — cette classe suffit et débloque AirDrop.
        try body.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        return url
    }
}
