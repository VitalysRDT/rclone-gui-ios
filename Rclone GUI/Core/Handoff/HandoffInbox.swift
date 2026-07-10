//
//  HandoffInbox.swift
//  Rclone GUI — Core/Handoff
//
//  Réception d'un fichier `.rclonebackup` arrivé de l'extérieur
//  (AirDrop, Fichiers, Mail…) via `onOpenURL`. Valide l'extension,
//  lit le contenu (accès security-scoped si nécessaire) et en extrait
//  le payload transport `HND1:` pour préremplir le wizard
//  « Handoff P2P — recevoir ».
//
//  Le fichier lui-même ne contient que le blob chiffré : sans la
//  passphrase de 6 mots (hors-canal), il est inexploitable — on peut
//  donc accepter n'importe quelle provenance sans risque.
//

import Foundation

public enum HandoffInboxError: Error, LocalizedError, Sendable {
    case notAHandoffFile(String)
    case unreadable(String)
    case noPayloadFound

    public var errorDescription: String? {
        switch self {
        case .notAHandoffFile(let name):
            return String(localized: "« \(name) » n'est pas un fichier .rclonebackup.")
        case .unreadable(let why):
            return String(localized: "Lecture du fichier impossible : \(why).")
        case .noPayloadFound:
            return String(localized: "Ce fichier ne contient pas de payload Handoff (HND1:) valide.")
        }
    }
}

public enum HandoffInbox {

    /// Est-ce qu'une URL entrante ressemble à un fichier Handoff ?
    /// (extension `.rclonebackup`, insensible à la casse)
    public nonisolated static func isHandoffFile(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == GhostVault.fileExtension
    }

    /// Lit un fichier `.rclonebackup` entrant et en extrait le payload
    /// `HND1:`. Gère l'accès security-scoped (fichier ouvert en place
    /// depuis Fichiers / AirDrop avec LSSupportsOpeningDocumentsInPlace).
    public nonisolated static func extractPayload(fromFileAt url: URL) throws -> String {
        guard isHandoffFile(url) else {
            throw HandoffInboxError.notAHandoffFile(url.lastPathComponent)
        }
        let didStart = url.startAccessingSecurityScopedResource()
        defer { if didStart { url.stopAccessingSecurityScopedResource() } }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw HandoffInboxError.unreadable(error.localizedDescription)
        }
        guard let text = String(data: data, encoding: .utf8),
              let payload = HandoffEnvelope.extract(from: text) else {
            throw HandoffInboxError.noPayloadFound
        }
        return payload
    }
}
