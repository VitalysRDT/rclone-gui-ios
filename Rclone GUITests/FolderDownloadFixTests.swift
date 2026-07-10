//
//  FolderDownloadFixTests.swift
//  Rclone GUITests
//
//  Tests des helpers purs introduits par le correctif des téléchargements de
//  dossier : conversion cumul→delta de la progression bridge, et détection
//  des destinations iCloud Drive (garde-fou anti-gel du daemon `bird`).
//

import Foundation
import Testing
@testable import Rclone_GUI

@Suite("BridgeFolderDownloader — progressDelta (cumul → delta)")
struct BridgeFolderProgressDeltaTests {

    @Test("Le delta est la différence depuis le dernier cumul reporté")
    func basicDelta() {
        #expect(BridgeFolderDownloader.progressDelta(previous: 0, cumulative: 1_000) == 1_000)
        #expect(BridgeFolderDownloader.progressDelta(previous: 1_000, cumulative: 2_500) == 1_500)
    }

    @Test("La somme des deltas d'une séquence cumulative croissante == dernier cumul")
    func deltasSumToCumulative() {
        let cumulatives: [Int64] = [0, 512, 4_096, 4_096, 1_048_576, 9_000_000]
        var previous: Int64 = 0
        var sum: Int64 = 0
        for c in cumulatives {
            sum += BridgeFolderDownloader.progressDelta(previous: previous, cumulative: c)
            previous = c
        }
        #expect(sum == cumulatives.last!)
        // Régression du bug d'origine : le cumul n'est JAMAIS compté tel quel.
        #expect(sum != cumulatives.reduce(0, +))
    }

    @Test("Un cumul stagnant (tick sans nouveaux octets) donne un delta nul")
    func zeroWhenNoProgress() {
        #expect(BridgeFolderDownloader.progressDelta(previous: 5_000, cumulative: 5_000) == 0)
    }

    @Test("Un reset du cumul (relance de tâche) est clampé à 0, pas négatif")
    func clampsRegressionToZero() {
        #expect(BridgeFolderDownloader.progressDelta(previous: 9_000_000, cumulative: 0) == 0)
    }
}

@Suite("TransferQueue — détection iCloud Drive (anti-gel)")
struct ICloudDrivePathTests {

    @Test("Les chemins iCloud Drive sont détectés")
    func detectsICloud() {
        #expect(TransferQueue.isICloudDrivePath(
            "/private/var/mobile/Library/Mobile Documents/com~apple~CloudDocs/Downloads/daisychain") == true)
        #expect(TransferQueue.isICloudDrivePath(
            "/var/mobile/Library/Mobile Documents/com~apple~CloudDocs/Films") == true)
    }

    @Test("Les chemins locaux (Sur mon iPhone, sandbox) ne le sont pas")
    func rejectsLocal() {
        #expect(TransferQueue.isICloudDrivePath(
            "/var/mobile/Containers/Data/Application/ABC/Documents/daisychain") == false)
        #expect(TransferQueue.isICloudDrivePath(
            "/private/var/mobile/Containers/Shared/AppGroup/XYZ/Downloads") == false)
        #expect(TransferQueue.isICloudDrivePath("") == false)
    }
}
