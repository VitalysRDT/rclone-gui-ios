//
//  AutoTransferPolicy.swift
//  Rclone GUI — Services
//
//  Cœur PUR du mode « Auto » de la file de transferts : table de décision de
//  concurrence pilotée par le contexte (réseau + énergie), classification des
//  erreurs rclone pour un retry intelligent, bornes de backoff par classe, et
//  tri petits-fichiers-d'abord. Aucune dépendance (ni réseau, ni SwiftData,
//  ni UI) : des structs d'entrées → des structs de décision, entièrement
//  testable en table (pattern maison PhotoSyncLimits).
//
//  TransferQueue échantillonne les signaux (NWPathMonitor, ProcessInfo) aux
//  évènements déjà câblés et APPLIQUE la décision — la politique ne vit
//  qu'ici. Mode Auto coupé → TransferQueue retombe octet pour octet sur les
//  réglages manuels existants (maxConcurrent, backoff historique).
//

import Foundation

// `nonisolated` : le projet est en SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor —
// sans ça, les types imbriqués et les static let hériteraient de l'isolation
// MainActor (erreur en mode Swift 6 quand les helpers `nonisolated` les
// touchent, et conformances Equatable inutilisables dans les tests).
nonisolated public enum AutoTransferPolicy {

    // MARK: - Mode

    /// Clé UserDefaults du mode Auto. Défaut ON tant que l'utilisateur n'a
    /// jamais touché au toggle (object == nil). Le mode Auto n'ÉCRIT jamais
    /// les clés manuelles (transfer.maxConcurrentTransfers…) : les couper/
    /// remettre restaure le comportement manuel à l'identique.
    public static let autoModeEnabledKey = "transfer.autoModeEnabled"

    nonisolated public static func isAutoModeEnabled(_ defaults: UserDefaults) -> Bool {
        defaults.object(forKey: autoModeEnabledKey) == nil
            ? true
            : defaults.bool(forKey: autoModeEnabledKey)
    }

    // MARK: - Table de décision (concurrence)

    /// Photographie des signaux contextuels au moment de la décision.
    nonisolated public struct Inputs: Sendable, Equatable {
        public var isOnline: Bool
        public var isExpensive: Bool
        public var isConstrained: Bool
        public var thermal: ProcessInfo.ThermalState
        public var lowPower: Bool

        public init(
            isOnline: Bool,
            isExpensive: Bool,
            isConstrained: Bool,
            thermal: ProcessInfo.ThermalState,
            lowPower: Bool
        ) {
            self.isOnline = isOnline
            self.isExpensive = isExpensive
            self.isConstrained = isConstrained
            self.thermal = thermal
            self.lowPower = lowPower
        }
    }

    /// Raison dominante de la décision — affichée dans Réglages → Performance
    /// pour que la valeur « automatique » reste explicable à l'utilisateur.
    nonisolated public enum Reason: String, Sendable, CaseIterable {
        case nominal
        case cellular
        case constrained
        case lowPower
        case thermalSerious
        case thermalCritical
        case offline

        public var localizedLabel: String {
            switch self {
            case .nominal:          return String(localized: "connexion rapide")
            case .cellular:         return String(localized: "réseau cellulaire")
            case .constrained:      return String(localized: "mode données réduites")
            case .lowPower:         return String(localized: "économie d'énergie")
            case .thermalSerious:   return String(localized: "appareil chaud")
            case .thermalCritical:  return String(localized: "surchauffe critique")
            case .offline:          return String(localized: "hors-ligne")
            }
        }
    }

    nonisolated public struct Decision: Sendable, Equatable {
        /// Nb max de download/upload simultanés dans la file bornée (1…8,
        /// mêmes bornes que setMaxConcurrent).
        public var queueConcurrency: Int
        /// Concurrence des téléchargeurs parallèles de dossier (workers
        /// multi-fichiers, 1…16). Exposé dans la décision pour que le chemin
        /// dossier la consomme dès qu'il est branché.
        public var bridgeConcurrency: Int
        public var reason: Reason

        public init(queueConcurrency: Int, bridgeConcurrency: Int, reason: Reason) {
            self.queueConcurrency = queueConcurrency
            self.bridgeConcurrency = bridgeConcurrency
            self.reason = reason
        }
    }

    /// Table first-match-wins : états DISCRETS uniquement (pas de seuil
    /// continu ni de boucle de rétroaction → aucune oscillation possible).
    /// La décision ne fait que borner la concurrence ; le débit (bwlimit)
    /// reste gouverné par smartCeiling/applyNetworkPolicy, séparation nette.
    nonisolated public static func decide(_ inputs: Inputs) -> Decision {
        let decision: Decision
        if !inputs.isOnline {
            // Hors-ligne : la file est de toute façon bloquée par
            // canStartNewTransfers ; on affiche une valeur minimale honnête.
            decision = Decision(queueConcurrency: 1, bridgeConcurrency: 1, reason: .offline)
        } else if inputs.thermal == .critical {
            decision = Decision(queueConcurrency: 1, bridgeConcurrency: 1, reason: .thermalCritical)
        } else if inputs.isConstrained {
            // Mode données réduites : l'utilisateur a demandé le strict
            // minimum au niveau système — on s'aligne.
            decision = Decision(queueConcurrency: 1, bridgeConcurrency: 1, reason: .constrained)
        } else if inputs.thermal == .serious || inputs.lowPower {
            let reason: Reason = inputs.thermal == .serious ? .thermalSerious : .lowPower
            decision = inputs.isExpensive
                ? Decision(queueConcurrency: 1, bridgeConcurrency: 1, reason: reason)
                : Decision(queueConcurrency: 2, bridgeConcurrency: 2, reason: reason)
        } else if inputs.isExpensive {
            // Cellulaire / hotspot : 2 flux suffisent à saturer le lien sans
            // multiplier les connexions radio coûteuses en énergie.
            decision = Decision(queueConcurrency: 2, bridgeConcurrency: 3, reason: .cellular)
        } else {
            // Wi-Fi + froid + non facturé : on pousse la concurrence des
            // fichiers de dossier (8) pour saturer le lien — chaque fichier
            // est un copyfile async léger. queueConcurrency (transferts
            // séparés) reste à 4, plus conservateur.
            decision = Decision(queueConcurrency: 4, bridgeConcurrency: 8, reason: .nominal)
        }
        return Decision(
            queueConcurrency: min(max(decision.queueConcurrency, 1), 8),
            bridgeConcurrency: min(max(decision.bridgeConcurrency, 1), 16),
            reason: decision.reason
        )
    }

    // MARK: - Classification des erreurs (retry intelligent)

    nonisolated public enum ErrorClass: Sendable, Equatable {
        /// Erreur réseau passagère → retry avec le backoff standard.
        case transient
        /// Le backend demande de ralentir (429…) → retry avec backoff long.
        case rateLimited
        /// Erreur définitive (404, 403, disque plein…) → aucune tentative,
        /// échec immédiat au lieu de 2 retries gaspillés.
        case permanent
        /// Message non reconnu → traité comme l'existant (2 tentatives).
        case unknown
    }

    /// Motifs PERMANENTS volontairement étroits : un faux « permanent »
    /// supprimerait des retries légitimes, alors qu'un faux « transient » ne
    /// coûte que quelques tentatives bornées. Corpus tiré des messages
    /// rclone/Go réels (anglais quel que soit le backend).
    private static let permanentPatterns = [
        "not found", "directory not found", "object not found",
        "401", "403", "unauthorized", "forbidden", "permission denied",
        "quota", "insufficient storage", "no space left",
    ]
    /// Inclut les formes collées de l'API Google (« userRateLimitExceeded »)
    /// et les quotas de DÉBIT GCP (« quota metric », « queries per ») — à
    /// distinguer des quotas de STOCKAGE (« Drive quota has been exceeded »)
    /// qui restent permanents.
    private static let rateLimitedPatterns = [
        "429", "too many requests", "rate limit", "ratelimitexceeded",
        "quota metric", "queries per", "slowdown", "slow down",
    ]
    private static let transientPatterns = [
        "timeout", "timed out", "connection reset", "connection refused",
        "broken pipe", "network is unreachable", "no route to host",
        "tls handshake", "eof", "502", "503", "504", "i/o error",
        "context deadline exceeded", "connection closed",
    ]

    nonisolated public static func classify(_ message: String?) -> ErrorClass {
        guard let message, !message.isEmpty else { return .unknown }
        let lowered = message.lowercased()
        // rate-limit AVANT permanent : Google Drive remonte ses throttles en
        // « Error 403: User Rate Limit Exceeded » / « Quota exceeded for
        // quota metric » — un marqueur rate-limit est plus spécifique qu'un
        // « 403 »/« quota » générique, et un faux permanent = 0 retry.
        if rateLimitedPatterns.contains(where: { lowered.contains($0) }) { return .rateLimited }
        if permanentPatterns.contains(where: { lowered.contains($0) }) { return .permanent }
        if transientPatterns.contains(where: { lowered.contains($0) }) { return .transient }
        return .unknown
    }

    /// Garde PURE de la pause hors-ligne (`autoPauseInsteadOfFail`) : un
    /// échec pendant une coupure réseau ne convertit en pause AUTO que les
    /// download/upload encore `.running` — jamais une pause MANUELLE
    /// (`.paused`) ni une annulation (`.failed`) posée pendant un await du
    /// dispatch/poll (sinon resumeAutoPaused relancerait un transfert que
    /// l'utilisateur vient de suspendre ou d'annuler), jamais PhotoSync
    /// (pipeline d'état propre), jamais en mode manuel.
    nonisolated public static func shouldAutoPauseInsteadOfFail(
        status: TransferStatus,
        kind: TransferKind,
        sourceKind: TransferSourceKind,
        autoEnabled: Bool,
        isOnline: Bool
    ) -> Bool {
        autoEnabled
            && status == .running
            && (kind == .download || kind == .upload)
            && sourceKind != .photoLibrary
            && !isOnline
    }

    /// Budget de tentatives auto par classe. `.unknown` = 2 → strictement le
    /// comportement historique (maxAutoRetries) pour tout message non reconnu.
    nonisolated public static func maxAttempts(for errorClass: ErrorClass) -> Int {
        switch errorClass {
        case .transient:   return 3
        case .rateLimited: return 3
        case .permanent:   return 0
        case .unknown:     return 2
        }
    }

    /// Bornes du délai avant la tentative `attempt` (1-indexée), ou nil si le
    /// budget de la classe est épuisé. PUR et déterministe : le jitter
    /// (Double.random dans la plage) est tiré par l'appelant, les bornes
    /// restent donc testables exactement. transient/unknown reproduisent la
    /// formule historique (cap 60 s) ; rateLimited attend plus longtemps
    /// (base 20 s, cap 120 s) pour laisser le backend souffler.
    nonisolated public static func retryDelayRange(
        errorClass: ErrorClass,
        attempt: Int
    ) -> ClosedRange<TimeInterval>? {
        guard attempt >= 1, attempt <= maxAttempts(for: errorClass) else { return nil }
        let capped: Double
        switch errorClass {
        case .permanent:
            return nil
        case .rateLimited:
            capped = min(120.0, 20.0 * pow(2.0, Double(attempt - 1)))
        case .transient, .unknown:
            capped = min(60.0, 3.0 * pow(2.0, Double(attempt - 1)))
        }
        return (capped / 2)...capped
    }

    // MARK: - Tri petits-fichiers-d'abord

    /// Projection minimale d'un Transfer .enqueued pour l'ordonnancement.
    nonisolated public struct QueueCandidate: Sendable, Equatable {
        public var id: String
        public var queueOrder: Int
        public var bytesTotal: Int64
        public var startedAt: Date

        public init(id: String, queueOrder: Int, bytesTotal: Int64, startedAt: Date) {
            self.id = id
            self.queueOrder = queueOrder
            self.bytesTotal = bytesTotal
            self.startedAt = startedAt
        }
    }

    /// Fenêtre d'ancienneté anti-famine : au-delà, un candidat repasse en
    /// FIFO DEVANT la règle de taille — un gros fichier ne peut pas être
    /// doublé indéfiniment par un flux continu de petits fichiers.
    public static let agingWindow: TimeInterval = 10 * 60

    /// Ordre de dispatch du mode Auto : à priorité manuelle égale, les petits
    /// transferts d'abord → maximise le nombre d'éléments TERMINÉS par minute
    /// (un gros fichier n'occupe pas tous les slots pendant que 30 petits
    /// attendent). Règles :
    ///   1. queueOrder croissant — le geste « Prioriser » (min-1) et l'ordre
    ///      manuel priment TOUJOURS sur la taille ;
    ///   2. à queueOrder égal : les candidats en attente depuis plus de
    ///      `agingWindow` d'abord, FIFO entre eux (anti-famine) ;
    ///   3. puis tailles connues (bytesTotal > 0) croissantes ;
    ///   4. tailles inconnues (≤ 0) en dernier, FIFO par startedAt ;
    ///   5. départage final startedAt puis id → ordre total, stable,
    ///      déterministe. `now` injecté pour des tests exacts.
    nonisolated public static func sortSmallFirst(
        _ candidates: [QueueCandidate],
        now: Date = .now
    ) -> [QueueCandidate] {
        candidates.sorted { a, b in
            if a.queueOrder != b.queueOrder { return a.queueOrder < b.queueOrder }
            let aAged = now.timeIntervalSince(a.startedAt) > agingWindow
            let bAged = now.timeIntervalSince(b.startedAt) > agingWindow
            if aAged != bAged { return aAged }
            if !aAged {
                // Les deux sont frais → petits d'abord.
                let aKnown = a.bytesTotal > 0
                let bKnown = b.bytesTotal > 0
                if aKnown != bKnown { return aKnown }
                if aKnown, a.bytesTotal != b.bytesTotal { return a.bytesTotal < b.bytesTotal }
            }
            // Les deux sont anciens (FIFO strict) ou à égalité de taille.
            if a.startedAt != b.startedAt { return a.startedAt < b.startedAt }
            return a.id < b.id
        }
    }
}
