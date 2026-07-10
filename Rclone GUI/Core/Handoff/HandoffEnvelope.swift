//
//  HandoffEnvelope.swift
//  Rclone GUI — Core/Handoff
//
//  Transport encoding for a Handoff P2P GhostVault envelope. Wraps the
//  GhostVault v1 envelope in a single line of text suitable for a QR
//  code, an AirDrop preview, or a pasteboard round-trip:
//
//      HND1:<base64url(zlib(JSON(envelope)))>
//
//  The `HND1:` magic prefix (4 ASCII chars) lets the receiver
//  distinguish a Handoff payload from any random text payload, a raw
//  `.rclonebackup` JSON, or a URL. The format is versioned so we can
//  evolve it (e.g. add animated-QR chunking, Argon2id) by bumping the
//  prefix without breaking v1 readers.
//
//  Compression: the envelope JSON is small (~1 KB on a single config
//  with a handful of remotes, 2-3 KB with OAuth tokens). zlib takes it
//  down to typically 30-50% of the original size, which is what lets a
//  realistic Handoff payload fit inside a single high-density QR code
//  (v40/L ≈ 1.8 KB of M-corrected alphanumeric). Anything bigger is
//  rejected by the caller and routed to AirDrop / file / clipboard.
//
//  Security: the prefix is not authenticated — it only deserializes the
//  envelope. Authentication comes from the ChaCha20-Poly1305 tag inside
//  the GhostVault envelope itself, which is verified when the
//  passphrase is provided. A bogus `HND1:` payload will fail JSON
//  decoding before reaching cryptographic code.
//

import Foundation
import Compression

public enum HandoffEnvelopeError: Error, LocalizedError, Sendable {
    case invalidEncoding(String)
    case unknownVersion(String)
    case compressionFailed(Int32)
    case decompressionFailed(Int32)
    case decodingFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidEncoding(let why):
            return String(localized: "Payload Handoff invalide : \(why).")
        case .unknownVersion(let prefix):
            return String(localized: "Version Handoff inconnue : « \(prefix) ». Mets à jour l’app.")
        case .compressionFailed(let code):
            return String(localized: "Compression impossible (code \(code)).")
        case .decompressionFailed(let code):
            return String(localized: "Décompression impossible (code \(code)).")
        case .decodingFailed(let why):
            return String(localized: "Payload Handoff corrompu : \(why).")
        }
    }
}

public enum HandoffEnvelope {

    public nonisolated static let transportPrefix: String = "HND1:"

    public nonisolated static let version: Int = 1

    /// Encode a `GhostVaultEnvelope` as the transport-friendly payload
    /// `<HND1:><base64url(zlib(json))>`. The result is a single ASCII
    /// string, safe to embed in a QR code or paste into a text field.
    public nonisolated static func encode(_ envelope: GhostVaultEnvelope) throws -> String {
        let json: Data
        do {
            json = try GhostVault.encode(envelope)
        } catch {
            throw HandoffEnvelopeError.decodingFailed("encodage GhostVault impossible")
        }
        let compressed = try Self.compress(json)
        let encoded = compressed.base64URLEncodedString()
        return transportPrefix + encoded
    }

    /// Decode a transport payload back to a `GhostVaultEnvelope`.
    /// Throws `HandoffEnvelopeError.unknownVersion` if the prefix isn't
    /// `HND1:` (this differentiates the format from a raw
    /// `.rclonebackup` JSON, an arbitrary base64url string, etc.).
    public nonisolated static func decode(_ payload: String) throws -> GhostVaultEnvelope {
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(transportPrefix) else {
            if trimmed.hasPrefix("{") {
                throw HandoffEnvelopeError.invalidEncoding(
                    "reçu un JSON brut, pas un payload HND1 ; utilise plutôt « Restaurer un vault »"
                )
            }
            throw HandoffEnvelopeError.unknownVersion(
                String(trimmed.prefix(8))
            )
        }
        let body = String(trimmed.dropFirst(transportPrefix.count))
        guard let compressed = Data(base64URLEncoded: body) else {
            throw HandoffEnvelopeError.invalidEncoding("base64url invalide")
        }
        let json = try Self.decompress(compressed)
        do {
            return try GhostVault.decode(json)
        } catch {
            throw HandoffEnvelopeError.decodingFailed("JSON GhostVault invalide")
        }
    }

    /// Quick check: is this string (possibly embedded in surrounding
    /// text) a `HND1:` payload?
    public nonisolated static func isPayload(_ s: String) -> Bool {
        extract(from: s) != nil
    }

    /// Best-effort extraction of a `HND1:` payload from a larger text
    /// blob (e.g. a clipboard containing a sentence + a payload). The
    /// prefix can appear anywhere, even mid-line — the payload is a
    /// single ASCII token, so it runs until the first whitespace.
    /// Returns `nil` if no payload is found.
    public nonisolated static func extract(from text: String) -> String? {
        guard let range = text.range(of: transportPrefix) else { return nil }
        let candidate = text[range.lowerBound...].prefix(while: { !$0.isWhitespace })
        guard candidate.count > transportPrefix.count else { return nil }
        return String(candidate)
    }

    public nonisolated static func estimatedPayloadBytes(envelope: GhostVaultEnvelope) -> Int {
        guard let encoded = try? Self.encode(envelope) else { return 0 }
        return encoded.utf8.count
    }
}

// MARK: - zlib wrappers via Compression framework

nonisolated private extension HandoffEnvelope {

    static func compress(_ data: Data) throws -> Data {
        let dstCapacity = max(data.count, 64) * 2 + 64
        let dst = UnsafeMutablePointer<UInt8>.allocate(capacity: dstCapacity)
        defer { dst.deallocate() }
        let srcCount = data.count
        let written: Int = data.withUnsafeBytes { src -> Int in
            guard let srcBase = src.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return 0
            }
            return Int(compression_encode_buffer(
                dst, dstCapacity,
                srcBase, srcCount,
                nil,
                COMPRESSION_ZLIB
            ))
        }
        guard written > 0 else {
            throw HandoffEnvelopeError.compressionFailed(Int32(written))
        }
        return Data(bytes: dst, count: written)
    }

    static func decompress(_ data: Data) throws -> Data {
        let dstCapacity = max(data.count * 8, 64 * 1024)
        let dst = UnsafeMutablePointer<UInt8>.allocate(capacity: dstCapacity)
        defer { dst.deallocate() }
        let srcCount = data.count
        let written: Int = data.withUnsafeBytes { src -> Int in
            guard let srcBase = src.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return 0
            }
            return Int(compression_decode_buffer(
                dst, dstCapacity,
                srcBase, srcCount,
                nil,
                COMPRESSION_ZLIB
            ))
        }
        guard written > 0 else {
            throw HandoffEnvelopeError.decompressionFailed(Int32(written))
        }
        return Data(bytes: dst, count: written)
    }
}

// MARK: - base64url helpers

nonisolated private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    init?(base64URLEncoded input: String) {
        var s = input
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = (4 - s.count % 4) % 4
        s.append(String(repeating: "=", count: padding))
        guard let data = Data(base64Encoded: s) else { return nil }
        self = data
    }
}
