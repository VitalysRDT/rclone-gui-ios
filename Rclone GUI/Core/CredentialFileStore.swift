//
//  CredentialFileStore.swift
//  Rclone GUI — Core
//
//  Imports credential FILES that some rclone backends require to connect:
//    - SSH private/public keys (sftp `key_file`, `pubkey_file`)
//    - known_hosts (sftp `known_hosts_file`)
//    - service-account JSON (drive / google cloud storage `service_account_file`)
//    - TLS material (`client_cert`, `client_key`, `ca_cert`)
//
//  On iOS a filesystem path is meaningless to type, so the user picks the file
//  with the document picker and we copy it into the App Group container (so the
//  embedded rclone engine AND the FileProvider extension can read it during
//  transfers). The stored path then goes straight into the `config/create`
//  parameters like any other field value.
//
//  For options whose value is the file *content* itself (e.g. `key_pem`,
//  `service_account_credentials`) we don't copy anything — `readText` returns
//  the file's text and the wizard stores it inline.
//

import Foundation

enum CredentialFileStore {

    enum ImportError: LocalizedError {
        case unreadable
        case notUTF8
        case tooLarge

        var errorDescription: String? {
            switch self {
            case .unreadable:
                return String(localized: "Impossible de lire le fichier sélectionné.")
            case .notUTF8:
                return String(localized: "Ce fichier n'est pas du texte lisible (clé/certificat attendus).")
            case .tooLarge:
                return String(localized: "Fichier trop volumineux (max 512 Ko pour une clé ou un certificat).")
            }
        }
    }

    /// Generous ceiling: real keys/certs/service-account files are a few KB.
    /// Guards against importing a huge unrelated file by mistake.
    private static let maxBytes = 512 * 1024

    /// Directory where imported credential files live (inside the App Group).
    private static var directory: URL { AppGroup.credentialsURL }

    // MARK: - Path fields (copy file into the container)

    /// Copies a picked (security-scoped) file into the secure credentials
    /// directory and returns the destination URL. The stored path is what the
    /// rclone option (`key_file`, `ca_cert`, …) will point to.
    static func importFile(from sourceURL: URL, fieldName: String) throws -> URL {
        let data = try readData(from: sourceURL)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let ext = sourceURL.pathExtension
        var name = fieldName
        if !ext.isEmpty { name += "." + ext }
        let dest = uniqueDestination(named: name)

        try data.write(to: dest, options: [.atomic])
        applyProtection(to: dest)
        return dest
    }

    // MARK: - Inline-content fields (return the text)

    /// Reads a picked (security-scoped) file as UTF-8 text, for options whose
    /// value is the content itself (`key_pem`, `service_account_credentials`).
    static func readText(from sourceURL: URL) throws -> String {
        let data = try readData(from: sourceURL)
        guard let text = String(data: data, encoding: .utf8) else {
            throw ImportError.notUTF8
        }
        return text
    }

    // MARK: - Cleanup

    /// Removes a previously imported file when the user clears a path field.
    /// Only deletes files that live inside our credentials directory.
    static func removeFileIfManaged(atPath path: String) {
        guard !path.isEmpty else { return }
        let url = URL(fileURLWithPath: path)
        guard url.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL else {
            return
        }
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Helpers

    private static func readData(from sourceURL: URL) throws -> Data {
        let scoped = sourceURL.startAccessingSecurityScopedResource()
        defer { if scoped { sourceURL.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: sourceURL) else {
            throw ImportError.unreadable
        }
        guard data.count <= maxBytes else {
            throw ImportError.tooLarge
        }
        return data
    }

    private static func uniqueDestination(named name: String) -> URL {
        let base = directory.appending(path: name)
        guard FileManager.default.fileExists(atPath: base.path) else { return base }
        let ext = base.pathExtension
        let stem = base.deletingPathExtension().lastPathComponent
        let unique = "\(stem)-\(UUID().uuidString.prefix(8))"
        let url = directory.appending(path: unique)
        return ext.isEmpty ? url : url.appendingPathExtension(ext)
    }

    private static func applyProtection(to url: URL) {
        #if os(iOS)
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: url.path
        )
        #endif
    }
}
