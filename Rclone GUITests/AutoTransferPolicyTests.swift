//
//  AutoTransferPolicyTests.swift
//  Rclone GUITests
//
//  Tests unitaires du cœur PUR du mode Auto de la file de transferts :
//  table de décision de concurrence (réseau + énergie), classification des
//  erreurs rclone, bornes de backoff par classe, tri petits-fichiers-d'abord
//  et défaut du toggle. Zéro réseau / SwiftData / UI.
//

import Foundation
import Testing
@testable import Rclone_GUI

// MARK: - Table de décision

@Suite("AutoTransferPolicy — table de décision")
struct AutoTransferPolicyDecideTests {

    private func inputs(
        online: Bool = true,
        expensive: Bool = false,
        constrained: Bool = false,
        thermal: ProcessInfo.ThermalState = .nominal,
        lowPower: Bool = false
    ) -> AutoTransferPolicy.Inputs {
        AutoTransferPolicy.Inputs(
            isOnline: online,
            isExpensive: expensive,
            isConstrained: constrained,
            thermal: thermal,
            lowPower: lowPower
        )
    }

    @Test("Wi-Fi nominal → 4 en file, 6 en bridge")
    func nominalWiFi() {
        let d = AutoTransferPolicy.decide(inputs())
        #expect(d == AutoTransferPolicy.Decision(queueConcurrency: 4, bridgeConcurrency: 6, reason: .nominal))
    }

    @Test("Cellulaire → 2 en file, 3 en bridge")
    func cellular() {
        let d = AutoTransferPolicy.decide(inputs(expensive: true))
        #expect(d == AutoTransferPolicy.Decision(queueConcurrency: 2, bridgeConcurrency: 3, reason: .cellular))
    }

    @Test("Mode données réduites → 1/1 quel que soit le lien")
    func constrained() {
        for expensive in [false, true] {
            let d = AutoTransferPolicy.decide(inputs(expensive: expensive, constrained: true))
            #expect(d.queueConcurrency == 1)
            #expect(d.bridgeConcurrency == 1)
            #expect(d.reason == .constrained)
        }
    }

    @Test("Précédence first-match : constrained prime sur serious et lowPower")
    func constrainedPrecedence() {
        let serious = AutoTransferPolicy.decide(inputs(constrained: true, thermal: .serious))
        #expect(serious == AutoTransferPolicy.Decision(queueConcurrency: 1, bridgeConcurrency: 1, reason: .constrained))
        let lp = AutoTransferPolicy.decide(inputs(constrained: true, lowPower: true))
        #expect(lp.reason == .constrained)
    }

    @Test("Économie d'énergie : 2/2 en Wi-Fi, 1/1 en cellulaire")
    func lowPower() {
        let wifi = AutoTransferPolicy.decide(inputs(lowPower: true))
        #expect(wifi == AutoTransferPolicy.Decision(queueConcurrency: 2, bridgeConcurrency: 2, reason: .lowPower))
        let cell = AutoTransferPolicy.decide(inputs(expensive: true, lowPower: true))
        #expect(cell == AutoTransferPolicy.Decision(queueConcurrency: 1, bridgeConcurrency: 1, reason: .lowPower))
    }

    @Test("Thermique serious : 2/2 en Wi-Fi, 1/1 en cellulaire, prime sur lowPower")
    func thermalSerious() {
        let wifi = AutoTransferPolicy.decide(inputs(thermal: .serious))
        #expect(wifi == AutoTransferPolicy.Decision(queueConcurrency: 2, bridgeConcurrency: 2, reason: .thermalSerious))
        let cell = AutoTransferPolicy.decide(inputs(expensive: true, thermal: .serious))
        #expect(cell == AutoTransferPolicy.Decision(queueConcurrency: 1, bridgeConcurrency: 1, reason: .thermalSerious))
        // serious + lowPower simultanés → la raison affichée est thermique.
        let both = AutoTransferPolicy.decide(inputs(thermal: .serious, lowPower: true))
        #expect(both.reason == .thermalSerious)
    }

    @Test("Thermique critical → 1/1, prime sur tout le reste (sauf hors-ligne)")
    func thermalCritical() {
        let d = AutoTransferPolicy.decide(inputs(expensive: true, constrained: true, thermal: .critical, lowPower: true))
        #expect(d == AutoTransferPolicy.Decision(queueConcurrency: 1, bridgeConcurrency: 1, reason: .thermalCritical))
    }

    @Test("Hors-ligne → 1/1 avec raison offline, prime sur tout")
    func offline() {
        let d = AutoTransferPolicy.decide(inputs(online: false, thermal: .critical))
        #expect(d == AutoTransferPolicy.Decision(queueConcurrency: 1, bridgeConcurrency: 1, reason: .offline))
    }

    @Test(".fair est traité comme nominal (aucun bridage prématuré)")
    func fairThermalIsNominal() {
        let d = AutoTransferPolicy.decide(inputs(thermal: .fair))
        #expect(d.queueConcurrency == 4)
        #expect(d.reason == .nominal)
    }

    /// Invariants sur les 64 combinaisons possibles : bornes respectées et
    /// monotonie (à état d'énergie égal, cellulaire ≤ Wi-Fi).
    @Test("Invariants exhaustifs : bornes 1…8 / 1…16 et monotonie cellulaire ≤ Wi-Fi")
    func exhaustiveInvariants() {
        let thermals: [ProcessInfo.ThermalState] = [.nominal, .fair, .serious, .critical]
        for online in [false, true] {
            for constrained in [false, true] {
                for thermal in thermals {
                    for lowPower in [false, true] {
                        let wifi = AutoTransferPolicy.decide(inputs(
                            online: online, expensive: false,
                            constrained: constrained, thermal: thermal, lowPower: lowPower))
                        let cell = AutoTransferPolicy.decide(inputs(
                            online: online, expensive: true,
                            constrained: constrained, thermal: thermal, lowPower: lowPower))
                        for d in [wifi, cell] {
                            #expect((1...8).contains(d.queueConcurrency))
                            #expect((1...16).contains(d.bridgeConcurrency))
                        }
                        #expect(cell.queueConcurrency <= wifi.queueConcurrency)
                        #expect(cell.bridgeConcurrency <= wifi.bridgeConcurrency)
                    }
                }
            }
        }
    }

    @Test("La décision est déterministe (Equatable stable)")
    func deterministic() {
        let i = inputs(expensive: true, thermal: .serious)
        #expect(AutoTransferPolicy.decide(i) == AutoTransferPolicy.decide(i))
    }

    @Test("Chaque raison a un libellé localisé non vide")
    func reasonLabels() {
        for reason in AutoTransferPolicy.Reason.allCases {
            #expect(!reason.localizedLabel.isEmpty)
        }
    }
}

// MARK: - Garde de pause hors-ligne

@Suite("AutoTransferPolicy — garde de pause hors-ligne")
struct AutoTransferPolicyAutoPauseGuardTests {

    private func should(
        status: TransferStatus = .running,
        kind: TransferKind = .download,
        sourceKind: TransferSourceKind = .remote,
        autoEnabled: Bool = true,
        isOnline: Bool = false
    ) -> Bool {
        AutoTransferPolicy.shouldAutoPauseInsteadOfFail(
            status: status, kind: kind, sourceKind: sourceKind,
            autoEnabled: autoEnabled, isOnline: isOnline
        )
    }

    @Test("Download/upload .running hors-ligne en mode Auto → pause auto")
    func nominalPause() {
        #expect(should(kind: .download) == true)
        #expect(should(kind: .upload) == true)
    }

    @Test("Jamais pour une pause manuelle ou une annulation posée pendant l'await")
    func neverConvertsManualStates() {
        // .paused = pause manuelle, .failed = annulé : les convertir en pause
        // auto les ferait relancer par resumeAutoPaused contre la volonté de
        // l'utilisateur.
        #expect(should(status: .paused) == false)
        #expect(should(status: .failed) == false)
        #expect(should(status: .completed) == false)
        #expect(should(status: .enqueued) == false)
    }

    @Test("Jamais pour copy/move/sync/delete (non repêchés par resumeAutoPaused)")
    func neverForUnqueuedKinds() {
        #expect(should(kind: .copy) == false)
        #expect(should(kind: .move) == false)
        #expect(should(kind: .sync) == false)
        #expect(should(kind: .delete) == false)
    }

    @Test("Jamais pour PhotoSync, en ligne, ou en mode manuel")
    func otherExclusions() {
        #expect(should(sourceKind: .photoLibrary) == false)
        #expect(should(isOnline: true) == false)
        #expect(should(autoEnabled: false) == false)
    }
}

// MARK: - Classification des erreurs

@Suite("AutoTransferPolicy — classification d'erreurs")
struct AutoTransferPolicyClassifyTests {

    @Test("Erreurs transitoires reconnues", arguments: [
        "connection reset by peer",
        "connection refused",
        "context deadline exceeded",
        "dial tcp: i/o timeout",
        "read: connection timed out",
        "write: broken pipe",
        "network is unreachable",
        "no route to host",
        "TLS handshake failure",
        "unexpected EOF",
        "HTTP 503 Service Unavailable",
        "502 Bad Gateway",
        // « 504 » sans « timeout » dans le message : épingle le motif 504 lui-même.
        "HTTP error 504",
        "local i/o error",
        "Connection closed mid-response",
    ])
    func transientCorpus(message: String) {
        #expect(AutoTransferPolicy.classify(message) == .transient)
    }

    @Test("Erreurs rate-limit reconnues", arguments: [
        "429 Too Many Requests",
        "googleapi: Error 429: rate limit exceeded",
        "SlowDown: please reduce your request rate",
        // Google Drive remonte ses throttles en 403/quota : ils doivent primer
        // sur les motifs permanents « 403 »/« quota » (sinon 0 retry).
        "googleapi: Error 403: User Rate Limit Exceeded, userRateLimitExceeded",
        "googleapi: Error 429: Quota exceeded for quota metric 'Queries' and limit 'Queries per minute'",
        "Error 403: Quota exceeded for quota metric 'Read requests'",
    ])
    func rateLimitedCorpus(message: String) {
        #expect(AutoTransferPolicy.classify(message) == .rateLimited)
    }

    @Test("Erreurs permanentes reconnues", arguments: [
        "404 Not Found",
        "directory not found",
        "object not found",
        "401 Unauthorized",
        "403 Forbidden",
        "permission denied",
        "insufficient storage",
        "no space left on device",
        "The user's Drive quota has been exceeded",
    ])
    func permanentCorpus(message: String) {
        #expect(AutoTransferPolicy.classify(message) == .permanent)
    }

    @Test("Message inconnu, nil ou vide → unknown (comportement historique)")
    func unknownFallback() {
        #expect(AutoTransferPolicy.classify("some exotic backend error") == .unknown)
        #expect(AutoTransferPolicy.classify(nil) == .unknown)
        #expect(AutoTransferPolicy.classify("") == .unknown)
    }

    @Test("Insensible à la casse")
    func caseInsensitive() {
        #expect(AutoTransferPolicy.classify("CONNECTION RESET") == .transient)
        #expect(AutoTransferPolicy.classify("Permission Denied") == .permanent)
    }
}

// MARK: - Budgets et backoff

@Suite("AutoTransferPolicy — budgets de retry et backoff")
struct AutoTransferPolicyRetryTests {

    @Test("Budgets par classe : transient 3, rateLimited 3, unknown 2, permanent 0")
    func budgets() {
        #expect(AutoTransferPolicy.maxAttempts(for: .transient) == 3)
        #expect(AutoTransferPolicy.maxAttempts(for: .rateLimited) == 3)
        #expect(AutoTransferPolicy.maxAttempts(for: .unknown) == 2)
        #expect(AutoTransferPolicy.maxAttempts(for: .permanent) == 0)
    }

    @Test("Permanent → aucun délai dès la première tentative")
    func permanentNoRetry() {
        #expect(AutoTransferPolicy.retryDelayRange(errorClass: .permanent, attempt: 1) == nil)
    }

    @Test("Transient : bornes exactes de la formule historique (cap 60 s)")
    func transientBounds() {
        #expect(AutoTransferPolicy.retryDelayRange(errorClass: .transient, attempt: 1) == 1.5...3.0)
        #expect(AutoTransferPolicy.retryDelayRange(errorClass: .transient, attempt: 2) == 3.0...6.0)
        #expect(AutoTransferPolicy.retryDelayRange(errorClass: .transient, attempt: 3) == 6.0...12.0)
        // Budget épuisé au-delà de 3 tentatives.
        #expect(AutoTransferPolicy.retryDelayRange(errorClass: .transient, attempt: 4) == nil)
    }

    @Test("Unknown : mêmes bornes que transient, budget 2")
    func unknownBounds() {
        #expect(AutoTransferPolicy.retryDelayRange(errorClass: .unknown, attempt: 1) == 1.5...3.0)
        #expect(AutoTransferPolicy.retryDelayRange(errorClass: .unknown, attempt: 2) == 3.0...6.0)
        #expect(AutoTransferPolicy.retryDelayRange(errorClass: .unknown, attempt: 3) == nil)
    }

    @Test("RateLimited : base 20 s, cap 120 s, budget 3")
    func rateLimitedBounds() {
        #expect(AutoTransferPolicy.retryDelayRange(errorClass: .rateLimited, attempt: 1) == 10.0...20.0)
        #expect(AutoTransferPolicy.retryDelayRange(errorClass: .rateLimited, attempt: 2) == 20.0...40.0)
        #expect(AutoTransferPolicy.retryDelayRange(errorClass: .rateLimited, attempt: 3) == 40.0...80.0)
        #expect(AutoTransferPolicy.retryDelayRange(errorClass: .rateLimited, attempt: 4) == nil)
    }

    @Test("Tentative invalide (0, négative) → nil")
    func invalidAttempt() {
        #expect(AutoTransferPolicy.retryDelayRange(errorClass: .transient, attempt: 0) == nil)
        #expect(AutoTransferPolicy.retryDelayRange(errorClass: .transient, attempt: -1) == nil)
    }
}

// MARK: - Tri petits-fichiers-d'abord

@Suite("AutoTransferPolicy — tri petits-fichiers-d'abord")
struct AutoTransferPolicySortTests {

    /// Horloge de référence des tests : tous les candidats « frais » sont
    /// datés à moins de 60 s de `testNow` (fenêtre d'ancienneté = 10 min).
    private let testNow = Date(timeIntervalSinceReferenceDate: 60)

    private func candidate(
        _ id: String,
        order: Int = 0,
        bytes: Int64,
        started: TimeInterval = 0
    ) -> AutoTransferPolicy.QueueCandidate {
        AutoTransferPolicy.QueueCandidate(
            id: id,
            queueOrder: order,
            bytesTotal: bytes,
            startedAt: Date(timeIntervalSinceReferenceDate: started)
        )
    }

    @Test("À priorité égale, les petits d'abord")
    func smallFirst() {
        let sorted = AutoTransferPolicy.sortSmallFirst([
            candidate("gros", bytes: 5_000_000_000, started: 0),
            candidate("petit", bytes: 1_024, started: 10),
            candidate("moyen", bytes: 50_000_000, started: 5),
        ], now: testNow)
        #expect(sorted.map(\.id) == ["petit", "moyen", "gros"])
    }

    @Test("La priorité manuelle (queueOrder négatif) prime toujours sur la taille")
    func manualPriorityWins() {
        let sorted = AutoTransferPolicy.sortSmallFirst([
            candidate("petit", order: 0, bytes: 1_024),
            candidate("gros-priorisé", order: -1, bytes: 5_000_000_000),
        ], now: testNow)
        #expect(sorted.map(\.id) == ["gros-priorisé", "petit"])
    }

    @Test("Tailles inconnues (≤ 0) en dernier, FIFO par startedAt")
    func unknownSizesLastFIFO() {
        let sorted = AutoTransferPolicy.sortSmallFirst([
            candidate("inconnu-tard", bytes: 0, started: 20),
            candidate("connu", bytes: 999_999_999, started: 30),
            candidate("inconnu-tôt", bytes: -1, started: 10),
        ], now: testNow)
        #expect(sorted.map(\.id) == ["connu", "inconnu-tôt", "inconnu-tard"])
    }

    @Test("Égalité totale départagée par startedAt puis id (ordre stable)")
    func stableTieBreak() {
        let sorted = AutoTransferPolicy.sortSmallFirst([
            candidate("b", bytes: 100, started: 0),
            candidate("a", bytes: 100, started: 0),
            candidate("c", bytes: 100, started: -5),
        ], now: testNow)
        #expect(sorted.map(\.id) == ["c", "a", "b"])
    }

    @Test("Anti-famine : un candidat plus vieux que la fenêtre repasse devant les petits")
    func agingBeatsSize() {
        // « affamé » attend depuis 15 min (> agingWindow 10 min) ; les petits
        // frais ne peuvent plus le doubler.
        let now = Date(timeIntervalSinceReferenceDate: 15 * 60)
        let sorted = AutoTransferPolicy.sortSmallFirst([
            candidate("petit-frais", bytes: 1_024, started: 14 * 60),
            candidate("affamé-gros", bytes: 5_000_000_000, started: 0),
        ], now: now)
        #expect(sorted.map(\.id) == ["affamé-gros", "petit-frais"])
    }

    @Test("Anti-famine : FIFO strict entre candidats anciens, priorité manuelle intacte")
    func agingFIFOAndPriority() {
        let now = Date(timeIntervalSinceReferenceDate: 30 * 60)
        let sorted = AutoTransferPolicy.sortSmallFirst([
            candidate("ancien-2", bytes: 10, started: 5 * 60),
            candidate("ancien-1", bytes: 9_999_999, started: 1 * 60),
            candidate("priorisé-frais", order: -1, bytes: 42, started: 29 * 60),
        ], now: now)
        // queueOrder prime toujours ; entre anciens, FIFO (pas la taille).
        #expect(sorted.map(\.id) == ["priorisé-frais", "ancien-1", "ancien-2"])
    }

    @Test("Sous la fenêtre d'ancienneté, la règle des petits d'abord reste inchangée")
    func freshKeepsSmallFirst() {
        let now = Date(timeIntervalSinceReferenceDate: 9 * 60)
        let sorted = AutoTransferPolicy.sortSmallFirst([
            candidate("gros-9min", bytes: 5_000_000_000, started: 0),
            candidate("petit-frais", bytes: 1_024, started: 8 * 60),
        ], now: now)
        #expect(sorted.map(\.id) == ["petit-frais", "gros-9min"])
    }

    @Test("Permutation-complétude : mêmes éléments en sortie qu'en entrée")
    func permutationComplete() {
        let input = (0..<50).map {
            candidate("t\($0)", order: $0 % 3 - 1, bytes: Int64(($0 * 37) % 11) - 2, started: Double($0 % 7))
        }
        let sorted = AutoTransferPolicy.sortSmallFirst(input, now: testNow)
        #expect(sorted.count == input.count)
        #expect(Set(sorted.map(\.id)) == Set(input.map(\.id)))
    }

    @Test("Liste vide et singleton")
    func edgeCases() {
        #expect(AutoTransferPolicy.sortSmallFirst([], now: testNow).isEmpty)
        let single = [candidate("seul", bytes: 42)]
        #expect(AutoTransferPolicy.sortSmallFirst(single, now: testNow).map(\.id) == ["seul"])
    }
}

// MARK: - Toggle du mode

@Suite("AutoTransferPolicy — état du toggle")
struct AutoTransferPolicyModeTests {

    @Test("Défaut ON quand la clé n'a jamais été posée, respecte la valeur sinon")
    func defaultOnRespectsExplicit() throws {
        let suiteName = "test.autoMode.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(AutoTransferPolicy.isAutoModeEnabled(defaults) == true)
        defaults.set(false, forKey: AutoTransferPolicy.autoModeEnabledKey)
        #expect(AutoTransferPolicy.isAutoModeEnabled(defaults) == false)
        defaults.set(true, forKey: AutoTransferPolicy.autoModeEnabledKey)
        #expect(AutoTransferPolicy.isAutoModeEnabled(defaults) == true)
    }
}
