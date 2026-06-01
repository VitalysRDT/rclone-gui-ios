//
//  ConfigStore.swift
//  Rclone GUI — Core
//
//  Stores the rclone.conf encrypted at rest in the App Group container.
//  The encryption key (256-bit) lives in the Keychain, optionally backed
//  by Secure Enclave when biometric protection is enabled.
//
//  Phase A scope: load / save / wipe operations only.
//  Phase B+ will add: iCloud Drive ubiquitous-container sync (FR-006),
//                     biometric-gated key access (FR-051),
//                     migration from a clear .conf import.
//

import Foundation
import CryptoKit
import Security

public actor ConfigStore {
    public static let shared = ConfigStore()

    private let masterKeyTag = "com.rougetet.rclone-gui.master-key"

    private init() {}

    // MARK: - Public API

    /// Load and decrypt the stored rclone.conf. Returns `nil` if no conf has been imported yet.
    public func load() async throws -> Data? {
        guard FileManager.default.fileExists(atPath: AppGroup.rcloneConfURL.path) else {
            return nil
        }
        let envelope = try Data(contentsOf: AppGroup.rcloneConfURL)
        let key = try loadOrCreateMasterKey()
        let box = try ChaChaPoly.SealedBox(combined: envelope)
        return try ChaChaPoly.open(box, using: key)
    }

    /// Encrypt and save the rclone.conf bytes.
    public func save(_ rcloneConf: Data) async throws {
        let key = try loadOrCreateMasterKey()
        let sealed = try ChaChaPoly.seal(rcloneConf, using: key)
        let envelope = sealed.combined
        let target = AppGroup.rcloneConfURL
        // Ensure the parent directory exists (it usually does via App Group
        // or Application Support, but be defensive on first launch).
        try FileManager.default.createDirectory(
            at: target.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try envelope.write(to: target, options: [.atomic, .completeFileProtection])
    }

    /// Wipe the stored conf and the master key. After this, the next save creates a fresh key.
    public func wipe() async throws {
        if FileManager.default.fileExists(atPath: AppGroup.rcloneConfURL.path) {
            try FileManager.default.removeItem(at: AppGroup.rcloneConfURL)
        }
        try? removeDecryptedTempFile()
        try deleteMasterKey()
    }

    /// True if a stored conf exists.
    public func hasStoredConf() -> Bool {
        FileManager.default.fileExists(atPath: AppGroup.rcloneConfURL.path)
    }

    /// Copies an existing legacy app-only key into the shared Keychain group
    /// used by the FileProvider extension. Safe to call on every launch.
    public func migrateMasterKeyToSharedAccessGroupIfNeeded() async throws {
        _ = try fetchMasterKeyData()
    }

    /// Decrypt the stored conf and write it as plaintext to a temporary
    /// location with full file protection. Returns the URL.
    ///
    /// Used to feed librclone via the `RCLONE_CONFIG` environment variable
    /// since librclone cannot read the encrypted blob directly. The file
    /// is written to the user's Caches directory (excluded from iCloud
    /// backup) and protected with `.completeFileProtection`.
    ///
    /// Throws `RcloneError.engineNotAvailable` when no conf has been imported.
    public func writeDecryptedToTempFile() async throws -> URL {
        guard let plaintext = try await load() else {
            throw RcloneError.engineNotAvailable(String(localized: "Aucune configuration rclone importée"))
        }
        let scrubbed = Self.scrubHostPaths(plaintext)
        let caches = try FileManager.default.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let target = caches.appending(path: "rclone.conf")
        try scrubbed.write(to: target, options: [.atomic, .completeFileProtection])
        return target
    }

    /// Retire les clés qui pointent vers des chemins macOS/Linux (par ex.
    /// `known_hosts_file = /Users/.../.ssh/known_hosts`) hérités d'un
    /// rclone.conf importé depuis un poste desktop. Sur iOS, librclone
    /// échoue avec « no such file or directory » dès que ces chemins sont
    /// utilisés — y compris pour les crypt qui wrapent un SFTP, ce qui
    /// rend tout le remote inutilisable. Le scrub ne touche que les clés
    /// `*_file` dont la valeur commence par un préfixe non-iOS reconnu.
    private static func scrubHostPaths(_ data: Data) -> Data {
        guard var text = String(data: data, encoding: .utf8) else { return data }
        let hostPrefixes = ["/Users/", "/home/", "/root/", "C:\\", "~/"]
        var cleaned: [String] = []
        var dropped: [String] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let eq = trimmed.firstIndex(of: "=") {
                let key = trimmed[..<eq].trimmingCharacters(in: .whitespaces)
                let value = trimmed[trimmed.index(after: eq)...].trimmingCharacters(in: .whitespaces)
                if key.hasSuffix("_file") && hostPrefixes.contains(where: { value.hasPrefix($0) }) {
                    dropped.append("\(key) = \(value)")
                    continue
                }
            }
            cleaned.append(String(line))
        }
        if dropped.isEmpty { return data }
        text = cleaned.joined(separator: "\n")
        Task { @MainActor in
            for d in dropped {
                await LogService.shared.log(
                    .info,
                    category: "config",
                    message: "scrub host-path : \(d) (chemin desktop incompatible iOS, retiré)"
                )
            }
        }
        return Data(text.utf8)
    }

    /// Writes a plaintext copy suitable for iOS sharing/export.
    ///
    /// The exported file intentionally lives in a unique temporary directory
    /// so ShareLink can keep a stable URL for the duration of the share sheet.
    public func exportPlaintextCopy() async throws -> URL {
        guard let plaintext = try await load() else {
            throw RcloneError.engineNotAvailable(String(localized: "Aucune configuration rclone à exporter"))
        }
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "rclone-gui-export-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let target = directory.appending(path: "rclone.conf")
        try plaintext.write(to: target, options: [.atomic, .completeFileProtection])
        return target
    }

    /// Re-encrypts the current plaintext runtime config back into the encrypted
    /// store. librclone persists `config/create` and `config/update` changes to
    /// the plaintext file at the path set via `config/setpath`
    /// (`Caches/rclone.conf`). Without copying it back, a subsequent
    /// `reloadConfigurationFromStore()` overwrites the runtime with the stale
    /// encrypted store and the freshly added remote vanishes — which is exactly
    /// why a wizard-created remote did not appear after import. No-op when the
    /// runtime file is absent or empty.
    public func persistRuntimeConfigToStore() async throws {
        let caches = try FileManager.default.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )
        let runtime = caches.appending(path: "rclone.conf")
        guard FileManager.default.fileExists(atPath: runtime.path) else { return }
        let data = try Data(contentsOf: runtime)
        guard !data.isEmpty else { return }
        try await save(data)
    }

    private func removeDecryptedTempFile() throws {
        let caches = try FileManager.default.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let target = caches.appending(path: "rclone.conf")
        if FileManager.default.fileExists(atPath: target.path) {
            try FileManager.default.removeItem(at: target)
        }
    }

    // MARK: - Master key (Keychain)

    private func loadOrCreateMasterKey() throws -> SymmetricKey {
        if let data = try fetchMasterKeyData() {
            return SymmetricKey(data: data)
        }
        let key = SymmetricKey(size: .bits256)
        let raw = key.withUnsafeBytes { Data($0) }
        try storeMasterKeyData(raw)
        return key
    }

    private func fetchMasterKeyData() throws -> Data? {
        if let sharedGroup = AppGroup.keychainAccessGroup {
            if let shared = try fetchMasterKeyData(accessGroup: sharedGroup) {
                return shared
            }
            if let legacy = try fetchMasterKeyData(accessGroup: nil) {
                try storeMasterKeyData(legacy, accessGroup: sharedGroup)
                return legacy
            }
            return nil
        }

        return try fetchMasterKeyData(accessGroup: nil)
    }

    private func fetchMasterKeyData(accessGroup: String?) throws -> Data? {
        var query = baseKeychainQuery(accessGroup: accessGroup)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            return item as? Data
        case errSecItemNotFound:
            return nil
        default:
            throw RcloneError.engineNotAvailable("Keychain read failed (OSStatus \(status))")
        }
    }

    private func storeMasterKeyData(_ data: Data) throws {
        if let sharedGroup = AppGroup.keychainAccessGroup {
            do {
                try storeMasterKeyData(data, accessGroup: sharedGroup)
                return
            } catch {
                // Keep the main app usable even on builds/profiles where the
                // shared keychain group is not provisioned. FileProvider will
                // still report a configuration error until signing is fixed.
                try storeMasterKeyData(data, accessGroup: nil)
                return
            }
        }
        try storeMasterKeyData(data, accessGroup: nil)
    }

    private func storeMasterKeyData(_ data: Data, accessGroup: String?) throws {
        var attrs = baseKeychainQuery(accessGroup: accessGroup)
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        attrs[kSecValueData as String] = data

        let status = SecItemAdd(attrs as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let query = baseKeychainQuery(accessGroup: accessGroup)
            let update: [String: Any] = [kSecValueData as String: data]
            let updStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)
            guard updStatus == errSecSuccess else {
                throw RcloneError.engineNotAvailable("Keychain update failed (OSStatus \(updStatus))")
            }
            return
        }
        guard status == errSecSuccess else {
            throw RcloneError.engineNotAvailable("Keychain add failed (OSStatus \(status))")
        }
    }

    private func deleteMasterKey() throws {
        var statuses: [OSStatus] = []
        statuses.append(SecItemDelete(baseKeychainQuery(accessGroup: AppGroup.keychainAccessGroup) as CFDictionary))
        statuses.append(SecItemDelete(baseKeychainQuery(accessGroup: nil) as CFDictionary))

        for status in statuses where status != errSecSuccess && status != errSecItemNotFound {
            throw RcloneError.engineNotAvailable("Keychain delete failed (OSStatus \(status))")
        }
    }

    private func baseKeychainQuery(accessGroup: String?) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: masterKeyTag,
        ]
        if let accessGroup, !accessGroup.isEmpty {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }
}
