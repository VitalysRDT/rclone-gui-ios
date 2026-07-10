//
//  QRCodeImageRenderer.swift
//  Rclone GUI — Core/QR
//
//  Thin wrapper around CoreImage's `qrCodeGenerator()` CIFilter to
//  produce a high-resolution `UIImage` (or `NSImage` on macOS) suitable
//  for the Handoff P2P display. Outputs a clean black-on-white, no
//  quiet zone (caller adds its own frame).
//
//  No third-party dependency: Apple ships the QR generator natively
//  on iOS 13+, macOS 10.15+ — works on every supported target of
//  Rclone GUI.
//

#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif
import CoreImage
import CoreImage.CIFilterBuiltins

public enum QRCodeImageRenderer {

    public enum CorrectionLevel: String, Sendable {
        case low      // L  ~7% recovery
        case medium   // M  ~15% recovery (default — most scannable on phones)
        case quartile // Q  ~25% recovery
        case high     // H  ~30% recovery
    }

#if canImport(UIKit)
    public static func render(
        payload: String,
        targetDimension: CGFloat,
        correction: CorrectionLevel = .medium
    ) -> UIImage? {
        guard let qr = makeCIImage(payload: payload, correction: correction) else { return nil }
        let extent = qr.extent
        let scale = max(targetDimension / max(extent.width, 1), 1)
        let scaled = qr.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let context = CIContext(options: nil)
        guard let cg = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
#else
    public static func render(
        payload: String,
        targetDimension: CGFloat,
        correction: CorrectionLevel = .medium
    ) -> NSImage? {
        guard let qr = makeCIImage(payload: payload, correction: correction) else { return nil }
        let extent = qr.extent
        let scale = max(targetDimension / max(extent.width, 1), 1)
        let scaled = qr.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let context = CIContext(options: nil)
        guard let cg = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        let size = NSSize(width: cg.width, height: cg.height)
        return NSImage(cgImage: cg, size: size)
    }
#endif

    private static func makeCIImage(payload: String, correction: CorrectionLevel) -> CIImage? {
        guard let data = payload.data(using: .utf8) else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = data
        filter.correctionLevel = correction.rawValue
        return filter.outputImage
    }
}
