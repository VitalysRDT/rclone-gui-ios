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
        try deleteMasterKey()
    }

    /// True if a stored conf exists.
    public func hasStoredConf() -> Bool {
        FileManager.default.fileExists(atPath: AppGroup.rcloneConfURL.path)
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
            throw RcloneError.engineNotAvailable("Aucune configuration rclone importée")
        }
        let caches = try FileManager.default.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let target = caches.appending(path: "rclone.conf")
        try plaintext.write(to: target, options: [.atomic, .completeFileProtection])
        return target
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
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: masterKeyTag,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
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
        let attrs: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: masterKeyTag,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data,
        ]
        let status = SecItemAdd(attrs as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: masterKeyTag,
            ]
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
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: masterKeyTag,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw RcloneError.engineNotAvailable("Keychain delete failed (OSStatus \(status))")
        }
    }
}
