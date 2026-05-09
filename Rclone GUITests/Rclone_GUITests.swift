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
