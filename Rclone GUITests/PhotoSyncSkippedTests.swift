//
//  PhotoSyncSkippedTests.swift
//  Rclone GUITests
//
//  Régression du « bloqué à N photos » : les assets .skipped (asset supprimé/
//  déplacé, accès Photos perdu, illisible) étaient comptés dans le total mais
//  invisibles, laissant « N restantes » plafonner sans explication. On vérifie
//  que le résumé les surface (skippedCount), les exclut des « restantes »
//  (outstandingCount) et les affiche dans le libellé.
//

import Foundation
import Testing
@testable import Rclone_GUI

@Suite("PhotoSync — visibilité des .skipped")
struct PhotoSyncSkippedTests {

    private func summary(
        indexed: Int, pending: Int, active: Int,
        completed: Int, failed: Int, skipped: Int
    ) -> PhotoSyncRunSummary {
        PhotoSyncRunSummary(
            authorization: .authorized,
            visibleAssetCount: indexed,
            indexedCount: indexed,
            newlyIndexedCount: 0,
            enqueuedCount: 0,
            pendingCount: pending,
            activeCount: active,
            completedCount: completed,
            failedCount: failed,
            skippedCount: skipped,
            totalBytes: 0,
            transferredBytes: 0,
            averageBytesPerSecond: 0,
            estimatedTimeRemaining: nil,
            pausedByUser: false,
            sessionUploaded: 0,
            sessionInitialPending: 0,
            sessionEstimatedRemaining: nil
        )
    }

    @Test("effectiveTotal inclut les ignorées")
    func effectiveTotalIncludesSkipped() {
        let s = summary(indexed: 3000, pending: 0, active: 0, completed: 2600, failed: 0, skipped: 400)
        #expect(s.effectiveTotal == 3000)
    }

    @Test("outstandingCount = pending + active + failed (exclut les ignorées)")
    func outstandingExcludesSkipped() {
        let s = summary(indexed: 3000, pending: 5, active: 2, completed: 2600, failed: 3, skipped: 390)
        #expect(s.outstandingCount == 10)
    }

    @Test("Régression « bloqué à 2600 » : que des ignorées → 0 restantes, libellé explicite")
    func stuckAt2600IsExplained() {
        let s = summary(indexed: 3000, pending: 0, active: 0, completed: 2600, failed: 0, skipped: 400)
        // Avant : remaining = total - completed = 400 « restantes » fantômes qui
        // ne drainaient jamais. Après : outstanding = 0, et 400 « ignorées ».
        #expect(s.effectiveTotal == 3000)
        #expect(s.skippedCount == 400)
        #expect(s.outstandingCount == 0)
        // NB : on n'assert pas le « 2600 / 3000 » littéral — String(localized:)
        // insère un séparateur de milliers dépendant de la locale (« 2 600 »).
        let label = s.displayLabel
        #expect(label.contains("ignorées"))
        #expect(!label.contains("restantes"))
    }

    @Test("Sans ignorées, libellé inchangé (pas de bruit)")
    func noSkippedNoClutter() {
        let s = summary(indexed: 100, pending: 10, active: 0, completed: 90, failed: 0, skipped: 0)
        let label = s.displayLabel
        #expect(label.contains("90 / 100"))
        #expect(label.contains("10 restantes"))
        #expect(!label.contains("ignorées"))
    }

    @Test("Échecs comptés dans les restantes (récupérables), pas les ignorées")
    func failedCountsAsOutstanding() {
        let s = summary(indexed: 100, pending: 0, active: 0, completed: 80, failed: 15, skipped: 5)
        #expect(s.outstandingCount == 15)
        let label = s.displayLabel
        #expect(label.contains("15 restantes"))
        #expect(label.contains("5 ignorées"))
    }
}
