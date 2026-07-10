//
//  GlassEngine.swift
//  Rclone GUI — Core
//
//  « Glass Engine » : le moteur de transparence réseau qui prouve la
//  revendication « 0 appel maison ». Deux morceaux :
//
//   1. `GlassEngine` — logique PURE (`nonisolated`, Foundation-only, testable) :
//      - une allowlist DÉCLARATIVE de toute la surface d'egress de l'app,
//        dérivée de la source de vérité `BackendOverrides.oauthConfigs` (donc
//        impossible d'oublier un host provider) + Apple + loopback ;
//      - `classify(host:)` qui range n'importe quel host en catégorie, où
//        **tout ce qui n'est pas explicitement de confiance retombe en `.home`**
//        (le rouge, qui doit rester à 0) ;
//      - des denylists (hosts maison + symboles SDK de tracking) consommées par
//        les tests et le garde de build `scripts/verify-no-phone-home.sh`.
//
//   2. `GlassEngineMonitor` — un bus PASSIF (`@MainActor`, `ObservableObject`).
//      Les points d'appel réseau existants (échange de token OAuth, démarrage du
//      pont loopback) émettent une ligne AVANT de partir. On n'enveloppe JAMAIS
//      le transport : le pipeline de download a été stabilisé sur 8 PR, on n'y
//      touche pas. L'entrée `record(...)` est `nonisolated` et non bloquante, donc
//      appelable depuis n'importe quel domaine d'isolation (acteur rclone inclus).
//
//  Ce que le moniteur NE voit PAS : le trafic natif de librclone (Go), qui sort
//  hors d'URLSession. On l'assume honnêtement dans l'UI en DÉCLARANT, depuis le
//  `config/dump` de rclone, exactement quels remotes (donc quels hosts) rclone
//  contactera — tous configurés par l'utilisateur, aucun « maison ».
//

import Foundation
import Combine

// MARK: - Modèle

/// Catégorie de destination réseau. `isTrusted == false` uniquement pour `.home`.
public enum EgressCategory: String, Sendable, CaseIterable, Codable {
    /// `127.0.0.1` — pont rclone sur l'appareil, ne quitte jamais le téléphone.
    case loopback
    /// Host OAuth/API d'un fournisseur cloud, déclaré dans `BackendOverrides`.
    case provider
    /// Service Apple (StoreKit, iCloud KVS, redeem App Store).
    case apple
    /// Un remote que l'UTILISATEUR a configuré dans rclone (lu via `config/dump`).
    case userRemote
    /// Tout le reste → un « appel maison ». DOIT rester à 0.
    case home

    public var isTrusted: Bool { self != .home }
}

/// Une destination que l'app est CONÇUE pour contacter (entrée d'allowlist).
public struct EgressDestination: Sendable, Hashable, Identifiable {
    public let host: String
    public let category: EgressCategory
    /// Libellé lisible (déjà localisé) expliquant le pourquoi de cette destination.
    public let purpose: String

    public var id: String { "\(category.rawValue)|\(host)|\(purpose)" }

    public init(host: String, category: EgressCategory, purpose: String) {
        self.host = host
        self.category = category
        self.purpose = purpose
    }
}

/// Un événement d'egress observé en direct (alimente le journal du moniteur).
public struct EgressEvent: Sendable, Hashable, Identifiable {
    public let id: UUID
    public let host: String
    public let category: EgressCategory
    public let purpose: String
    public let date: Date

    public init(host: String, category: EgressCategory, purpose: String, date: Date, id: UUID = UUID()) {
        self.id = id
        self.host = host
        self.category = category
        self.purpose = purpose
        self.date = date
    }
}

// MARK: - Logique pure

public enum GlassEngine {

    // MARK: Hosts de confiance

    /// Suffixes de hosts Apple (StoreKit, iCloud, App Store). Match exact ou sous-domaine.
    public static let appleHostSuffixes: [String] = [
        "apple.com", "icloud.com", "icloud-content.com", "cdn-apple.com", "mzstatic.com"
    ]

    /// Hosts loopback (pont rclone sur l'appareil).
    public static let loopbackHosts: Set<String> = ["127.0.0.1", "localhost", "::1", "[::1]"]

    /// Hosts des fournisseurs OAuth, DÉRIVÉS de la source de vérité
    /// `BackendOverrides.oauthConfigs` (auth + token de chaque backend). Calculé
    /// une fois. C'est ce qui garantit qu'aucun host provider ne peut être oublié
    /// dans l'allowlist : elle EST la config.
    public static let providerHosts: Set<String> = {
        var hosts = Set<String>()
        for cfg in BackendOverrides.oauthConfigs.values {
            if let h = cfg.authURL.host?.lowercased() { hosts.insert(h) }
            if let h = cfg.tokenURL.host?.lowercased() { hosts.insert(h) }
        }
        return hosts
    }()

    // MARK: Denylists (garde de build + tests)

    /// Fragments de hosts « maison » / télémétrie qui ne doivent JAMAIS apparaître
    /// comme cible réseau dans le code. `rougetet.com` y figure : le site n'est
    /// atteint que si l'utilisateur ouvre un lien (→ Safari), jamais par l'app.
    /// Consommé par `scripts/verify-no-phone-home.sh`.
    public static let homeDenylistHostFragments: [String] = [
        "rougetet.com",
        "vercel.app", "vercel.com",
        "supabase.co", "supabase.in", "supabase.com",
        "sentry.io", "ingest.sentry",
        "firebaseio.com", "firebaseinstallations", "app-measurement.com",
        "crashlytics.com", "crashlyticsreports",
        "mixpanel.com", "amplitude.com",
        "segment.io", "segment.com",
        "google-analytics.com", "googletagmanager.com", "analytics.google.com",
        "bugsnag.com", "datadoghq.com", "appcenter.ms",
        "flurry.com", "adjust.com", "appsflyer.com", "app.adjust",
        "branch.io", "onesignal.com", "instabug.com", "smartlook.com"
    ]

    /// Symboles / imports de SDK de tracking interdits dans le binaire.
    /// Consommé par `scripts/verify-no-phone-home.sh`.
    public static let telemetrySymbolDenylist: [String] = [
        "FirebaseAnalytics", "FirebaseCrashlytics", "Crashlytics",
        "Sentry", "Mixpanel", "Amplitude", "SegmentAnalytics",
        "Bugsnag", "AppCenterAnalytics", "AppCenterCrashes",
        "GoogleAnalytics", "GoogleAppMeasurement", "Flurry",
        "Adjust", "AppsFlyerLib", "BranchSDK", "OneSignalFramework",
        "DatadogCore", "Instabug", "Smartlook", "TelemetryDeck"
    ]

    // MARK: Classification

    /// Range un host en catégorie. Tout host inconnu → `.home` (fail-closed :
    /// c'est le rouge, qui doit rester à 0).
    public static func classify(host rawHost: String?) -> EgressCategory {
        guard let host = normalizedHost(rawHost) else { return .home }
        if loopbackHosts.contains(host) { return .loopback }
        if matchesSuffix(host, in: appleHostSuffixes) { return .apple }
        if providerHosts.contains(host) || providerHosts.contains(where: { host.hasSuffix("." + $0) }) {
            return .provider
        }
        return .home
    }

    /// Vrai si `host` (ou un de ses sous-domaines) figure dans les fragments maison.
    /// Utilisé pour repérer un endpoint maison qui aurait fuité.
    public static func isHomeHost(_ rawHost: String?) -> Bool {
        guard let host = normalizedHost(rawHost) else { return false }
        return homeDenylistHostFragments.contains { host.contains($0) }
    }

    private static func normalizedHost(_ rawHost: String?) -> String? {
        guard var host = rawHost?.lowercased() else { return nil }
        host = host.trimmingCharacters(in: .whitespacesAndNewlines)
        return host.isEmpty ? nil : host
    }

    private static func matchesSuffix(_ host: String, in suffixes: [String]) -> Bool {
        suffixes.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    // MARK: Allowlist déclarative

    /// La liste COMPLÈTE des destinations que l'app est conçue pour contacter,
    /// pour l'écran de transparence. Groupée par host pour rester lisible.
    public static func declaredAllowlist() -> [EgressDestination] {
        var dests: [EgressDestination] = []

        // 1) Loopback — pont rclone sur l'appareil.
        dests.append(EgressDestination(
            host: "127.0.0.1",
            category: .loopback,
            purpose: String(localized: "Pont rclone local — téléchargements & streaming, restent sur l'appareil")
        ))

        // 2) Apple — abonnement & codes promo.
        dests.append(EgressDestination(
            host: "apps.apple.com",
            category: .apple,
            purpose: String(localized: "App Store — abonnement & codes promo (StoreKit)")
        ))

        // 3) Fournisseurs OAuth — groupés par host, dérivés de BackendOverrides.
        var backendsByHost: [String: Set<String>] = [:]
        for (backend, cfg) in BackendOverrides.oauthConfigs {
            if let h = cfg.authURL.host?.lowercased() { backendsByHost[h, default: []].insert(backend) }
            if let h = cfg.tokenURL.host?.lowercased() { backendsByHost[h, default: []].insert(backend) }
        }
        for host in backendsByHost.keys.sorted() {
            let backends = backendsByHost[host]!.sorted().joined(separator: ", ")
            let purpose = String(localized: "OAuth — connexion à vos comptes : \(backends)")
            dests.append(EgressDestination(host: host, category: .provider, purpose: purpose))
        }

        return dests
    }

    // MARK: Verdict

    public struct Verdict: Sendable, Equatable {
        public let homeCallCount: Int
        public let countsByCategory: [EgressCategory: Int]
        public var isClean: Bool { homeCallCount == 0 }

        public init(homeCallCount: Int, countsByCategory: [EgressCategory: Int]) {
            self.homeCallCount = homeCallCount
            self.countsByCategory = countsByCategory
        }
    }

    /// Compte les événements par catégorie et isole le nombre d'appels maison.
    public static func verdict(events: [EgressEvent]) -> Verdict {
        var counts: [EgressCategory: Int] = [:]
        for e in events { counts[e.category, default: 0] += 1 }
        return Verdict(homeCallCount: counts[.home] ?? 0, countsByCategory: counts)
    }
}

// MARK: - Bus passif observable

/// Collecte non intrusive des egress observés côté URLSession (échange de token
/// OAuth, démarrage du pont loopback). N'enveloppe pas le transport ; se contente
/// d'enregistrer une ligne avant chaque appel. Alimente l'écran `GlassEngineView`.
@MainActor
public final class GlassEngineMonitor: ObservableObject {

    public static let shared = GlassEngineMonitor()

    /// Journal en anneau (les plus récents en dernier), borné pour ne pas grossir.
    @Published public private(set) var events: [EgressEvent] = []
    /// Compteurs cumulés par catégorie (survivent au rognage du journal).
    @Published public private(set) var countsByCategory: [EgressCategory: Int] = [:]

    private let maxEvents = 500

    private init() {}

    /// Point d'entrée NON bloquant, appelable depuis n'importe quel domaine
    /// d'isolation (les call-sites incluent l'acteur `RcloneStreamingService`).
    /// Programme l'ingestion sur le MainActor et rend la main immédiatement.
    nonisolated public static func record(host: String?, purpose: String) {
        Task { @MainActor in
            shared.ingest(host: host, purpose: purpose, date: Date())
        }
    }

    /// Variante testable/synchrone (déjà sur le MainActor).
    public func ingest(host: String?, purpose: String, date: Date) {
        let category = GlassEngine.classify(host: host)
        let shownHost = (host?.isEmpty == false) ? host! : "—"
        events.append(EgressEvent(host: shownHost, category: category, purpose: purpose, date: date))
        if events.count > maxEvents {
            events.removeFirst(events.count - maxEvents)
        }
        countsByCategory[category, default: 0] += 1
    }

    /// Verdict courant (sur le cumul des compteurs, robuste au rognage).
    public var verdict: GlassEngine.Verdict {
        GlassEngine.Verdict(
            homeCallCount: countsByCategory[.home] ?? 0,
            countsByCategory: countsByCategory
        )
    }

    /// Journal exportable en texte brut (bouton « Partager » de l'écran).
    public func exportText() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        var lines: [String] = [
            "Glass Engine — journal réseau",
            "Appels maison : \(verdict.homeCallCount)",
            ""
        ]
        for e in events {
            lines.append("\(formatter.string(from: e.date))  [\(e.category.rawValue)]  \(e.host)  — \(e.purpose)")
        }
        return lines.joined(separator: "\n")
    }

    public func clear() {
        events.removeAll()
        countsByCategory.removeAll()
    }
}
