//
//  RemoteLensImageTests.swift
//  Rclone GUITests
//
//  Round-trip EXIF réel via ImageIO, sans réseau ni fichier : on génère un
//  JPEG en mémoire portant un dictionnaire Exif/TIFF/GPS, puis on vérifie que
//  RemoteLensService.extractMetadata / decodeImage le relisent correctement.
//

import Testing
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import Rclone_GUI

private func makeTestJPEG(width: Int = 64, height: Int = 48,
                         properties: [CFString: Any]) -> Data? {
    let space = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8,
        bytesPerRow: 0, space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }
    ctx.setFillColor(CGColor(red: 0.2, green: 0.45, blue: 0.7, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    guard let image = ctx.makeImage() else { return nil }

    let out = NSMutableData()
    guard let dest = CGImageDestinationCreateWithData(
        out as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil
    ) else { return nil }
    CGImageDestinationAddImage(dest, image, properties as CFDictionary)
    guard CGImageDestinationFinalize(dest) else { return nil }
    return out as Data
}

private let richExif: [CFString: Any] = [
    kCGImagePropertyExifDictionary: [
        kCGImagePropertyExifFNumber: 2.8,
        kCGImagePropertyExifExposureTime: 0.004,          // 1/250 s
        kCGImagePropertyExifISOSpeedRatings: [100],
        kCGImagePropertyExifFocalLength: 50.0,
        kCGImagePropertyExifDateTimeOriginal: "2026:07:11 14:30:00",
        kCGImagePropertyExifLensModel: "Test 50mm f/1.8",
    ] as [CFString: Any],
    kCGImagePropertyTIFFDictionary: [
        kCGImagePropertyTIFFMake: "TestCam",
        kCGImagePropertyTIFFModel: "X100",
    ] as [CFString: Any],
    kCGImagePropertyGPSDictionary: [
        kCGImagePropertyGPSLatitude: 48.8566,
        kCGImagePropertyGPSLatitudeRef: "N",
        kCGImagePropertyGPSLongitude: 2.3522,
        kCGImagePropertyGPSLongitudeRef: "W",       // W → longitude négative
    ] as [CFString: Any],
]

@Suite("RemoteLensService — extraction EXIF (round-trip ImageIO)")
struct RemoteLensImageTests {

    @Test("extractMetadata relit dimensions, appareil, expo/ISO/focale/ouverture")
    func extractCoreFields() throws {
        let data = try #require(makeTestJPEG(properties: richExif))
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let meta = try #require(RemoteLensService.extractMetadata(from: source))

        #expect(meta.pixelWidth == 64)
        #expect(meta.pixelHeight == 48)
        #expect(meta.cameraMake == "TestCam")
        #expect(meta.cameraModel == "X100")
        #expect(meta.fNumber == "f/2.8")
        #expect(meta.iso == "ISO 100")
        #expect(meta.focalLength == "50 mm")
        #expect(meta.exposure == "1/250 s")
        #expect(meta.lensModel == "Test 50mm f/1.8")
    }

    @Test("extractMetadata applique le signe hémisphère au GPS")
    func extractGPS() throws {
        let data = try #require(makeTestJPEG(properties: richExif))
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let meta = try #require(RemoteLensService.extractMetadata(from: source))

        let lat = try #require(meta.latitude)
        let lon = try #require(meta.longitude)
        #expect(abs(lat - 48.8566) < 0.001)
        #expect(lon < 0)                          // réf « W » → négatif
        #expect(abs(lon + 2.3522) < 0.001)
    }

    @Test("extractMetadata renvoie nil quand aucune métadonnée exploitable")
    func extractEmpty() throws {
        // JPEG minimal SANS dictionnaire EXIF : ImageIO expose quand même
        // les dimensions → meta non nil, mais pas d'EXIF caméra.
        let data = try #require(makeTestJPEG(properties: [:]))
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let meta = RemoteLensService.extractMetadata(from: source)
        // Dimensions toujours présentes → meta non nil, champs caméra nil.
        #expect(meta?.pixelWidth == 64)
        #expect(meta?.fNumber == nil)
        #expect(meta?.cameraMake == nil)
    }

    @Test("decodeImage produit une vignette non nulle + métadonnées")
    func decodeProducesThumbnailAndMeta() throws {
        let data = try #require(makeTestJPEG(width: 800, height: 600, properties: richExif))
        let decoded = try #require(RemoteLensService.decodeImage(data))
        let thumb = try #require(decoded.thumbnail)
        // Downsamplée à 400 px max (ThumbnailService.maxPixel).
        #expect(thumb.image.width <= 400)
        #expect(thumb.image.height <= 400)
        #expect(decoded.meta?.fNumber == "f/2.8")
    }

    @Test("decodeImage renvoie nil sur des octets non-image")
    func decodeGarbage() {
        let junk = Data([0x00, 0x01, 0x02, 0x03, 0xFF, 0xFE])
        #expect(RemoteLensService.decodeImage(junk) == nil)
    }
}
