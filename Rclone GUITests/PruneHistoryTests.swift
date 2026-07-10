//
//  PruneHistoryTests.swift
//  Rclone GUITests
//
//  Tests de la sélection PURE des transferts terminés à purger (borne
//  l'historique SwiftData → le @Query non borné ne matérialise plus des
//  milliers de lignes = fin du « tourne au ralenti »).
//

import Foundation
import Testing
@testable import Rclone_GUI

@Suite("TransferQueue — purge de l'historique (sélection pure)")
struct PruneHistoryTests {

    private func terminal(_ n: Int, batchID: String? = nil) -> [(id: String, batchID: String?)] {
        // Du plus récent (index 0) au plus ancien — comme le fetch trié desc.
        (0..<n).map { (id: "t\($0)", batchID: batchID) }
    }

    @Test("Sous le plafond : rien à supprimer")
    func underCapKeepsAll() {
        let ids = TransferQueue.terminalTransfersToPrune(
            sortedTerminal: terminal(50), runningBatchIDs: [], keepingRecent: 300)
        #expect(ids.isEmpty)
    }

    @Test("Au-delà du plafond : supprime les plus anciens uniquement")
    func overCapDeletesOldest() {
        let ids = TransferQueue.terminalTransfersToPrune(
            sortedTerminal: terminal(305), runningBatchIDs: [], keepingRecent: 300)
        // Les 5 plus anciens (indices 300..304) sont supprimés.
        #expect(ids == ["t300", "t301", "t302", "t303", "t304"])
    }

    @Test("Ne supprime jamais une ligne d'un batch encore en cours")
    func neverPrunesRunningBatchRows() {
        var rows = terminal(300)  // récents, gardés
        // 5 anciens appartenant à un batch encore running → protégés.
        rows += (0..<5).map { (id: "old\($0)", batchID: "batchRunning") }
        // 5 anciens d'un batch terminé → supprimables.
        rows += (0..<5).map { (id: "dead\($0)", batchID: "batchDone") }
        let ids = TransferQueue.terminalTransfersToPrune(
            sortedTerminal: rows, runningBatchIDs: ["batchRunning"], keepingRecent: 300)
        #expect(Set(ids) == Set(["dead0", "dead1", "dead2", "dead3", "dead4"]))
        #expect(!ids.contains { $0.hasPrefix("old") })
    }

    @Test("Plafond exact : rien à supprimer")
    func exactCapKeepsAll() {
        let ids = TransferQueue.terminalTransfersToPrune(
            sortedTerminal: terminal(300), runningBatchIDs: [], keepingRecent: 300)
        #expect(ids.isEmpty)
    }
}
