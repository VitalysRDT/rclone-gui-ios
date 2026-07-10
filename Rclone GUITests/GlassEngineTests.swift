//
//  GlassEngineTests.swift
//  Rclone GUITests
//
//  Tests unitaires du Glass Engine (moniteur « 0 appel maison ») :
//  classification des hosts (fail-closed → .home), complétude de l'allowlist
//  vis-à-vis de la source de vérité BackendOverrides.oauthConfigs, verdict,
//  denylists, et bus passif GlassEngineMonitor. Zéro réseau / UI.
//

import Foundation
import Testing
@testable import Rclone_GUI

// MARK: - Classification

@Suite("GlassEngine — classify()")
struct GlassEngineClassifyTests {

    @Test("Loopback → .loopback")
    func loopback() {
        #expect(GlassEngine.classify(host: "127.0.0.1") == .loopback)
        #expect(GlassEngine.classify(host: "localhost") == .loopback)
        #expect(GlassEngine.classify(host: "::1") == .loopback)
    }

    @Test("Hosts Apple (exact + sous-domaine) → .apple")
    func apple() {
        #expect(GlassEngine.classify(host: "apps.apple.com") == .apple)
        #expect(GlassEngine.classify(host: "buy.itunes.apple.com") == .apple)
        #expect(GlassEngine.classify(host: "gateway.icloud.com") == .apple)
        // Sensible à la casse ? non — normalisé en minuscule.
        #expect(GlassEngine.classify(host: "APPS.APPLE.COM") == .apple)
    }

    @Test("Hosts fournisseurs OAuth → .provider")
    func provider() {
        #expect(GlassEngine.classify(host: "accounts.google.com") == .provider)
        #expect(GlassEngine.classify(host: "oauth2.googleapis.com") == .provider)
        #expect(GlassEngine.classify(host: "api.dropboxapi.com") == .provider)
        #expect(GlassEngine.classify(host: "login.microsoftonline.com") == .provider)
    }

    @Test("Hosts maison / inconnus / vides → .home (fail-closed)")
    func home() {
        #expect(GlassEngine.classify(host: "rclone.rougetet.com") == .home)
        #expect(GlassEngine.classify(host: "api.vercel.app") == .home)
        #expect(GlassEngine.classify(host: "xyz.supabase.co") == .home)
        #expect(GlassEngine.classify(host: "o123.ingest.sentry.io") == .home)
        #expect(GlassEngine.classify(host: "evil.example.com") == .home)
        #expect(GlassEngine.classify(host: nil) == .home)
        #expect(GlassEngine.classify(host: "") == .home)
        #expect(GlassEngine.classify(host: "   ") == .home)
    }

    @Test("isTrusted : seul .home n'est pas de confiance")
    func trust() {
        for c in EgressCategory.allCases {
            #expect(c.isTrusted == (c != .home))
        }
    }
}

// MARK: - Allowlist / complétude vs BackendOverrides

@Suite("GlassEngine — allowlist & complétude")
struct GlassEngineAllowlistTests {

    @Test("Tout host OAuth de BackendOverrides est de confiance, jamais .home")
    func everyOAuthHostIsTrusted() {
        #expect(!BackendOverrides.oauthConfigs.isEmpty)
        for (backend, cfg) in BackendOverrides.oauthConfigs {
            let authCat = GlassEngine.classify(host: cfg.authURL.host)
            let tokenCat = GlassEngine.classify(host: cfg.tokenURL.host)
            // De confiance = .provider, ou .apple pour les backends Apple
            // (iclouddrive → appleid.apple.com). Jamais « maison ».
            #expect(authCat == .provider || authCat == .apple,
                    "authURL de \(backend) devrait être de confiance (\(cfg.authURL.host ?? "nil") → \(authCat))")
            #expect(tokenCat == .provider || tokenCat == .apple,
                    "tokenURL de \(backend) devrait être de confiance (\(cfg.tokenURL.host ?? "nil") → \(tokenCat))")
            #expect(authCat != .home)
            #expect(tokenCat != .home)
        }
    }

    @Test("providerHosts couvre les hosts Google/Microsoft/Dropbox connus")
    func providerHostsCoverage() {
        #expect(GlassEngine.providerHosts.contains("accounts.google.com"))
        #expect(GlassEngine.providerHosts.contains("oauth2.googleapis.com"))
        #expect(GlassEngine.providerHosts.contains("api.dropboxapi.com"))
    }

    @Test("declaredAllowlist : loopback + Apple + tous les hosts provider, aucun .home")
    func declaredAllowlist() {
        let list = GlassEngine.declaredAllowlist()
        #expect(list.contains { $0.category == .loopback })
        #expect(list.contains { $0.category == .apple })
        #expect(list.contains { $0.category == .provider })
        // Aucune entrée déclarée ne doit être de catégorie maison.
        #expect(!list.contains { $0.category == .home })
        // Chaque host provider de la config apparaît dans l'allowlist.
        let listedHosts = Set(list.map { $0.host })
        for host in GlassEngine.providerHosts {
            #expect(listedHosts.contains(host), "host provider manquant dans l'allowlist : \(host)")
        }
    }
}

// MARK: - Denylists

@Suite("GlassEngine — denylists")
struct GlassEngineDenylistTests {

    @Test("isHomeHost repère les fragments maison, pas les fournisseurs")
    func isHomeHost() {
        #expect(GlassEngine.isHomeHost("rclone.rougetet.com"))
        #expect(GlassEngine.isHomeHost("proj.supabase.co"))
        #expect(GlassEngine.isHomeHost("api.vercel.app"))
        #expect(!GlassEngine.isHomeHost("accounts.google.com"))
        #expect(!GlassEngine.isHomeHost("127.0.0.1"))
        #expect(!GlassEngine.isHomeHost(nil))
    }

    @Test("Les denylists de référence ne sont pas vides")
    func denylistsNonEmpty() {
        #expect(GlassEngine.homeDenylistHostFragments.contains("rougetet.com"))
        #expect(GlassEngine.telemetrySymbolDenylist.contains("Sentry"))
        #expect(GlassEngine.telemetrySymbolDenylist.contains("Crashlytics"))
    }
}

// MARK: - Verdict

@Suite("GlassEngine — verdict()")
struct GlassEngineVerdictTests {

    private func event(_ cat: EgressCategory) -> EgressEvent {
        EgressEvent(host: "h", category: cat, purpose: "p", date: Date(timeIntervalSince1970: 0))
    }

    @Test("Aucun événement → propre, 0 appel maison")
    func empty() {
        let v = GlassEngine.verdict(events: [])
        #expect(v.homeCallCount == 0)
        #expect(v.isClean)
    }

    @Test("Comptage par catégorie et isolation des appels maison")
    func counting() {
        let events = [
            event(.loopback), event(.loopback),
            event(.provider),
            event(.apple),
            event(.home), event(.home), event(.home)
        ]
        let v = GlassEngine.verdict(events: events)
        #expect(v.homeCallCount == 3)
        #expect(v.isClean == false)
        #expect(v.countsByCategory[.loopback] == 2)
        #expect(v.countsByCategory[.provider] == 1)
        #expect(v.countsByCategory[.apple] == 1)
        #expect(v.countsByCategory[.home] == 3)
    }
}

// MARK: - Bus passif

@Suite("GlassEngineMonitor — bus passif")
@MainActor
struct GlassEngineMonitorTests {

    @Test("ingest classe, compte et alimente le verdict")
    func ingest() {
        let m = GlassEngineMonitor.shared
        m.clear()
        m.ingest(host: "127.0.0.1", purpose: "pont", date: Date(timeIntervalSince1970: 0))
        m.ingest(host: "accounts.google.com", purpose: "oauth", date: Date(timeIntervalSince1970: 1))
        m.ingest(host: "rclone.rougetet.com", purpose: "??", date: Date(timeIntervalSince1970: 2))

        #expect(m.events.count == 3)
        #expect(m.countsByCategory[.loopback] == 1)
        #expect(m.countsByCategory[.provider] == 1)
        #expect(m.verdict.homeCallCount == 1)
        #expect(m.verdict.isClean == false)

        m.clear()
        #expect(m.events.isEmpty)
        #expect(m.verdict.homeCallCount == 0)
    }

    @Test("host vide affiché comme tiret, classé .home")
    func emptyHost() {
        let m = GlassEngineMonitor.shared
        m.clear()
        m.ingest(host: nil, purpose: "x", date: Date(timeIntervalSince1970: 0))
        #expect(m.events.first?.host == "—")
        #expect(m.events.first?.category == .home)
        m.clear()
    }
}
