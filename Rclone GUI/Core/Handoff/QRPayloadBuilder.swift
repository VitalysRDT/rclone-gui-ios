//
//  QRPayloadBuilder.swift
//  Rclone GUI — Core/Handoff
//
//  Decides whether a Handoff transport payload fits inside a single
//  high-density QR code, or whether it must be routed to an alternative
//  transport (AirDrop, file picker, pasteboard).
//
//  Conservative capacity model: a QR v40/L at error-correction M holds
//  ≈ 1,852 bytes in alphanumeric mode. We round down to 1,800 to leave
//  a safety margin against scanner-app quirks (low-light camera,
//  slight angle, screen glare). For binary payloads we conservatively
//  model 1,533 bytes (QR v40/M byte mode, the worst case).
//
//  v1 deliberately does NOT chunk into animated QR frames — too easy to
//  ship a brittle UX. v2 may add it if single-QR proves too limiting
//  in real-world configs.
//

import Foundation

public enum QRPayloadBuilder {

    /// Single-QR payload ceiling, conservative.
    public nonisolated static let singleQRByteBudget: Int = 1800

    /// Decision a Handoff sender must take based on `estimatedPayloadBytes`.
    public enum QRDecision: Equatable, Sendable {
        /// Fits in a single QR code.
        case single(payload: String)
        /// Too large for one QR — caller must use AirDrop / file / clipboard.
        case tooLargeForQR(payload: String, rawBytes: Int)
    }

    public nonisolated static func build(from envelope: GhostVaultEnvelope) throws -> QRDecision {
        let encoded = try HandoffEnvelope.encode(envelope)
        return build(fromEncodedPayload: encoded)
    }

    public nonisolated static func build(fromEncodedPayload payload: String) -> QRDecision {
        let byteCount = payload.utf8.count
        if byteCount <= singleQRByteBudget {
            return .single(payload: payload)
        }
        return .tooLargeForQR(payload: payload, rawBytes: byteCount)
    }

    public nonisolated static func formattedByteCount(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}
