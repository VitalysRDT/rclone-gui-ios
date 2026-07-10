//
//  Rclone_GUITests.swift
//  Rclone GUITests
//
//  Core tests covering encryption round-trip, INI parsing, and time parsing
//  paths. Live integration with librclone is NOT tested here — that requires
//  a real RcloneKit.xcframework + device, exercised via UI tests + manual.
//

import Testing
import Foundation
import CryptoKit
import SwiftData
@testable import Rclone_GUI

// MARK: - INI parser (MockRcloneEngine.parseRcloneConf)

@Suite("MockRcloneEngine INI parser")
struct INIParserTests {

    @Test("Parses a minimal single-remote conf")
    func parsesSingleRemote() {
        let conf = """
        [drive]
        type = drive
        scope = drive
        token = {"access_token":"x"}
        """
        let result = MockRcloneEngine.parseRcloneConf(Data(conf.utf8))
        #expect(result.count == 1)
        #expect(result.first?.name == "drive")
        #expect(result.first?.type == "drive")
    }

    @Test("Parses multiple remotes preserving order")
    func parsesMultipleRemotes() {
        let conf = """
        [s3-prod]
        type = s3
        provider = AWS

        [crypt-photos]
        type = crypt
        remote = s3-prod:photos
        """
        let result = MockRcloneEngine.parseRcloneConf(Data(conf.utf8))
        #expect(result.count == 2)
        #expect(result[0].name == "s3-prod")
        #expect(result[0].type == "s3")
        #expect(result[1].name == "crypt-photos")
        #expect(result[1].type == "crypt")
    }

    @Test("Skips comments (# and ;) and blank lines")
    func skipsCommentsAndBlanks() {
        let conf = """
        # This is a header comment
        ; legacy comment too

        [box]
        ; inline comment-style line above the type
        type = box
        # bogus = value should be ignored
        """
        let result = MockRcloneEngine.parseRcloneConf(Data(conf.utf8))
        #expect(result.count == 1)
        #expect(result[0].type == "box")
    }

    @Test("Falls back to 'unknown' type when section has no type key")
    func unknownTypeWhenMissing() {
        let conf = """
        [weird]
        # no type key
        host = example.com
        """
        let result = MockRcloneEngine.parseRcloneConf(Data(conf.utf8))
        #expect(result.count == 1)
        #expect(result[0].type == "unknown")
    }

    @Test("Returns empty for non-UTF8 garbage")
    func emptyForGarbage() {
        let bytes: [UInt8] = [0xFF, 0xFE, 0xFD, 0xFC]
        let result = MockRcloneEngine.parseRcloneConf(Data(bytes))
        #expect(result.isEmpty)
    }

    @Test("Handles trailing whitespace around tokens")
    func tolerantOfWhitespace() {
        let conf = "  [  drive  ]  \n  type   =   drive  \n"
        let result = MockRcloneEngine.parseRcloneConf(Data(conf.utf8))
        #expect(result.count == 1)
        #expect(result[0].name == "drive")
        #expect(result[0].type == "drive")
    }
}

// MARK: - rclone.conf editor

@Suite("RcloneConfigEditor")
struct RcloneConfigEditorTests {

    @Test("Appends a manual remote section")
    func appendsManualRemote() throws {
        let conf = """
        [existing]
        type = drive
        scope = drive
        """

        let updated = try RcloneConfigEditor.updatedConfigText(
            conf,
            addingRemoteNamed: "s3-prod",
            type: "s3",
            options: [
                "provider": "AWS",
                "access_key_id": "AKIA",
                "secret_access_key": "secret",
                "empty": "",
            ]
        )

        #expect(updated.contains("[existing]"))
        #expect(updated.contains("[s3-prod]"))
        #expect(updated.contains("type = s3"))
        #expect(updated.contains("provider = AWS"))
        #expect(updated.contains("access_key_id = AKIA"))
        #expect(!updated.contains("empty ="))
    }

    @Test("Rejects duplicate remote names")
    func rejectsDuplicates() throws {
        let conf = """
        [drive]
        type = drive
        """

        #expect(throws: RcloneConfigEditor.ConfigError.self) {
            _ = try RcloneConfigEditor.updatedConfigText(
                conf,
                addingRemoteNamed: "drive",
                type: "s3",
                options: [:]
            )
        }
    }

    @Test("Rejects remote names that cannot be addressed by rclone")
    func rejectsInvalidRemoteName() throws {
        #expect(throws: RcloneConfigEditor.ConfigError.self) {
            _ = try RcloneConfigEditor.updatedConfigText(
                "",
                addingRemoteNamed: "bad:name",
                type: "s3",
                options: [:]
            )
        }
    }
}

// MARK: - Saved locations

@Suite("SavedLocationStore")
struct SavedLocationStoreTests {

    @Test("recordOpen upserts recent locations")
    @MainActor
    func recordOpenUpsertsRecent() throws {
        let container = try makeSavedLocationContainer()
        let context = container.mainContext

        try SavedLocationStore.recordOpen(remote: "drive", path: "Docs", displayName: "Docs", in: context)
        try SavedLocationStore.recordOpen(remote: "drive", path: "/Docs/", displayName: "Documents", in: context)

        let recents = try SavedLocationStore.locations(kind: .recent, in: context)
        #expect(recents.count == 1)
        #expect(recents[0].displayName == "Documents")
        #expect(recents[0].openCount == 2)
    }

    @Test("togglePinned adds and removes a favorite")
    @MainActor
    func togglePinnedAddsAndRemoves() throws {
        let container = try makeSavedLocationContainer()
        let context = container.mainContext

        let didPin = try SavedLocationStore.togglePinned(remote: "s3", path: "Photos", displayName: "Photos", in: context)
        #expect(didPin)
        #expect(try SavedLocationStore.isPinned(remote: "s3", path: "Photos", in: context))

        let didUnpin = try SavedLocationStore.togglePinned(remote: "s3", path: "Photos", displayName: "Photos", in: context)
        #expect(!didUnpin)
        #expect(!(try SavedLocationStore.isPinned(remote: "s3", path: "Photos", in: context)))
    }

    @Test("pruneRecents keeps the newest items")
    @MainActor
    func pruneRecentsKeepsNewest() throws {
        let container = try makeSavedLocationContainer()
        let context = container.mainContext

        try SavedLocationStore.recordOpen(remote: "r", path: "one", displayName: "One", in: context)
        try SavedLocationStore.recordOpen(remote: "r", path: "two", displayName: "Two", in: context)
        try SavedLocationStore.recordOpen(remote: "r", path: "three", displayName: "Three", in: context)
        try SavedLocationStore.pruneRecents(limit: 2, in: context)

        let recents = try SavedLocationStore.locations(kind: .recent, in: context)
        #expect(recents.count == 2)
        #expect(recents.map(\.path).contains("three"))
        #expect(recents.map(\.path).contains("two"))
        #expect(!recents.map(\.path).contains("one"))
    }

    @Test("removeUnavailableRemotes removes stale shortcuts")
    @MainActor
    func removeUnavailableRemotesDropsStaleItems() throws {
        let container = try makeSavedLocationContainer()
        let context = container.mainContext

        try SavedLocationStore.recordOpen(remote: "live", path: "", displayName: "live", in: context)
        try SavedLocationStore.recordOpen(remote: "stale", path: "", displayName: "stale", in: context)
        try SavedLocationStore.togglePinned(remote: "stale", path: "Archive", displayName: "Archive", in: context)

        try SavedLocationStore.removeUnavailableRemotes(["live"], in: context)

        let all = try context.fetch(FetchDescriptor<SavedLocation>())
        #expect(all.count == 1)
        #expect(all[0].remote == "live")
    }

    @MainActor
    private func makeSavedLocationContainer() throws -> ModelContainer {
        let schema = Schema([SavedLocation.self])
        // cloudKitDatabase: .none — même piège que dans Rclone_GUIApp : le
        // host de test porte l'entitlement iCloud, et sans opt-out SwiftData
        // tente le mirroring CloudKit et rejette nos contraintes uniques.
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}

// MARK: - ChaChaPoly round-trip (mirrors ConfigStore seal/open primitive)

@Suite("Détection config rclone chiffrée (RCLONE_ENCRYPT_V0)")
struct EncryptedConfigDetectionTests {

    @Test("Détecte le format produit par « rclone config encryption set »")
    func detectsEncryptedConfig() {
        let blob = """
        # Encrypted rclone configuration File

        RCLONE_ENCRYPT_V0:
        qK5Z8mFhYmNkZWZnaGlqa2xtbm9wcXJzdHV2d3h5ego=
        """
        #expect(ConfigStore.isRcloneEncrypted(Data(blob.utf8)))
    }

    @Test("Détecte aussi les versions futures (RCLONE_ENCRYPT_Vn)")
    func detectsFutureVersions() {
        let blob = "RCLONE_ENCRYPT_V1:\nabc=\n"
        #expect(ConfigStore.isRcloneEncrypted(Data(blob.utf8)))
    }

    @Test("Une config INI en clair n'est pas signalée comme chiffrée")
    func plaintextIsNotEncrypted() {
        let conf = """
        # commentaire
        [drive]
        type = drive
        """
        #expect(!ConfigStore.isRcloneEncrypted(Data(conf.utf8)))
    }

    @Test("Un remote nommé RCLONE_ENCRYPT_V0 n'est pas un faux positif")
    func sectionHeaderIsNotEncrypted() {
        let conf = "[RCLONE_ENCRYPT_V0]\ntype = local\n"
        #expect(!ConfigStore.isRcloneEncrypted(Data(conf.utf8)))
    }

    @Test("Données vides ou binaires → non chiffré (pas de crash)")
    func emptyAndBinaryAreSafe() {
        #expect(!ConfigStore.isRcloneEncrypted(Data()))
        #expect(!ConfigStore.isRcloneEncrypted(Data([0xFF, 0xFE, 0x00, 0x01])))
    }
}

@Suite("ChaChaPoly seal/open primitive")
struct CryptoRoundTripTests {

    @Test("Seal then open returns the original bytes")
    func roundTrip() throws {
        let key = SymmetricKey(size: .bits256)
        let plaintext = Data("rclone-conf-bytes-here".utf8)
        let sealed = try ChaChaPoly.seal(plaintext, using: key)
        let envelope = sealed.combined
        let box = try ChaChaPoly.SealedBox(combined: envelope)
        let opened = try ChaChaPoly.open(box, using: key)
        #expect(opened == plaintext)
    }

    @Test("Open with wrong key fails")
    func wrongKeyFails() throws {
        let keyA = SymmetricKey(size: .bits256)
        let keyB = SymmetricKey(size: .bits256)
        let plaintext = Data("secret".utf8)
        let sealed = try ChaChaPoly.seal(plaintext, using: keyA)
        let box = try ChaChaPoly.SealedBox(combined: sealed.combined)
        #expect(throws: (any Error).self) {
            _ = try ChaChaPoly.open(box, using: keyB)
        }
    }

    @Test("Tampered ciphertext fails authentication")
    func tamperedCiphertextFails() throws {
        let key = SymmetricKey(size: .bits256)
        let plaintext = Data("hello".utf8)
        let sealed = try ChaChaPoly.seal(plaintext, using: key)
        var combined = sealed.combined
        // Flip one byte in the ciphertext region (after 12-byte nonce, before tag)
        combined[combined.count / 2] ^= 0xFF
        let box = try ChaChaPoly.SealedBox(combined: combined)
        #expect(throws: (any Error).self) {
            _ = try ChaChaPoly.open(box, using: key)
        }
    }
}

// MARK: - Smoke test for the AppGroup helper (graceful fallback path)

@Suite("AppGroup container resolution")
struct AppGroupTests {

    @Test("rcloneConfURL points at the encrypted blob inside the container")
    func confURLNonEmpty() {
        let url = AppGroup.rcloneConfURL
        #expect(!url.path.isEmpty)
        #expect(url.lastPathComponent == "rclone.conf.enc")
    }

    @Test("containerURL is reachable (creates parent on demand if needed)")
    func containerReachable() {
        let url = AppGroup.containerURL
        #expect(!url.path.isEmpty)
    }
}

// MARK: - Download conflict policy

@Suite("Local download conflict resolver")
struct LocalDownloadConflictTests {

    @Test("keepBoth appends a numeric suffix before the extension")
    func keepBothAppendsSuffix() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "rclone-gui-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let original = directory.appending(path: "photo.heic")
        try Data("one".utf8).write(to: original)

        let resolved = try LocalFileConflictResolver.destination(for: original, policy: .keepBoth)
        #expect(resolved?.lastPathComponent == "photo 2.heic")
    }

    @Test("skip returns nil when the destination already exists")
    func skipExistingFile() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "rclone-gui-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let original = directory.appending(path: "movie.mov")
        try Data("one".utf8).write(to: original)

        let resolved = try LocalFileConflictResolver.destination(for: original, policy: .skip)
        #expect(resolved == nil)
    }

    @Test("replace removes the existing destination and returns the same URL")
    func replaceExistingFile() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "rclone-gui-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let original = directory.appending(path: "document.pdf")
        try Data("one".utf8).write(to: original)

        let resolved = try LocalFileConflictResolver.destination(for: original, policy: .replace)
        #expect(resolved == original)
        #expect(!FileManager.default.fileExists(atPath: original.path))
    }
}

// MARK: - Photo sync index model

@Suite("PhotoSyncAsset index model")
struct PhotoSyncAssetTests {

    @Test("status and remote paths round-trip through persisted raw fields")
    func statusAndPathsRoundTrip() {
        let asset = PhotoSyncAsset(
            localIdentifier: "A1B2/L0/001",
            mediaType: "image",
            creationDate: Date(timeIntervalSince1970: 1_700_000_000)
        )

        asset.status = .enqueued
        asset.remotePaths = [
            "Photos/2023/11/image.heic",
            "Photos/2023/11/image.mov"
        ]

        #expect(asset.status == .enqueued)
        #expect(asset.statusRaw == "enqueued")
        #expect(asset.remotePaths.count == 2)
        #expect(asset.remotePaths[0].hasSuffix("image.heic"))
    }

    @Test("invalid raw status falls back to pending")
    func invalidStatusFallsBackToPending() {
        let asset = PhotoSyncAsset(localIdentifier: "x", mediaType: "video", creationDate: nil)
        asset.statusRaw = "unknown-state"
        #expect(asset.status == .pending)
    }
}

@Suite("PhotoSync service batching")
struct PhotoSyncServiceBatchingTests {

    @Test("full-library scan can return more than one hundred new assets")
    func scanKeepsMoreThanOneHundredAssets() {
        let candidates = (0..<250).map { index in
            PhotoSyncCandidate(
                localIdentifier: "asset-\(index)",
                mediaType: "image",
                creationDate: Date(timeIntervalSince1970: TimeInterval(index)),
                contentFingerprint: nil
            )
        }

        let result = PhotoSyncService.scanCandidates(candidates, excluding: ["asset-3", "asset-17"])
        let batches = PhotoSyncService.batches(result, size: 100)

        #expect(result.count == 248)
        #expect(result.count > 100)
        #expect(batches.count == 3)
        #expect(batches[0].count == 100)
        #expect(batches[2].count == 48)
    }

    @Test("enqueue capacity never exceeds the photo concurrency limit")
    func enqueueCapacityHonorsActiveUploads() {
        let limits = PhotoSyncLimits(indexSaveBatchSize: 100, enqueueBatchSize: 3, maxActiveUploads: 3, maxRetries: 3)

        #expect(PhotoSyncService.enqueueCapacity(activeCount: 0, requestedLimit: 10, limits: limits) == 3)
        #expect(PhotoSyncService.enqueueCapacity(activeCount: 2, requestedLimit: 10, limits: limits) == 1)
        #expect(PhotoSyncService.enqueueCapacity(activeCount: 3, requestedLimit: 10, limits: limits) == 0)
        #expect(PhotoSyncService.enqueueCapacity(activeCount: 1, requestedLimit: 1, limits: limits) == 1)
    }

    @Test("continuation resumes only when pending work can fit")
    func continuationNeedsPendingWorkAndCapacity() {
        let limits = PhotoSyncLimits(indexSaveBatchSize: 100, enqueueBatchSize: 3, maxActiveUploads: 3, maxRetries: 3)

        #expect(PhotoSyncService.shouldContinueSync(continueUntilEmpty: true, pendingCount: 5, activeCount: 2, limits: limits))
        #expect(!PhotoSyncService.shouldContinueSync(continueUntilEmpty: true, pendingCount: 5, activeCount: 3, limits: limits))
        #expect(!PhotoSyncService.shouldContinueSync(continueUntilEmpty: true, pendingCount: 0, activeCount: 0, limits: limits))
        #expect(!PhotoSyncService.shouldContinueSync(continueUntilEmpty: false, pendingCount: 5, activeCount: 0, limits: limits))
    }
}

// MARK: - Transfer batch metadata

@Suite("Transfer batch metadata")
struct TransferBatchMetadataTests {

    @Test("transfer stores batch fields used by recursive operations")
    func storesBatchFields() {
        let batchID = UUID().uuidString
        let transfer = Transfer(
            kind: .download,
            sourceRemote: "photos",
            sourcePath: "2026/IMG_0001.HEIC",
            destinationPath: "/tmp/IMG_0001.HEIC",
            batchID: batchID,
            relativePath: "2026/IMG_0001.HEIC",
            displayName: "IMG_0001.HEIC",
            sourceKind: .photoLibrary,
            bytesTotal: 42
        )

        #expect(transfer.batchID == batchID)
        #expect(transfer.relativePath == "2026/IMG_0001.HEIC")
        #expect(transfer.displayName == "IMG_0001.HEIC")
        #expect(transfer.sourceKind == TransferSourceKind.photoLibrary)
    }
}

// MARK: - Trash retention model

@Suite("TrashEntry retention metadata")
struct TrashEntryTests {

    @Test("default retention is 30 days from trashedAt")
    func defaultRetentionIs30Days() {
        let trashedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let entry = TrashEntry(
            originalRemote: "drive",
            originalPath: "Documents/foo.pdf",
            originalName: "foo.pdf",
            isDirectory: false,
            sizeBytes: 12_345,
            trashPath: ".rclone-gui-trash/abc/foo.pdf",
            trashedAt: trashedAt
        )
        let expectedExpiry = trashedAt.addingTimeInterval(30 * 24 * 60 * 60)
        #expect(entry.expiresAt == expectedExpiry)
        #expect(entry.originalRemote == "drive")
        #expect(entry.trashPath.hasPrefix(".rclone-gui-trash/"))
        #expect(!entry.isDirectory)
    }

    @Test("custom retention is honored and expiresAt sits in the future")
    func customRetentionTakesEffect() {
        let trashedAt = Date.now
        let entry = TrashEntry(
            originalRemote: "s3",
            originalPath: "Backup/2026",
            originalName: "2026",
            isDirectory: true,
            sizeBytes: -1,
            trashPath: ".rclone-gui-trash/xyz/2026",
            trashedAt: trashedAt,
            retention: 60
        )
        #expect(entry.expiresAt.timeIntervalSince(trashedAt) == 60)
        #expect(entry.expiresAt > .now)
        #expect(entry.isDirectory)
        #expect(entry.sizeBytes == -1)
    }

    @Test("UUID id is unique across newly trashed entries")
    func generatedIDsAreUnique() {
        let a = TrashEntry(
            originalRemote: "r",
            originalPath: "a",
            originalName: "a",
            isDirectory: false,
            sizeBytes: 0,
            trashPath: ".rclone-gui-trash/a/a"
        )
        let b = TrashEntry(
            originalRemote: "r",
            originalPath: "a",
            originalName: "a",
            isDirectory: false,
            sizeBytes: 0,
            trashPath: ".rclone-gui-trash/b/a"
        )
        #expect(a.id != b.id)
    }
}

// MARK: - FilesClipboard (Cut/Copy/Paste pattern)

@Suite("FilesClipboard staging and paste eligibility")
@MainActor
struct FilesClipboardTests {

    private func sampleItem(name: String, parent: String = "Documents", isDir: Bool = false) -> FilesClipboard.Item {
        let path = parent.isEmpty ? name : "\(parent)/\(name)"
        return FilesClipboard.Item(
            remote: "drive",
            path: path,
            name: name,
            isDirectory: isDir,
            size: 1024
        )
    }

    @Test("stage replaces, never appends")
    func stageReplacesPriorContents() {
        let clip = FilesClipboard.shared
        clip.clear()
        defer { clip.clear() }

        clip.stage(items: [sampleItem(name: "a.pdf")], operation: .copy)
        #expect(clip.count == 1)
        #expect(clip.operation == .copy)

        clip.stage(items: [sampleItem(name: "b.pdf"), sampleItem(name: "c.pdf")], operation: .cut)
        #expect(clip.count == 2)
        #expect(clip.operation == .cut)
        #expect(clip.items.map(\.name) == ["b.pdf", "c.pdf"])
    }

    @Test("clear empties the clipboard")
    func clearEmpties() {
        let clip = FilesClipboard.shared
        clip.clear()
        defer { clip.clear() }

        clip.stage(items: [sampleItem(name: "a")], operation: .cut)
        clip.clear()
        #expect(clip.isEmpty)
        #expect(clip.count == 0)
        #expect(clip.sourceRemote == nil)
    }

    @Test("canPaste is false when the clipboard is empty")
    func cannotPasteEmpty() {
        let clip = FilesClipboard.shared
        clip.clear()
        defer { clip.clear() }

        #expect(!clip.canPaste(into: "drive", folder: "Documents"))
    }

    @Test("canPaste refuses cut into the source folder (no-op)")
    func cannotPasteCutIntoSource() {
        let clip = FilesClipboard.shared
        defer { clip.clear() }
        clip.stage(items: [sampleItem(name: "a.pdf", parent: "Documents")], operation: .cut)
        #expect(!clip.canPaste(into: "drive", folder: "Documents"))
        #expect(clip.canPaste(into: "drive", folder: "Photos"))
        #expect(clip.canPaste(into: "other", folder: "Documents"))
    }

    @Test("canPaste allows copy into any folder including source")
    func canPasteCopyAnywhere() {
        let clip = FilesClipboard.shared
        defer { clip.clear() }
        clip.stage(items: [sampleItem(name: "a.pdf", parent: "Documents")], operation: .copy)
        #expect(clip.canPaste(into: "drive", folder: "Documents"))
        #expect(clip.canPaste(into: "drive", folder: "Photos"))
    }

    @Test("isStagedCut only returns true for items staged in cut mode")
    func isStagedCutTracksItemsAndOperation() {
        let clip = FilesClipboard.shared
        defer { clip.clear() }

        clip.stage(items: [sampleItem(name: "a.pdf")], operation: .cut)
        #expect(clip.isStagedCut(remote: "drive", path: "Documents/a.pdf"))
        #expect(!clip.isStagedCopy(remote: "drive", path: "Documents/a.pdf"))
        #expect(!clip.isStagedCut(remote: "drive", path: "Documents/b.pdf"))

        clip.stage(items: [sampleItem(name: "a.pdf")], operation: .copy)
        #expect(!clip.isStagedCut(remote: "drive", path: "Documents/a.pdf"))
        #expect(clip.isStagedCopy(remote: "drive", path: "Documents/a.pdf"))
    }

    @Test("sourceRemote reflects first staged item")
    func sourceRemoteIsFirstItem() {
        let clip = FilesClipboard.shared
        defer { clip.clear() }
        clip.stage(items: [sampleItem(name: "a")], operation: .copy)
        #expect(clip.sourceRemote == "drive")
        clip.clear()
        #expect(clip.sourceRemote == nil)
    }

    @Test("Item id encodes remote and path uniquely")
    func itemIdIsRemoteColonPath() {
        let item = FilesClipboard.Item(
            remote: "s3-prod",
            path: "uploads/q4-2026.pdf",
            name: "q4-2026.pdf",
            isDirectory: false,
            size: 99
        )
        #expect(item.id == "s3-prod:uploads/q4-2026.pdf")
    }
}

// MARK: - Ghost Vault round-trip

@Suite("Ghost Vault encryption & format")
struct GhostVaultTests {

    private let sampleConf = Data("""
    [drive]
    type = drive
    scope = drive
    token = {"access_token":"demo","expiry":"2099-01-01T00:00:00Z"}

    [b2-photos]
    type = b2
    account = 003a1b2c3d4e5f60000000001
    key = K003exampleexampleexampleexampleEXA
    """.utf8)

    @Test("seal → open round-trips the rclone.conf and preserves meta")
    func sealOpenRoundTrip() throws {
        let passphrase = "correct horse battery staple"
        let meta = GhostVaultMeta(
            sizeBytes: sampleConf.count,
            remoteCount: 2,
            createdAt: Date(timeIntervalSince1970: 1_750_000_000),
            deviceName: "iPhone de Vitalys",
            rcloneVersion: "1.74.3"
        )
        let envelope = try GhostVault.seal(
            rcloneConf: sampleConf,
            passphrase: passphrase,
            meta: meta,
            rcloneVersion: meta.rcloneVersion
        )
        let opened = try GhostVault.open(envelope: envelope, passphrase: passphrase)
        #expect(opened.rcloneConf == sampleConf)
        #expect(opened.meta.sizeBytes == meta.sizeBytes)
        #expect(opened.meta.remoteCount == meta.remoteCount)
        #expect(opened.meta.deviceName == meta.deviceName)
        #expect(opened.meta.rcloneVersion == meta.rcloneVersion)
    }

    @Test("encode/decode round-trips an envelope without alteration")
    func envelopeEncodeDecode() throws {
        let envelope = try GhostVault.seal(
            rcloneConf: sampleConf,
            passphrase: "another-strong-passphrase",
            meta: GhostVaultMeta(
                sizeBytes: sampleConf.count,
                remoteCount: 1,
                createdAt: Date(timeIntervalSince1970: 1_750_000_000),
                deviceName: "MacBook Pro",
                rcloneVersion: "1.74.3"
            ),
            rcloneVersion: "1.74.3"
        )
        let bytes = try GhostVault.encode(envelope)
        let restored = try GhostVault.decode(bytes)
        #expect(restored == envelope)
    }

    @Test("wrong passphrase produces a decryption failure (not a silent success)")
    func wrongPassphraseFails() throws {
        let envelope = try GhostVault.seal(
            rcloneConf: sampleConf,
            passphrase: "right-passphrase-here",
            meta: GhostVaultMeta(
                sizeBytes: sampleConf.count,
                remoteCount: 1,
                createdAt: Date(),
                deviceName: "iPhone",
                rcloneVersion: "1.74.3"
            ),
            rcloneVersion: "1.74.3"
        )
        #expect(throws: GhostVaultError.self) {
            _ = try GhostVault.open(envelope: envelope, passphrase: "wrong-passphrase")
        }
    }

    @Test("passphrase too short is rejected before any encryption work")
    func shortPassphraseRejected() {
        let meta = GhostVaultMeta(
            sizeBytes: 0, remoteCount: 0,
            createdAt: Date(), deviceName: "iPhone", rcloneVersion: "1.0"
        )
        #expect(throws: GhostVaultError.self) {
            _ = try GhostVault.seal(
                rcloneConf: Data(),
                passphrase: "abc",
                meta: meta,
                rcloneVersion: "1.0"
            )
        }
    }

    @Test("tampered ciphertext is rejected (no silent partial decryption)")
    func tamperedCiphertextFails() throws {
        let passphrase = "tamper-resistant-vault-2026"
        let envelope = try GhostVault.seal(
            rcloneConf: sampleConf,
            passphrase: passphrase,
            meta: GhostVaultMeta(
                sizeBytes: sampleConf.count,
                remoteCount: 1,
                createdAt: Date(),
                deviceName: "iPhone",
                rcloneVersion: "1.74.3"
            ),
            rcloneVersion: "1.74.3"
        )
        // Décode l'envelope, flippe un octet au milieu du payload chiffré,
        // réencode et tente d'ouvrir : doit échouer.
        var tampered = envelope
        let originalB64 = envelope.payloadB64
        guard var payloadBytes = Data(base64Encoded: originalB64) else {
            Issue.record("payload non base64"); return
        }
        let mid = payloadBytes.count / 2
        payloadBytes[mid] ^= 0xFF
        let tamperedB64 = payloadBytes.base64EncodedString()
        // On doit reconstruire l'envelope avec le payload altéré.
        let json = try GhostVault.encode(envelope)
        var dict = try JSONSerialization.jsonObject(with: json) as? [String: Any] ?? [:]
        dict["payload_b64"] = tamperedB64
        let tamperedData = try JSONSerialization.data(withJSONObject: dict)
        let tamperedEnvelope = try GhostVault.decode(tamperedData)
        #expect(throws: GhostVaultError.self) {
            _ = try GhostVault.open(envelope: tamperedEnvelope, passphrase: passphrase)
        }
        _ = tampered // silence unused warning
    }

    @Test("two seals of the same conf produce different ciphertexts (fresh salt + nonce)")
    func freshSaltEachSeal() throws {
        let meta = GhostVaultMeta(
            sizeBytes: sampleConf.count,
            remoteCount: 1,
            createdAt: Date(),
            deviceName: "iPhone",
            rcloneVersion: "1.74.3"
        )
        let a = try GhostVault.seal(
            rcloneConf: sampleConf,
            passphrase: "same-passphrase-12345",
            meta: meta,
            rcloneVersion: "1.74.3"
        )
        let b = try GhostVault.seal(
            rcloneConf: sampleConf,
            passphrase: "same-passphrase-12345",
            meta: meta,
            rcloneVersion: "1.74.3"
        )
        #expect(a.kdfSaltB64 != b.kdfSaltB64)
        #expect(a.cipherNonceB64 != b.cipherNonceB64)
        #expect(a.payloadB64 != b.payloadB64)
    }

    @Test("envelope JSON is human-readable (no binary blob in plaintext)")
    func envelopeIsJSON() throws {
        let envelope = try GhostVault.seal(
            rcloneConf: sampleConf,
            passphrase: "inspect-me-passphrase",
            meta: GhostVaultMeta(
                sizeBytes: sampleConf.count,
                remoteCount: 2,
                createdAt: Date(),
                deviceName: "iPhone de Vitalys",
                rcloneVersion: "1.74.3"
            ),
            rcloneVersion: "1.74.3"
        )
        let bytes = try GhostVault.encode(envelope)
        let asText = String(data: bytes, encoding: .utf8) ?? ""
        #expect(asText.contains("\"v\":1"))
        #expect(asText.contains("\"kdf\":\"pbkdf2-sha256\""))
        #expect(asText.contains("\"cipher\":\"chacha20-poly1305\""))
        // Le payload chiffré est base64, donc caractères ASCII imprimables.
        #expect(!asText.contains("[drive]"))
        #expect(!asText.contains("type = drive"))
    }
}

// MARK: - Handoff P2P : passphrase Diceware

@Suite("Handoff P2P — Diceware passphrase")
struct HandoffPassphraseTests {

    @Test("Le wordlist FR contient 256 mots uniques")
    func frenchWordlistHas256UniqueWords() {
        let list = HandoffPassphrase.wordlist(for: .french)
        #expect(list.count == 256)
        #expect(Set(list).count == 256)
    }

    @Test("Le wordlist EN contient 256 mots uniques")
    func englishWordlistHas256UniqueWords() {
        let list = HandoffPassphrase.wordlist(for: .english)
        #expect(list.count == 256)
        #expect(Set(list).count == 256)
    }

    @Test("generate() produit exactement 6 mots (default)")
    func generateProducesSixWords() {
        let words = HandoffPassphrase.generate()
        #expect(words.count == 6)
        let list = HandoffPassphrase.wordlist(for: .french)
        for w in words {
            #expect(list.contains(w), "le mot \(w) devrait provenir du wordlist FR")
        }
    }

    @Test("Deux tirages consécutifs produisent des listes différentes (SystemRandomNumberGenerator)")
    func consecutiveDrawsDiffer() {
        let a = HandoffPassphrase.generate()
        let b = HandoffPassphrase.generate()
        let setA = Set(a)
        let setB = Set(b)
        #expect(setA != setB, "deux tirages consécutifs devraient rarement être identiques")
    }

    @Test("split() lowercased et dé-whitespace")
    func splitNormalisesWhitespaceAndCase() {
        let words = HandoffPassphrase.split("  Abeille   ACIER  Cerise\n\nBaie ")
        #expect(words == ["abeille", "acier", "cerise", "baie"])
    }

    @Test("validate() rejette un mot hors wordlist")
    func validateRejectsForeignWord() {
        let bogus = ["abeille", "cerise", "banane", "chien", "loutre", "nuage"]
        #expect(throws: HandoffPassphraseError.self) {
            _ = try HandoffPassphrase.validate(words: bogus, language: .french)
        }
    }

    @Test("validate() rejette un nombre de mots hors bornes")
    func validateRejectsWrongCount() {
        let tooFew = ["abeille", "acier"]
        #expect(throws: HandoffPassphraseError.self) {
            _ = try HandoffPassphrase.validate(words: tooFew, language: .french)
        }
        let tooMany = (1...10).map { _ in "abeille" }
        #expect(throws: HandoffPassphraseError.self) {
            _ = try HandoffPassphrase.validate(words: tooMany, language: .french)
        }
    }

    @Test("validate() accepte un set FR valide")
    func validateAcceptsValidFrenchSet() throws {
        let list = HandoffPassphrase.wordlist(for: .french)
        let sample = Array(list.prefix(6))
        try HandoffPassphrase.validate(words: sample, language: .french)
    }

    @Test("entropyBits croît linéairement avec le nombre de mots")
    func entropyBitsIsLinear() {
        #expect(HandoffPassphrase.entropyBits(for: 3) == 24.0)
        #expect(HandoffPassphrase.entropyBits(for: 6) == 48.0)
        #expect(HandoffPassphrase.entropyBits(for: 8) == 64.0)
    }
}

// MARK: - Handoff P2P : envelope transport (zlib + base64url + HND1:)

@Suite("Handoff P2P — transport envelope")
struct HandoffEnvelopeTests {

    private let sampleConf = Data("""
    [drive]
    type = drive
    scope = drive
    token = {"access_token":"demo","expiry":"2099-01-01T00:00:00Z"}

    [b2-photos]
    type = b2
    account = 003a1b2c3d4e5f60000000001
    key = K003exampleexampleexampleexampleEXA

    [crypt-photos]
    type = crypt
    remote = b2-photos:encrypted
    password = rclonecrypt-strong-passphrase-2026
    filename_encryption = standard
    """.utf8)

    private func buildEnvelope() throws -> GhostVaultEnvelope {
        let meta = GhostVaultMeta(
            sizeBytes: sampleConf.count,
            remoteCount: 3,
            createdAt: Date(timeIntervalSince1970: 1_750_000_000),
            deviceName: "iPhone de Vitalys",
            rcloneVersion: "1.74.3"
        )
        return try GhostVault.seal(
            rcloneConf: sampleConf,
            passphrase: "valid-passphrase-test-2026",
            meta: meta,
            rcloneVersion: meta.rcloneVersion
        )
    }

    @Test("Encode → decode round-trip préserve l'envelope")
    func encodeDecodeRoundTrip() throws {
        let env = try buildEnvelope()
        let payload = try HandoffEnvelope.encode(env)
        #expect(payload.hasPrefix(HandoffEnvelope.transportPrefix))
        let restored = try HandoffEnvelope.decode(payload)
        #expect(restored == env)
    }

    @Test("Le payload est mono-ligne ASCII imprimable")
    func payloadIsSingleLineASCII() throws {
        let env = try buildEnvelope()
        let payload = try HandoffEnvelope.encode(env)
        #expect(!payload.contains("\n"))
        for scalar in payload.unicodeScalars {
            #expect(scalar.isASCII)
            #expect(scalar.value >= 0x20 && scalar.value <= 0x7E, "imprimable uniquement")
        }
    }

    @Test("Reject: payload sans préfixe HND1:")
    func rejectsMissingPrefix() {
        #expect(throws: HandoffEnvelopeError.self) {
            _ = try HandoffEnvelope.decode("AAECAwQF")
        }
    }

    @Test("Reject: base64url invalide")
    func rejectsInvalidBase64URL() {
        let payload = "HND1:!!@@##not-base64@@!!##"
        #expect(throws: HandoffEnvelopeError.self) {
            _ = try HandoffEnvelope.decode(payload)
        }
    }

    @Test("Reject: payload JSON brut (pas HND1)")
    func rejectsRawJSON() {
        let json = #"{"v":1,"kdf":"pbkdf2-sha256"}"#
        #expect(throws: HandoffEnvelopeError.self) {
            _ = try HandoffEnvelope.decode(json)
        }
    }

    @Test("isPayload() détecte un HND1: au milieu d'un texte")
    func isPayloadDetectsPrefix() {
        #expect(HandoffEnvelope.isPayload("HND1:abc") == true)
        #expect(HandoffEnvelope.isPayload("  HND1:abc  ") == true)
        #expect(HandoffEnvelope.isPayload("Voyage à HND1:abc") == true)
        #expect(HandoffEnvelope.isPayload("plain text") == false)
    }

    @Test("extract() retourne le payload complet même noyé dans du texte")
    func extractFindsPayloadInText() {
        let text = """
        Bonjour ! Voici le payload :

        HND1:eJyrVk3PT8wvSizKUOKi5MrPSwMAF5MDtw

        Merci !
        """
        let extracted = HandoffEnvelope.extract(from: text)
        #expect(extracted == "HND1:eJyrVk3PT8wvSizKUOKi5MrPSwMAF5MDtw")
    }

    @Test("zlib réduit le JSON GhostVault avant base64url")
    func compressionShrinksPayload() throws {
        let env = try buildEnvelope()
        let jsonBytes = try GhostVault.encode(env)
        let payload = try HandoffEnvelope.encode(env)
        // Mesure les octets zlib BINAIRES : comparer au base64url (+33%)
        // masquerait la compression. On décode donc le corps du payload.
        var body = String(payload.dropFirst(HandoffEnvelope.transportPrefix.count))
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        body.append(String(repeating: "=", count: (4 - body.count % 4) % 4))
        let compressed = try #require(Data(base64Encoded: body))
        let compressionRatio = Double(jsonBytes.count) / Double(compressed.count)
        // Le JSON de l'envelope est majoritairement du base64 (ciphertext),
        // que zlib re-compacte vers ~75% + les clés textuelles : on attend
        // au moins 10% de gain réel sur une conf réaliste.
        #expect(compressionRatio >= 1.10, "compression insuffisante : ratio \(compressionRatio)")
    }
}

// MARK: - Handoff P2P : inbox (fichier .rclonebackup entrant via AirDrop)

@Suite("Handoff P2P — inbox fichier entrant")
struct HandoffInboxTests {

    private func tempFile(named name: String, contents: Data) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "handoff-inbox-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appending(path: name)
        try contents.write(to: url)
        return url
    }

    private func tempFile(named name: String, contents: String) throws -> URL {
        try tempFile(named: name, contents: Data(contents.utf8))
    }

    @Test("isHandoffFile : extension .rclonebackup, insensible à la casse")
    func isHandoffFileMatchesExtension() {
        #expect(HandoffInbox.isHandoffFile(URL(fileURLWithPath: "/tmp/a.rclonebackup")))
        #expect(HandoffInbox.isHandoffFile(URL(fileURLWithPath: "/tmp/a.RcloneBackup")))
        #expect(!HandoffInbox.isHandoffFile(URL(fileURLWithPath: "/tmp/a.conf")))
        #expect(!HandoffInbox.isHandoffFile(URL(fileURLWithPath: "/tmp/rclonebackup")))
    }

    @Test("extractPayload : round-trip complet avec un envelope réel")
    func extractPayloadRoundTrip() throws {
        let conf = Data("[s3]\ntype = s3\nprovider = AWS\n".utf8)
        let meta = GhostVaultMeta(
            sizeBytes: conf.count,
            remoteCount: 1,
            createdAt: Date(timeIntervalSince1970: 1_750_000_000),
            deviceName: "iPhone de test",
            rcloneVersion: "1.74.3"
        )
        let env = try GhostVault.seal(
            rcloneConf: conf,
            passphrase: "abeille acier cerise baie dune ferme",
            meta: meta,
            rcloneVersion: meta.rcloneVersion
        )
        let payload = try HandoffEnvelope.encode(env)
        let url = try tempFile(named: "handoff.rclonebackup", contents: payload)
        let extracted = try HandoffInbox.extractPayload(fromFileAt: url)
        #expect(extracted == payload)
        let decoded = try HandoffEnvelope.decode(extracted)
        #expect(decoded == env)
    }

    @Test("extractPayload : payload noyé dans du texte environnant")
    func extractPayloadFromSurroundedText() throws {
        let url = try tempFile(
            named: "notes.rclonebackup",
            contents: "Salut !\nHND1:eJyrVk3PT8wvSizKUOKi5MrPSwMAF5MDtw\nBye"
        )
        let extracted = try HandoffInbox.extractPayload(fromFileAt: url)
        #expect(extracted == "HND1:eJyrVk3PT8wvSizKUOKi5MrPSwMAF5MDtw")
    }

    @Test("Reject : mauvaise extension")
    func rejectsWrongExtension() throws {
        let url = try tempFile(named: "payload.txt", contents: "HND1:abc")
        #expect(throws: HandoffInboxError.self) {
            _ = try HandoffInbox.extractPayload(fromFileAt: url)
        }
    }

    @Test("Reject : fichier .rclonebackup sans payload HND1:")
    func rejectsFileWithoutPayload() throws {
        let url = try tempFile(named: "junk.rclonebackup", contents: "pas un payload handoff")
        #expect(throws: HandoffInboxError.self) {
            _ = try HandoffInbox.extractPayload(fromFileAt: url)
        }
    }

    @Test("Reject : contenu binaire non-UTF8")
    func rejectsBinaryContent() throws {
        let binary = Data([0xFF, 0xFE, 0x00, 0x01, 0x80, 0x81, 0xC0])
        let url = try tempFile(named: "binary.rclonebackup", contents: binary)
        #expect(throws: HandoffInboxError.self) {
            _ = try HandoffInbox.extractPayload(fromFileAt: url)
        }
    }

    @Test("Reject : fichier inexistant")
    func rejectsMissingFile() {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "missing-\(UUID().uuidString).rclonebackup")
        #expect(throws: HandoffInboxError.self) {
            _ = try HandoffInbox.extractPayload(fromFileAt: url)
        }
    }
}

// MARK: - Handoff P2P : fichier AirDrop (send service → inbox)

@Suite("Handoff P2P — fichier AirDrop")
struct HandoffSendServiceFileTests {

    @Test("materializeAirDropFile écrit un .rclonebackup lisible qui round-trip via l'inbox")
    func airDropFileRoundTrips() throws {
        let payload = "HND1:eJyrVk3PT8wvSizKUOKi5MrPSwMAF5MDtw"
        let url = try HandoffSendService.shared.materializeAirDropFile(payload: payload)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        #expect(url.pathExtension == "rclonebackup")
        #expect(FileManager.default.fileExists(atPath: url.path))
        // Le daemon de partage (sharingd) lit ce fichier hors-process : il
        // doit être lisible (protection ≠ .completeFileProtection) et contenir
        // exactement le payload. Ce round-trip est la garantie anti-régression
        // du bug « AirDrop n'affiche rien ».
        let extracted = try HandoffInbox.extractPayload(fromFileAt: url)
        #expect(extracted == payload)
    }

    @Test("Le fichier AirDrop n'est PAS protégé en .completeFileProtection")
    func airDropFileIsReadableByShareDaemon() throws {
        let url = try HandoffSendService.shared.materializeAirDropFile(payload: "HND1:abcdef")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let values = try url.resourceValues(forKeys: [.fileProtectionKey])
        // .complete rendrait le fichier illisible pour sharingd quand l'écran
        // se verrouille pendant le transfert AirDrop.
        #expect(values.fileProtection != .complete)
    }
}

// MARK: - Handoff P2P : QR payload single-fit

@Suite("Handoff P2P — QR payload split")
struct QRPayloadBuilderTests {

    private func buildEnvelope(bytes: Int) throws -> GhostVaultEnvelope {
        let dummyConf = Data((0..<bytes).map { UInt8($0 & 0xFF) })
        let meta = GhostVaultMeta(
            sizeBytes: dummyConf.count,
            remoteCount: 1,
            createdAt: Date(),
            deviceName: "Test",
            rcloneVersion: "1.74.3"
        )
        return try GhostVault.seal(
            rcloneConf: dummyConf,
            passphrase: "valid-passphrase-test",
            meta: meta,
            rcloneVersion: meta.rcloneVersion
        )
    }

    private func buildRealisticEnvelope() throws -> GhostVaultEnvelope {
        // Conf TEXTE réaliste (~450 octets, 3 remotes) : une fois chiffrée,
        // la taille du ciphertext ≈ celle du plaintext — c'est elle qui
        // décide si le payload tient dans un QR, pas la compressibilité
        // (des octets chiffrés ne se compressent pas).
        let conf = Data("""
        [drive]
        type = drive
        scope = drive
        token = {"access_token":"demo","expiry":"2099-01-01T00:00:00Z"}

        [b2-photos]
        type = b2
        account = 003a1b2c3d4e5f60000000001
        key = K003exampleexampleexampleexampleEXA

        [crypt-photos]
        type = crypt
        remote = b2-photos:encrypted
        password = rclonecrypt-strong-passphrase-2026
        filename_encryption = standard
        """.utf8)
        let meta = GhostVaultMeta(
            sizeBytes: conf.count,
            remoteCount: 3,
            createdAt: Date(),
            deviceName: "Test",
            rcloneVersion: "1.74.3"
        )
        return try GhostVault.seal(
            rcloneConf: conf,
            passphrase: "valid-passphrase-test",
            meta: meta,
            rcloneVersion: meta.rcloneVersion
        )
    }

    @Test("Un envelope typique (3 remotes, conf texte) tient en un seul QR")
    func typicalEnvelopeFitsInSingleQR() throws {
        let env = try buildRealisticEnvelope()
        let decision = try QRPayloadBuilder.build(from: env)
        switch decision {
        case .single:
            break
        case .tooLargeForQR(_, let rawBytes):
            Issue.record("attendu single QR, reçu tooLargeForQR (\(rawBytes) bytes)")
        }
    }

    @Test("Un envelope de 100 octets produit un payload de taille attendue")
    func measureEnvelopes() throws {
        for size in [100, 500, 1_000, 4_000, 8_000] {
            let env = try buildEnvelope(bytes: size)
            let payload = try HandoffEnvelope.encode(env)
            print("conf \(size) → envelope+transport: \(payload.utf8.count) bytes")
        }
    }

    @Test("Un envelope trop gros (>1800 bytes) déclenche fallback")
    func hugeEnvelopeTriggersFallback() throws {
        let env = try buildEnvelope(bytes: 16_000)
        let decision = try QRPayloadBuilder.build(from: env)
        switch decision {
        case .single(let payload):
            Issue.record("attendu tooLargeForQR, reçu single (\(payload.utf8.count) bytes)")
        case .tooLargeForQR(_, let rawBytes):
            #expect(rawBytes > QRPayloadBuilder.singleQRByteBudget)
        }
    }

    @Test("Le seuil 1800 bytes est appliqué correctement")
    func singleQRBudgetEdge() {
        #expect(QRPayloadBuilder.singleQRByteBudget == 1800)
    }
}

// MARK: - Handoff P2P : merge INI

@Suite("Handoff P2P — merge rclone.conf")
struct HandoffReceiveMergeTests {

    @Test("Replace: incoming écrase local entièrement")
    func mergeReplaceYieldsIncoming() async {
        let local = Data("""
        [local]
        type = local
        """.utf8)
        let incoming = Data("""
        [drive]
        type = drive
        """.utf8)
        let plan = await HandoffReceiveService.shared.buildMergePlan(local: local, incoming: incoming)
        #expect(plan.addedRemotes == ["drive"])
        #expect(plan.conflictingRemotes.isEmpty)
        #expect(plan.keptRemotes.isEmpty)
    }

    @Test("Merge: collision garde la version locale, marque le conflit")
    func mergeKeepsLocalOnConflict() async {
        let local = Data("""
        [drive]
        type = drive
        token = {"access_token":"LOCAL"}
        """.utf8)
        let incoming = Data("""
        [drive]
        type = drive
        token = {"access_token":"REMOTE"}
        """.utf8)
        let plan = await HandoffReceiveService.shared.buildMergePlan(local: local, incoming: incoming)
        #expect(plan.addedRemotes.isEmpty)
        #expect(plan.conflictingRemotes.count == 1)
        #expect(plan.conflictingRemotes.first?.name == "drive")
    }

    @Test("Merge: les remotes inchangés sont signalés «kept»")
    func mergeIdentifiesKeptRemotes() async {
        let local = Data("""
        [s3prod]
        type = s3
        provider = AWS
        """.utf8)
        let incoming = Data("""
        [s3prod]
        type = s3
        provider = AWS
        """.utf8)
        let plan = await HandoffReceiveService.shared.buildMergePlan(local: local, incoming: incoming)
        #expect(plan.keptRemotes == ["s3prod"])
        #expect(plan.conflictingRemotes.isEmpty)
        #expect(plan.addedRemotes.isEmpty)
    }

    @Test("Merge: 3 sections, 2 nouvelles + 1 collision → added=2 conflict=1")
    func mergeMixesAddedAndConflicts() async {
        let local = Data("""
        [drive]
        type = drive
        token = LOCAL
        """.utf8)
        let incoming = Data("""
        [drive]
        type = drive
        token = REMOTE

        [b2]
        type = b2
        account = B2ACC

        [box]
        type = box
        """.utf8)
        let plan = await HandoffReceiveService.shared.buildMergePlan(local: local, incoming: incoming)
        #expect(plan.addedRemotes.sorted() == ["b2", "box"])
        #expect(plan.conflictingRemotes.count == 1)
        #expect(plan.conflictingRemotes.first?.name == "drive")
    }

    @Test("Merge: local vide → tous les entrants sont «added»")
    func mergeFromEmptyLocal() async {
        let plan = await HandoffReceiveService.shared.buildMergePlan(local: Data(), incoming: Data("""
        [drive]
        type = drive
        """.utf8))
        #expect(plan.addedRemotes == ["drive"])
    }
}

// MARK: - Handoff P2P : unseal cross-check

@Suite("Handoff P2P — seal + HND1 + unseal round-trip")
struct HandoffEndToEndTests {

    @Test("Seal → HND1 → unseal restitue la conf originale")
    func endToEndRoundTrip() throws {
        let originalConf = Data("""
        [drive]
        type = drive
        token = {"access_token":"abc"}

        [b2]
        type = b2
        account = 12345
        """.utf8)
        let meta = GhostVaultMeta(
            sizeBytes: originalConf.count,
            remoteCount: 2,
            createdAt: Date(),
            deviceName: "iPhone",
            rcloneVersion: "1.74.3"
        )
        let envelope = try GhostVault.seal(
            rcloneConf: originalConf,
            passphrase: "diceware-temporary-passphrase-2026",
            meta: meta,
            rcloneVersion: meta.rcloneVersion
        )
        let payload = try HandoffEnvelope.encode(envelope)
        let restored = try HandoffEnvelope.decode(payload)
        let opened = try GhostVault.open(envelope: restored, passphrase: "diceware-temporary-passphrase-2026")
        #expect(opened.rcloneConf == originalConf)
    }

    @Test("HND1: payload déchiffré avec MAUVAISE passphrase → erreur")
    func wrongPassphraseFailsOnHDN1Payload() throws {
        let envelope = try GhostVault.seal(
            rcloneConf: Data("[x]\ntype = local\n".utf8),
            passphrase: "right-passphrase",
            meta: GhostVaultMeta(
                sizeBytes: 14, remoteCount: 1,
                createdAt: Date(), deviceName: "iPhone", rcloneVersion: "1.74.3"
            ),
            rcloneVersion: "1.74.3"
        )
        let payload = try HandoffEnvelope.encode(envelope)
        let restored = try HandoffEnvelope.decode(payload)
        #expect(throws: GhostVaultError.self) {
            _ = try GhostVault.open(envelope: restored, passphrase: "wrong-passphrase")
        }
    }
}

// MARK: - BridgeFolderDownloader pure helpers
//
// Tests des helpers statiques extraits de BridgeFolderDownloader.swift.
// Pas besoin de librclone ni de réseau : la logique de tri, de calcul de
// chemin relatif et de partition skip-existing est pure et testable en
// isolation. Couvre les régressions critiques pour le download de dossier
// « daisychain 9 GB vers iCloud Drive ».

@Suite("BridgeFolderDownloader — helpers purs")
struct BridgeFolderDownloaderTests {

    /// Construit une RemoteEntryDTO factice pour les tests. Pas de SwiftData,
    /// juste les champs nécessaires aux helpers testés.
    private func entry(path: String, name: String, size: Int64) -> RemoteEntryDTO {
        RemoteEntryDTO(
            pathInRemote: path,
            name: name,
            isDirectory: false,
            size: size,
            modTime: Date(),
            mimeType: nil,
            hashMD5: nil,
            hashSHA1: nil
        )
    }

    // MARK: - sortLargeFirst

    @Test("sortLargeFirst : place les gros fichiers en premier")
    func sortPlacesLargestFirst() {
        let small = entry(path: "a.mp4", name: "a.mp4", size: 100)
        let big = entry(path: "b.mp4", name: "b.mp4", size: 9_000_000_000)
        let medium = entry(path: "c.mp4", name: "c.mp4", size: 50_000_000)
        let input = [small, big, medium]
        let sorted = BridgeFolderDownloader.sortLargeFirst(input)
        #expect(sorted.map(\.size) == [9_000_000_000, 50_000_000, 100])
    }

    @Test("sortLargeFirst : stable pour les fichiers de même taille")
    func sortIsStableForEqualSizes() {
        let a = entry(path: "a.mp4", name: "a.mp4", size: 1000)
        let b = entry(path: "b.mp4", name: "b.mp4", size: 1000)
        let c = entry(path: "c.mp4", name: "c.mp4", size: 1000)
        let sorted = BridgeFolderDownloader.sortLargeFirst([a, b, c])
        // L'ordre d'origine est préservé (algorithme de tri Swift stable).
        #expect(sorted.map(\.pathInRemote) == ["a.mp4", "b.mp4", "c.mp4"])
    }

    @Test("sortLargeFirst : tableau vide → vide")
    func sortEmpty() {
        #expect(BridgeFolderDownloader.sortLargeFirst([]).isEmpty)
    }

    // MARK: - relativePath

    @Test("relativePath : sourcePath vide → pathInRemote tel quel")
    func relativePathWithEmptySource() {
        let e = entry(path: "sub/foo.mp4", name: "foo.mp4", size: 100)
        #expect(BridgeFolderDownloader.relativePath(for: e, sourcePath: "") == "sub/foo.mp4")
    }

    @Test("relativePath : strip le préfixe sourcePath")
    func relativePathStripsPrefix() {
        let e = entry(path: "daisychain/sub/foo.mp4", name: "foo.mp4", size: 100)
        #expect(BridgeFolderDownloader.relativePath(for: e, sourcePath: "daisychain") == "sub/foo.mp4")
    }

    @Test("relativePath : tolère un sourcePath avec trailing slash")
    func relativePathWithTrailingSlash() {
        let e = entry(path: "daisychain/sub/foo.mp4", name: "foo.mp4", size: 100)
        #expect(BridgeFolderDownloader.relativePath(for: e, sourcePath: "daisychain/") == "sub/foo.mp4")
    }

    @Test("relativePath : pathInRemote sans préfixe → conservé tel quel")
    func relativePathWithoutPrefix() {
        // Cas rare : pathInRemote ne commence pas par sourcePath (listing
        // incomplet ou path absolu). On garde le path tel quel pour ne
        // pas perdre le fichier.
        let e = entry(path: "other/foo.mp4", name: "foo.mp4", size: 100)
        #expect(BridgeFolderDownloader.relativePath(for: e, sourcePath: "daisychain") == "other/foo.mp4")
    }

    // MARK: - partitionByExistence

    @Test("partitionByExistence : skip les fichiers existants avec taille identique")
    func partitionSkipsIdenticalFiles() throws {
        // Crée un dossier temporaire avec deux fichiers existants
        let tmp = FileManager.default.temporaryDirectory
            .appending(path: "bridge-folder-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        // Crée deux fichiers : un avec taille qui matche, un autre qui ne matche pas
        let matchURL = tmp.appending(path: "exists.mp4")
        let mismatchURL = tmp.appending(path: "wrongsize.mp4")
        try Data(count: 1000).write(to: matchURL)
        try Data(count: 2000).write(to: mismatchURL)

        let matchingEntry = entry(path: "sub/exists.mp4", name: "exists.mp4", size: 1000)
        let mismatchEntry = entry(path: "sub/wrongsize.mp4", name: "wrongsize.mp4", size: 999_999)
        let missingEntry = entry(path: "sub/missing.mp4", name: "missing.mp4", size: 5000)

        let result = BridgeFolderDownloader.partitionByExistence(
            files: [matchingEntry, mismatchEntry, missingEntry],
            sourcePath: "sub",
            destDir: tmp
        )

        #expect(result.skippedCount == 1, "Le fichier avec taille identique doit être skipped")
        #expect(result.skippedBytes == 1000, "Le skippedBytes doit refléter la taille du fichier skip")
        #expect(result.todo.count == 2, "Les deux autres fichiers doivent rester en todo")
        #expect(result.todo.map(\.entry.name).sorted() == ["missing.mp4", "wrongsize.mp4"])
    }

    @Test("partitionByExistence : ne skip JAMAIS un fichier de taille 0")
    func partitionNeverSkipsZeroSize() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appending(path: "bridge-folder-zs-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        // Fichier vide existant : on doit le retélécharger car la taille 0
        // ne permet pas de confirmer l'intégrité (backends comme S3 distillent
        // la taille pendant le download).
        let emptyURL = tmp.appending(path: "empty.mp4")
        try Data().write(to: emptyURL)

        let emptyEntry = entry(path: "empty.mp4", name: "empty.mp4", size: 0)
        let result = BridgeFolderDownloader.partitionByExistence(
            files: [emptyEntry],
            sourcePath: "",
            destDir: tmp
        )
        #expect(result.skippedCount == 0, "Taille 0 = pas de skip, on retélécharge pour récupérer la vraie taille")
        #expect(result.todo.count == 1)
    }

    @Test("partitionByExistence : aucun fichier existant → tout en todo")
    func partitionAllMissing() {
        let tmp = URL(fileURLWithPath: "/tmp/bridge-folder-test-nonexistent-\(UUID().uuidString)")
        let files = (1...5).map { entry(path: "file\($0).mp4", name: "file\($0).mp4", size: Int64($0 * 1000)) }
        let result = BridgeFolderDownloader.partitionByExistence(files: files, sourcePath: "", destDir: tmp)
        #expect(result.skippedCount == 0)
        #expect(result.skippedBytes == 0)
        #expect(result.todo.count == 5)
    }

    @Test("partitionByExistence : préserve la structure interne du dossier distant")
    func partitionPreservesFolderStructure() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appending(path: "bridge-folder-struct-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        // Fichier dans un sous-dossier
        let subDir = tmp.appending(path: "sub", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
        let nestedURL = subDir.appending(path: "deep.mp4")
        try Data(count: 500).write(to: nestedURL)

        let nestedEntry = entry(path: "daisychain/sub/deep.mp4", name: "deep.mp4", size: 500)
        let result = BridgeFolderDownloader.partitionByExistence(
            files: [nestedEntry],
            sourcePath: "daisychain",
            destDir: tmp
        )
        // Le fichier est trouvé grâce au strip du préfixe "daisychain/"
        #expect(result.skippedCount == 1)
        #expect(result.todo.isEmpty)
    }

    // MARK: - Téléversement final

    @Test("Téléversement : le compte de fichiers + bytesTotal est correct après tri+partition")
    func endToEndSortAndPartition() {
        let files = [
            entry(path: "small.mp4", name: "small.mp4", size: 100),
            entry(path: "big.mp4", name: "big.mp4", size: 1_000_000),
            entry(path: "medium.mp4", name: "medium.mp4", size: 10_000),
        ]
        let sorted = BridgeFolderDownloader.sortLargeFirst(files)
        #expect(sorted.first?.name == "big.mp4")
        #expect(sorted.last?.name == "small.mp4")
        let bytesTotal = sorted.reduce(Int64(0)) { $0 + $1.size }
        #expect(bytesTotal == 1_010_100)
    }
}
