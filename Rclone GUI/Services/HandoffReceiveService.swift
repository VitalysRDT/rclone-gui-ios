//
//  HandoffReceiveService.swift
//  Rclone GUI — Services/Handoff
//
//  Orchestrates "Handoff P2P — recevoir". Decodes an HND1: transport
//  payload (from QR / file / clipboard), opens the GhostVault envelope
//  with the Diceware passphrase, and applies the resulting rclone.conf
//  to the local store via three user-selectable strategies:
//
//    - `.replace`: overwrite the local conf with the incoming one
//      (after taking an automatic snapshot of the local one for safety).
//    - `.merge` : merge sections by name; on collision, keep the local
//      remote (preserves valid OAuth tokens). Uses `MockRcloneEngine.parseRcloneConf`
//      to enumerate sections deterministically.
//    - `.cancel`: do nothing.
//
//  FaceID gate required before any write operation (uses `.configWrite`).
//

import Foundation

public enum HandoffReceiveServiceError: Error, LocalizedError, Sendable {
    case invalidPayload(String)
    case badPassphrase(String)
    case emptyPassphrase
    case notAuthorized
    case writeFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidPayload(let why):
            return String(localized: "Payload Handoff invalide : \(why).")
        case .badPassphrase(let why):
            return String(localized: "Impossible de déchiffrer : \(why).")
        case .emptyPassphrase:
            return String(localized: "Saisis les 6 mots de la passphrase.")
        case .notAuthorized:
            return String(localized: "Authentification biométrique requise.")
        case .writeFailed(let why):
            return String(localized: "Écriture impossible : \(why).")
        }
    }
}

public enum HandoffImportStrategy: String, CaseIterable, Sendable {
    case replace
    case merge
    case cancel

    public var localizedTitle: String {
        switch self {
        case .replace: return String(localized: "Remplacer")
        case .merge:   return String(localized: "Fusionner")
        case .cancel:  return String(localized: "Annuler")
        }
    }
}

public struct HandoffMergePlan: Sendable, Equatable {
    public let addedRemotes: [String]
    public let conflictingRemotes: [ConflictEntry]
    public let keptRemotes: [String]
    public let resultingBytes: Int

    public var totalIncomingRemotes: Int {
        addedRemotes.count + conflictingRemotes.count
    }
}

public struct ConflictEntry: Sendable, Equatable, Hashable {
    public let name: String
    public let localType: String
    public let incomingType: String
}

public struct HandoffReceivedEnvelope: Sendable {
    public let payload: String
    public let envelope: GhostVaultEnvelope
    public let meta: GhostVaultMeta
    public let passphraseHint: HandoffPassphraseLanguage?
}

public actor HandoffReceiveService {
    public static let shared = HandoffReceiveService()

    private init() {}

    /// Step 1: parse the transport payload without unsealing. Returns
    /// the metadata the UI needs to show "3 remotes, 2 KB, on device X".
    public func inspect(payload: String) throws -> HandoffReceivedEnvelope {
        let envelope = try HandoffEnvelope.decode(payload)
        return HandoffReceivedEnvelope(
            payload: payload,
            envelope: envelope,
            meta: Self.extractMeta(from: envelope),
            passphraseHint: nil
        )
    }

    /// Step 2: open the envelope with a passphrase. Throws `badPassphrase`
    /// if the passphrase is wrong or the payload is tampered.
    public func unseal(payload: String, passphrase: String) throws -> (rcloneConf: Data, meta: GhostVaultMeta) {
        let envelope = try HandoffEnvelope.decode(payload)
        do {
            return try GhostVault.open(envelope: envelope, passphrase: passphrase)
        } catch GhostVaultError.decryptionFailed,
                GhostVaultError.decryptionMismatch,
                GhostVaultError.payloadCorrupt {
            throw HandoffReceiveServiceError.badPassphrase("mot de passe incorrect ou payload altéré")
        } catch {
            throw HandoffReceiveServiceError.badPassphrase(String(describing: error))
        }
    }

    /// Step 2-bis: same as `unseal` but the passphrase comes from the
    /// receiver typing 6 words. Splits + lowercases first.
    public func unseal(
        payload: String,
        passphraseWords: [String],
        language: HandoffPassphraseLanguage = .french
    ) throws -> (rcloneConf: Data, meta: GhostVaultMeta) {
        guard !passphraseWords.isEmpty else {
            throw HandoffReceiveServiceError.emptyPassphrase
        }
        return try unseal(payload: payload, passphrase: HandoffPassphrase.join(passphraseWords))
    }

    public func buildMergePlan(local: Data, incoming: Data) -> HandoffMergePlan {
        let localSections = sectionDict(local)
        let incomingSections = sectionDict(incoming)
        var added: [String] = []
        var conflicts: [ConflictEntry] = []  
        var kept: [String] = []
        for (name, incoming) in incomingSections {
            if let local = localSections[name] {
                if local.body == incoming.body {
                    kept.append(name)
                } else {
                    conflicts.append(ConflictEntry(name: name, localType: local.type, incomingType: incoming.type))
                }
            } else {
                added.append(name)
            }
        }
        let merged = mergeINI(local: local, incoming: incoming, acceptedIncomingNames: Set(added))
        return HandoffMergePlan(
            addedRemotes: added.sorted(),
            conflictingRemotes: conflicts.sorted { $0.name < $1.name },
            keptRemotes: kept.sorted(),
            resultingBytes: merged.count
        )
    }

    /// Step 3: apply. Caller chooses the strategy. FaceID-gated because
    /// we touch the encrypted store. `.cancel` is a no-op.
    public func apply(
        strategy: HandoffImportStrategy,
        payload: String,
        passphraseWords: [String],
        language: HandoffPassphraseLanguage = .french,
        biometricReason: BiometricReason = .handoffReceive
    ) async throws -> HandoffApplyResult {
        switch strategy {
        case .cancel:
            return HandoffApplyResult(strategy: strategy, appliedCount: 0, snapshotURL: nil)
        case .replace, .merge:
            break
        }
        let bio = await BiometricGate.shared.authenticate(reason: biometricReason)
        guard bio == .authenticated else {
            throw HandoffReceiveServiceError.notAuthorized
        }
        let opened = try unseal(
            payload: payload,
            passphraseWords: passphraseWords,
            language: language
        )
        let localSnapshot: URL?
        switch strategy {
        case .replace:
            localSnapshot = try await snapshotLocalConf()
        default:
            localSnapshot = nil
        }
        let toWrite: Data
        switch strategy {
        case .replace:
            toWrite = opened.rcloneConf
        case .merge:
            let local = (try await ConfigStore.shared.load()) ?? Data()
            toWrite = mergeINI(local: local, incoming: opened.rcloneConf, acceptedIncomingNames: nil)
        case .cancel:
            return HandoffApplyResult(strategy: strategy, appliedCount: 0, snapshotURL: nil)
        }
        do {
            try await ConfigStore.shared.save(toWrite)
            try await ConfigStore.shared.migrateMasterKeyToSharedAccessGroupIfNeeded()
        } catch {
            throw HandoffReceiveServiceError.writeFailed(String(describing: error))
        }
        await MainActor.run {
            NotificationCenter.default.post(name: .rcloneConfigurationDidChange, object: nil)
        }
        let applied = MockRcloneEngine.parseRcloneConf(toWrite).count
        return HandoffApplyResult(
            strategy: strategy,
            appliedCount: applied,
            snapshotURL: localSnapshot
        )
    }

    // MARK: helpers

    private struct ParsedSection {
        let name: String
        let type: String
        let body: String
    }

    private static func extractMeta(from envelope: GhostVaultEnvelope) -> GhostVaultMeta {
        guard let metaData = Data(base64Encoded: envelope.metaB64),
              let meta = try? JSONDecoder().decode(GhostVaultMeta.self, from: metaData)
        else {
            return GhostVaultMeta(
                sizeBytes: 0,
                remoteCount: envelope.remoteCount,
                createdAt: envelope.createdAt,
                deviceName: envelope.deviceName,
                rcloneVersion: envelope.rcloneVersion
            )
        }
        return meta
    }

    /// Snapshot the local conf (if any) as a `.rclonebackup` in a
    /// app-private pre-import directory so the user can restore it
    /// later if the import is bad. Returns the URL.
    private func snapshotLocalConf() async throws -> URL? {
        guard let plaintext = try await ConfigStore.shared.load() else { return nil }
        let snapshotsDir = AppGroup.containerURL
            .appending(path: "Library", directoryHint: .isDirectory)
            .appending(path: "handoff-snapshots", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: snapshotsDir, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: Date())
        let safeStamp = stamp.replacingOccurrences(of: ":", with: "-")
        let target = snapshotsDir.appending(path: "pre-handoff-\(safeStamp).rclone.conf")
        try plaintext.write(to: target, options: [.atomic, .completeFileProtection])
        return target
    }
}

public struct HandoffApplyResult: Sendable {
    public let strategy: HandoffImportStrategy
    public let appliedCount: Int
    public let snapshotURL: URL?
}

// MARK: - INI helpers

nonisolated private func sectionDict(_ data: Data) -> [String: HandoffReceiveService_Section] {
    let summaries = MockRcloneEngine.parseRcloneConf(data)
    guard let text = String(data: data, encoding: .utf8) else { return [:] }
    var result: [String: HandoffReceiveService_Section] = [:]
    var currentName: String?
    var currentType: String = "unknown"
    var currentLines: [String] = []
    var currentRaw: [String] = []
    func flush() {
        if let name = currentName {
            let body = currentLines.joined(separator: "\n")
            result[name] = HandoffReceiveService_Section(
                name: name,
                type: currentType,
                body: body
            )
        }
        currentName = nil
        currentType = "unknown"
        currentLines = []
        currentRaw = []
    }
    for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
        let line = String(raw)
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            currentRaw.append(line)
            continue
        }
        if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
            flush()
            currentName = String(trimmed.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
            currentRaw = [line]
            continue
        }
        if let eq = trimmed.firstIndex(of: "=") {
            let key = String(trimmed[..<eq]).trimmingCharacters(in: .whitespaces)
            if key == "type" {
                let value = String(trimmed[trimmed.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
                currentType = value
            }
        }
        currentRaw.append(line)
        currentLines.append(trimmed)
    }
    flush()
    _ = currentRaw
    _ = summaries
    return result
}

struct HandoffReceiveService_Section {
    let name: String
    let type: String
    let body: String
}

/// Merge two rclone.conf blobs. Sections present in `local` are kept
/// verbatim. Sections present in `incoming` are appended unless their
/// name collides with a local section — in which case:
///   - if `acceptedIncomingNames` is non-nil, ONLY those names from the
///     incoming blob are appended,
///   - if `acceptedIncomingNames` is nil (replace semantics), incoming
///     sections still don't overwrite locals (safer default).
nonisolated func mergeINI(local: Data, incoming: Data, acceptedIncomingNames: Set<String>?) -> Data {
    let localText = String(data: local, encoding: .utf8) ?? ""
    let incomingText = String(data: incoming, encoding: .utf8) ?? ""
    let localNames = Set(MockRcloneEngine.parseRcloneConf(local).map(\.name))
    var header = localText
    if !header.isEmpty && !header.hasSuffix("\n") { header += "\n" }
    if header.isEmpty { header += "\n" }
    var newSections: [String] = []
    var currentName: String?
    var currentBlock: [String] = []
    func flush() {
        if let name = currentName, !localNames.contains(name) {
            newSections.append(currentBlock.joined(separator: "\n"))
        }
        currentName = nil
        currentBlock = []
    }
    for raw in incomingText.split(separator: "\n", omittingEmptySubsequences: false) {
        let line = String(raw)
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
            flush()
            let name = String(trimmed.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
            if localNames.contains(name) {
                currentName = nil
                continue
            }
            if let accepted = acceptedIncomingNames, !accepted.contains(name) {
                currentName = nil
                continue
            }
            currentName = name
            currentBlock = [line]
            continue
        }
        if currentName != nil {
            currentBlock.append(line)
        }
    }
    flush()
    if !newSections.isEmpty {
        header += "\n" + newSections.joined(separator: "\n\n") + "\n"
    }
    return Data(header.utf8)
}
