//
//  FolderProgressTests.swift
//  Rclone GUITests
//
//  Test de la progression AFFICHÉE d'un download de dossier : cumul terminé +
//  in-flight, borné, monotone. Corrige le bug « alterne entre des Mo et 0 »
//  (tickStats n'affichait que l'in-flight, qui retombait aux rotations).
//

import Foundation
import Testing
@testable import Rclone_GUI

@Suite("TransferQueue — progression affichée d'un dossier")
struct FolderProgressTests {

    @Test("Cumul terminé + in-flight")
    func sumsCompletedAndInFlight() {
        #expect(TransferQueue.folderDisplayedBytes(completed: 300, inFlight: 50, total: 1000) == 350)
    }

    @Test("Borné au total")
    func clampedToTotal() {
        #expect(TransferQueue.folderDisplayedBytes(completed: 900, inFlight: 500, total: 1000) == 1000)
    }

    @Test("In-flight négatif ou nul traité comme 0")
    func nonNegativeInFlight() {
        #expect(TransferQueue.folderDisplayedBytes(completed: 300, inFlight: -10, total: 1000) == 300)
        #expect(TransferQueue.folderDisplayedBytes(completed: 300, inFlight: 0, total: 1000) == 300)
    }

    @Test("Total inconnu (0) → pas de clamp")
    func unknownTotalNoClamp() {
        #expect(TransferQueue.folderDisplayedBytes(completed: 300, inFlight: 50, total: 0) == 350)
    }

    @Test("Rotation de fichier : la valeur ne retombe PAS (monotone)")
    func monotonicAcrossFileRotation() {
        let total: Int64 = 1000
        // Fichier A (100) en cours, rien de terminé.
        let duringA = TransferQueue.folderDisplayedBytes(completed: 0, inFlight: 100, total: total)
        // A terminé (→ completed), B (30) démarre : A quitte l'in-flight.
        let afterA = TransferQueue.folderDisplayedBytes(completed: 100, inFlight: 30, total: total)
        // La barre NE redescend jamais sous le cumul terminé (100) → jamais 0.
        #expect(duringA == 100)
        #expect(afterA == 130)
        #expect(afterA >= 100)   // ce qui cassait avant : afterA valait 30 (in-flight seul)
    }
}
