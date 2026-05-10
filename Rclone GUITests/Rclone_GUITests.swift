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

// MARK: - ChaChaPoly round-trip (mirrors ConfigStore seal/open primitive)

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
                creationDate: Date(timeIntervalSince1970: TimeInterval(index))
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
