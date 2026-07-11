//
//  RemoteLensCoreTests.swift
//  Rclone GUITests
//
//  Tests unitaires du socle « Remote Lens » (PR1) : détection PDF/lens
//  (MediaFormat), décisions de stratégie + formatage EXIF (RemoteLensPlan),
//  et lecture de plage sur source mémoire (RangeByteSource). Zéro réseau.
//

import Testing
import Foundation
@testable import Rclone_GUI

@Suite("MediaFormat — PDF & lens")
struct MediaFormatLensTests {

    @Test("isPDF reconnaît .pdf quelle que soit la casse, pas les autres")
    func isPDF() {
        #expect(MediaFormat.isPDF("rapport.pdf"))
        #expect(MediaFormat.isPDF("RAPPORT.PDF"))
        #expect(MediaFormat.isPDF("dossier/sous/a.Pdf"))
        #expect(!MediaFormat.isPDF("photo.png"))
        #expect(!MediaFormat.isPDF("archive.zip"))
        #expect(!MediaFormat.isPDF("sans-extension"))
    }

    @Test("hasLens = images + PDF, pas vidéo/audio/autre")
    func hasLens() {
        #expect(MediaFormat.hasLens("photo.jpg"))
        #expect(MediaFormat.hasLens("raw.dng"))
        #expect(MediaFormat.hasLens("scan.pdf"))
        #expect(!MediaFormat.hasLens("film.mp4"))
        #expect(!MediaFormat.hasLens("son.mp3"))
        #expect(!MediaFormat.hasLens("archive.zip"))
    }
}

@Suite("RemoteLensPlan — stratégie & formatage")
struct RemoteLensPlanTests {

    @Test("imageStrategy : skip au-delà du plafond, inline si petit, sinon range de tête")
    func imageStrategy() {
        #expect(RemoteLensPlan.imageStrategy(size: 200 * 1024 * 1024) == .skip)
        #expect(RemoteLensPlan.imageStrategy(size: 100 * 1024) == .fullBounded)      // 100 Ko
        #expect(RemoteLensPlan.imageStrategy(size: 5 * 1024 * 1024)
                == .headRange(RemoteLensPlan.imageHeadWindow))                       // 5 Mo
        // Taille inconnue → on tente la fenêtre de tête.
        #expect(RemoteLensPlan.imageStrategy(size: 0)
                == .headRange(RemoteLensPlan.imageHeadWindow))
    }

    @Test("imageStrategy : bornes exactes autour des seuils")
    func imageStrategyBoundaries() {
        #expect(RemoteLensPlan.imageStrategy(size: RemoteLensPlan.imageInlineCap) == .fullBounded)
        #expect(RemoteLensPlan.imageStrategy(size: RemoteLensPlan.imageInlineCap + 1)
                == .headRange(RemoteLensPlan.imageHeadWindow))
        #expect(RemoteLensPlan.imageStrategy(size: RemoteLensPlan.imageFullCap)
                == .headRange(RemoteLensPlan.imageHeadWindow))
        #expect(RemoteLensPlan.imageStrategy(size: RemoteLensPlan.imageFullCap + 1) == .skip)
    }

    @Test("pdfStrategy : toujours accès aléatoire")
    func pdfStrategy() {
        #expect(RemoteLensPlan.pdfStrategy(size: 1_000) == .randomAccess)
        #expect(RemoteLensPlan.pdfStrategy(size: 500 * 1024 * 1024) == .randomAccess)
    }

    @Test("clampedRange : borne à EOF, refuse au-delà de la taille")
    func clampedRange() {
        // Fenêtre entièrement dans le fichier.
        #expect(RemoteLensPlan.clampedRange(start: 0, window: 100, totalSize: 1_000) == 0...99)
        // Fenêtre qui dépasse EOF → bornée au dernier octet.
        #expect(RemoteLensPlan.clampedRange(start: 950, window: 100, totalSize: 1_000) == 950...999)
        // start == taille → hors fichier → nil.
        #expect(RemoteLensPlan.clampedRange(start: 1_000, window: 10, totalSize: 1_000) == nil)
        // Taille inconnue → on fait confiance à la fenêtre.
        #expect(RemoteLensPlan.clampedRange(start: 0, window: 512, totalSize: 0) == 0...511)
        // Paramètres invalides.
        #expect(RemoteLensPlan.clampedRange(start: -1, window: 10, totalSize: 100) == nil)
        #expect(RemoteLensPlan.clampedRange(start: 0, window: 0, totalSize: 100) == nil)
    }

    @Test("formatExposureTime : fractions sous 1 s, secondes au-dessus")
    func exposureTime() {
        #expect(RemoteLensPlan.formatExposureTime(0.004) == "1/250 s")
        #expect(RemoteLensPlan.formatExposureTime(0.5) == "1/2 s")
        #expect(RemoteLensPlan.formatExposureTime(2.0) == "2 s")
        #expect(RemoteLensPlan.formatExposureTime(0) == "—")
    }

    @Test("formatFNumber / focale / ISO")
    func numericFormats() {
        #expect(RemoteLensPlan.formatFNumber(2.8) == "f/2.8")
        #expect(RemoteLensPlan.formatFNumber(8.0) == "f/8")
        #expect(RemoteLensPlan.formatFocalLength(50) == "50 mm")
        #expect(RemoteLensPlan.formatFocalLength(35.4) == "35 mm")
        #expect(RemoteLensPlan.formatISO(100) == "ISO 100")
        #expect(RemoteLensPlan.formatISO(0) == "—")
    }

    @Test("gpsDecimal : réfs S/W négatives, N/E positives")
    func gps() {
        #expect(RemoteLensPlan.gpsDecimal(48.8566, ref: "N") == 48.8566)
        #expect(RemoteLensPlan.gpsDecimal(48.8566, ref: "S") == -48.8566)
        #expect(RemoteLensPlan.gpsDecimal(2.3522, ref: "W") == -2.3522)
        #expect(RemoteLensPlan.gpsDecimal(2.3522, ref: nil) == 2.3522)
        #expect(RemoteLensPlan.formatCoordinate(lat: 48.8566, lon: 2.3522) == "48.85660, 2.35220")
    }
}

@Suite("RangeByteSource — source mémoire")
struct RangeByteSourceTests {

    @Test("inMemory : size et lecture de plage exacte")
    func inMemoryReads() async {
        let bytes = Data((0..<256).map { UInt8($0) })
        let src = RangeByteSource.inMemory(bytes)

        #expect(await src.size() == 256)
        let head = await src.read(0...15)
        #expect(head == Data((0...15).map { UInt8($0) }))
        let mid = await src.read(100...103)
        #expect(mid == Data([100, 101, 102, 103]))
    }

    @Test("inMemory : plage dépassant EOF tronquée, hors fichier → nil")
    func inMemoryClamp() async {
        let bytes = Data((0..<10).map { UInt8($0) })
        let src = RangeByteSource.inMemory(bytes)

        let tail = await src.read(8...20)     // dépasse EOF → 8,9
        #expect(tail == Data([8, 9]))
        let beyond = await src.read(10...20)  // entièrement hors fichier
        #expect(beyond == nil)
    }
}
