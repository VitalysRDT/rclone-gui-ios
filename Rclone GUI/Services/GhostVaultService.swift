//
//  GhostVaultService.swift
//  Rclone GUI — Services
//
//  Orchestrateur Ghost Vault : crée des vaults chiffrés à partir du rclone.conf
//  local, les uploade dans un remote appartenant à l'utilisateur, les liste,
//  et restaure. Toutes les opérations de lecture/écriture de config passent
//  par ConfigStore (master key en Keychain) ; le chiffrement Ghost Vault est
//  INDÉPENDANT de la master key — la passphrase seule ouvre un vault, ce qui
//  rend le backup portable d'un appareil à l'autre.
//
//  Garantie : on chiffre TOUJOURS côté client, même si le remote cible est
//  déjà chiffré (crypt). C'est du defense in depth.
//

import Foundation
import CryptoKit

// MARK: - Public types

/// Représente un vault tel qu'on le voit dans la liste (issu du manifest local
/// ou scanné depuis le remote).
public struct GhostVaultDescriptor: Codable, Sendable, Identifiable, Hashable {
    public let id: String              // = "<remote>:<remotePath>/<filename>"
    public let remote: String
    public let remotePath: String      // ex: "ghost-vaults/ghost-vault-2026-07-09.rclonebackup"
    public let filename: String
    public let sizeBytes: Int
    public let createdAt: Date
    public let deviceName: String
    public let rcloneVersion: String
    public let remoteCount: Int
    /// Provenance : "manifest" (créé ou restauré sur cet appareil) ou "scanned"
    /// (trouvé en scannant le remote).
    public let source: Source

    public enum Source: String, Codable, Sendable, Hashable {
        case manifest
        case scanned
    }
}

/// Préférences de création d'un vault.
public struct GhostVaultCreateRequest: Sendable {
    public let remote: String
    public let folder: String          // dossier dans le remote ("ghost-vaults" par défaut)
    public let passphrase: String
    public let filenameOverride: String?
    public init(remote: String, folder: String = GhostVault.remoteFolder, passphrase: String, filenameOverride: String? = nil) {
        self.remote = remote
        self.folder = folder
        self.passphrase = passphrase
        self.filenameOverride = filenameOverride
    }
}

/// Résultat d'un create : où il a atterri sur le remote.
public struct GhostVaultCreateResult: Sendable {
    public let descriptor: GhostVaultDescriptor
    public let rcloneConfBytes: Int
}

// MARK: - Service

public actor GhostVaultService {
    public static let shared = GhostVaultService()

    private init() {}

    // MARK: Create (backup)

    /// Crée un vault chiffré à partir du rclone.conf actuel et l'upload dans
    /// le remote cible. Le vault final est écrit via TransferQueue (visible
    /// dans l'onglet Transferts) pour qu'on profite du retry + UI de progression.
    public func create(
        request: GhostVaultCreateRequest
    ) async throws -> GhostVaultCreateResult {
        guard let plaintext = try await ConfigStore.shared.load() else {
            throw RcloneError.engineNotAvailable(String(localized: "Aucune configuration rclone à sauvegarder."))
        }
        let rcloneVersion = await currentRcloneVersion()
        let remoteSummaries = try await RemoteService.shared.listRemoteSummaries()
        let remoteType = remoteSummaries.first(where: { $0.name == request.remote })?.type ?? "unknown"
        let isCrypt = (remoteType == "crypt")
        let meta = GhostVaultMeta(
            sizeBytes: plaintext.count,
            remoteCount: remoteSummaries.count,
            createdAt: Date(),
            deviceName: GhostVault.currentDeviceName(),
            rcloneVersion: rcloneVersion
        )
        let envelope = try GhostVault.seal(
            rcloneConf: plaintext,
            passphrase: request.passphrase,
            meta: meta,
            rcloneVersion: rcloneVersion
        )
        let envelopeBytes = try GhostVault.encode(envelope)
        let filename = request.filenameOverride ?? GhostVault.defaultFilename()
        let stagedDir = try stageLocalFile(name: filename, contents: envelopeBytes)
        defer { try? FileManager.default.removeItem(at: stagedDir) }
        let remotePath = request.folder.isEmpty
            ? filename
            : "\(request.folder)/\(filename)"
        try await TransferQueue.shared.enqueueUpload(
            local: stagedDir,
            remote: request.remote,
            path: remotePath,
            sourceKind: .localFile
        )
        let descriptor = GhostVaultDescriptor(
            id: "\(request.remote):\(remotePath)",
            remote: request.remote,
            remotePath: remotePath,
            filename: filename,
            sizeBytes: envelopeBytes.count,
            createdAt: meta.createdAt,
            deviceName: meta.deviceName,
            rcloneVersion: meta.rcloneVersion,
            remoteCount: meta.remoteCount,
            source: .manifest
        )
        try await appendManifest(descriptor: descriptor, isCrypt: isCrypt)
        NotificationCenter.default.post(name: .ghostVaultDidChange, object: nil)
        return GhostVaultCreateResult(
            descriptor: descriptor,
            rcloneConfBytes: plaintext.count
        )
    }

    // MARK: Restore

    /// Télécharge un vault, le déchiffre, et restaure le rclone.conf.
    public func restore(
        descriptor: GhostVaultDescriptor,
        passphrase: String
    ) async throws -> (conf: Data, meta: GhostVaultMeta) {
        let downloaded = try await download(descriptor: descriptor)
        defer { try? FileManager.default.removeItem(at: downloaded) }
        let envelopeBytes = try Data(contentsOf: downloaded)
        let envelope = try GhostVault.decode(envelopeBytes)
        let opened = try GhostVault.open(envelope: envelope, passphrase: passphrase)
        try await ConfigStore.shared.save(opened.rcloneConf)
        try await RcloneCore.shared.reloadConfigurationFromStore()
        await MainActor.run {
            NotificationCenter.default.post(name: .rcloneConfigurationDidChange, object: nil)
            NotificationCenter.default.post(name: .ghostVaultDidChange, object: nil)
        }
        return (opened.rcloneConf, opened.meta)
    }

    // MARK: List

    /// Liste les vaults connus localement (créés ou restaurés sur cet appareil).
    public func listLocalManifest() async throws -> [GhostVaultDescriptor] {
        guard FileManager.default.fileExists(atPath: GhostVault.manifestURL.path) else {
            return []
        }
        let data = try Data(contentsOf: GhostVault.manifestURL)
        return try JSONDecoder().decode([GhostVaultDescriptor].self, from: data)
    }

    /// Liste les vaults présents dans le dossier par défaut d'un remote.
    /// Télécharge chaque fichier `.rclonebackup`, décode le meta (sans
    /// déchiffrer le payload), et retourne la liste.
    public func scanRemote(remote: String, folder: String = GhostVault.remoteFolder) async throws -> [GhostVaultDescriptor] {
        let entries = try await RemoteService.shared.list(remote: remote, path: folder)
        var descriptors: [GhostVaultDescriptor] = []
        for entry in entries where entry.isDirectory == false && entry.name.hasSuffix(".\(GhostVault.fileExtension)") {
            let remotePath = folder.isEmpty ? entry.name : "\(folder)/\(entry.name)"
            let downloadURL = try await downloadToTemp(
                remote: remote,
                remotePath: remotePath,
                filename: entry.name
            )
            defer { try? FileManager.default.removeItem(at: downloadURL) }
            do {
                let data = try Data(contentsOf: downloadURL)
                let envelope = try GhostVault.decode(data)
                let descriptor = GhostVaultDescriptor(
                    id: "\(remote):\(remotePath)",
                    remote: remote,
                    remotePath: remotePath,
                    filename: entry.name,
                    sizeBytes: data.count,
                    createdAt: envelope.createdAt,
                    deviceName: envelope.deviceName,
                    rcloneVersion: envelope.rcloneVersion,
                    remoteCount: envelope.remoteCount,
                    source: .scanned
                )
                descriptors.append(descriptor)
            } catch {
                // On ignore les fichiers corrompus ou non-GhostVault.
                continue
            }
        }
        return descriptors
    }

    // MARK: Delete

    /// Supprime un vault du remote. Le manifest local est mis à jour.
    public func delete(descriptor: GhostVaultDescriptor) async throws {
        try await TransferQueue.shared.enqueueDelete(
            remote: descriptor.remote,
            path: descriptor.remotePath,
            isDirectory: false
        )
        try await removeFromManifest(id: descriptor.id)
        NotificationCenter.default.post(name: .ghostVaultDidChange, object: nil)
    }

    // MARK: Helpers

    private func download(descriptor: GhostVaultDescriptor) async throws -> URL {
        try await downloadToTemp(
            remote: descriptor.remote,
            remotePath: descriptor.remotePath,
            filename: descriptor.filename
        )
    }

    private func downloadToTemp(remote: String, remotePath: String, filename: String) async throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "ghost-vault-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let target = tempDir.appending(path: filename)
        try await TransferQueue.shared.enqueueDownload(
            remote: remote,
            path: remotePath,
            to: target
        )
        return target
    }

    private func stageLocalFile(name: String, contents: Data) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "ghost-vault-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let target = tempDir.appending(path: name)
        try contents.write(to: target, options: [.atomic, .completeFileProtection])
        return target
    }

    private func currentRcloneVersion() async -> String {
        if let v = try? await RcloneCore.shared.version(), !v.isEmpty {
            return v
        }
        return "unknown"
    }

    // MARK: Manifest local

    private func appendManifest(descriptor: GhostVaultDescriptor, isCrypt: Bool) async throws {
        var existing = (try? await listLocalManifest()) ?? []
        // Remplacer si déjà présent (même id), sinon ajouter en tête.
        existing.removeAll { $0.id == descriptor.id }
        existing.insert(descriptor, at: 0)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(existing)
        let target = GhostVault.manifestURL
        try FileManager.default.createDirectory(
            at: target.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: target, options: [.atomic])
    }

    private func removeFromManifest(id: String) async throws {
        var existing = (try? await listLocalManifest()) ?? []
        existing.removeAll { $0.id == id }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(existing)
        try data.write(to: GhostVault.manifestURL, options: [.atomic])
    }
}