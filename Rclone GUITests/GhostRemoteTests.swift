//
//  GhostRemoteTests.swift
//  Rclone GUITests
//
//  Garde-fous pour les remotes « fantômes » remontés en 2.1 : un remote visible
//  dans la liste, mais ni modifiable (« Impossible de charger le remote ») ni
//  supprimable (aucun effet, aucune erreur).
//
//  Cause — deux sources de vérité divergentes :
//
//    • la LISTE vient du moteur rclone (config/listremotes → rclone.conf
//      runtime, dans Caches/) ;
//    • l'ÉDITION et la SUPPRESSION lisaient le seul store chiffré.
//
//  Le wizard écrit la section via config/create dès l'étape « Tester » et ne la
//  re-chiffre dans le store qu'à la finalisation. Un remote abandonné après un
//  test de connexion raté (SMB injoignable, par ex.) n'existait donc que côté
//  moteur : l'édition ne le trouvait pas, et la suppression retirait une
//  section absente puis rendait la main sans erreur.
//
//  Les invariants vérifiés ici :
//    1. retirer une section absente est un no-op — la suppression ne peut donc
//       PAS reposer sur le seul store (c'est la cause racine, en dur) ;
//    2. deleteRemote passe aussi par le moteur (config/delete) et VÉRIFIE le
//       listing derrière, au lieu de sortir en silence ;
//    3. remoteConfig(named:) retombe sur config/dump quand le store n'a pas la
//       section ;
//    4. le wizard ne peut plus être fermé au doigt tant qu'une section
//       pré-créée n'est pas nettoyée ;
//    5. un échec de suppression n'efface plus la liste des remotes.
//
//  Les points 2 à 5 vivent dans le câblage (appels RPC, modificateurs SwiftUI)
//  qu'aucun helper pur n'expose : ils sont vérifiés en lisant le source, comme
//  DestructiveDialogCaptureTests.
//

import Foundation
import Testing
@testable import Rclone_GUI

// MARK: - Lecture de source

/// Racine du dépôt, déduite du chemin de ce fichier de test.
private var repoRoot: URL {
    URL(fileURLWithPath: #filePath)      // …/Rclone GUITests/GhostRemoteTests.swift
        .deletingLastPathComponent()     // …/Rclone GUITests
        .deletingLastPathComponent()     // …/
}

/// Lit un source Swift **débarrassé de ses commentaires** : on vérifie le code,
/// pas la prose. Sans ça les commentaires qui documentent ce correctif — ils
/// citent `config/delete`, `loadState = .failed`… — feraient passer les
/// assertions positives à tort et échouer les négatives.
private func source(_ relativePath: String) throws -> String {
    let raw = try String(contentsOf: repoRoot.appending(path: relativePath), encoding: .utf8)
    return stripComments(raw)
}

/// Retire les commentaires `//` de fin de ligne et les blocs `/* … */`.
/// Volontairement simple : suffisant pour ces sources (pas de `//` en littéral).
private func stripComments(_ source: String) -> String {
    var out = ""
    var inBlock = false
    for line in source.split(separator: "\n", omittingEmptySubsequences: false) {
        var text = String(line)
        if inBlock {
            guard let end = text.range(of: "*/") else { continue }
            text = String(text[end.upperBound...])
            inBlock = false
        }
        while let start = text.range(of: "/*") {
            if let end = text.range(of: "*/", range: start.upperBound..<text.endIndex) {
                text.replaceSubrange(start.lowerBound..<end.upperBound, with: "")
            } else {
                text = String(text[..<start.lowerBound])
                inBlock = true
            }
        }
        if let comment = text.range(of: "//") {
            text = String(text[..<comment.lowerBound])
        }
        out += text + "\n"
    }
    return out
}

/// Extrait le corps d'une fonction à partir de sa signature, en équilibrant les
/// accolades. Évite qu'un test passe grâce à du code situé ailleurs dans le
/// fichier.
private func functionBody(_ source: String, startingWith signature: String) throws -> String {
    guard let start = source.range(of: signature) else {
        throw ExtractionError.signatureNotFound(signature)
    }
    guard let open = source[start.upperBound...].firstIndex(of: "{") else {
        throw ExtractionError.bodyNotFound(signature)
    }
    var depth = 0
    var body = ""
    for character in source[open...] {
        if character == "{" { depth += 1 }
        if depth > 0 { body.append(character) }
        if character == "}" {
            depth -= 1
            if depth == 0 { return body }
        }
    }
    throw ExtractionError.bodyNotFound(signature)
}

private enum ExtractionError: Error {
    case signatureNotFound(String)
    case bodyNotFound(String)
}

// MARK: - 1. Cause racine : le store seul ne suffit pas

@Suite("Remotes fantômes — divergence store / moteur")
struct GhostRemoteDivergenceTests {

    @Test("Retirer une section absente du store est un no-op")
    func removingAbsentSectionIsNoop() {
        // Le store ne connaît que `drive` : le remote SMB a été écrit par
        // config/create dans le rclone.conf runtime et jamais re-chiffré.
        let store = """
        [drive]
        type = drive
        scope = drive
        """

        let updated = RcloneConfigEditor.configText(store, removingSectionNamed: "smb-nas")

        // Le texte est inchangé — d'où l'absence totale d'effet perçue par
        // l'utilisateur si la suppression s'arrête là.
        #expect(updated == store)
        #expect(RcloneConfigEditor.sectionNames(in: updated) == ["drive"])
    }

    @Test("Une section présente est bien retirée avec tout son corps")
    func removesSectionAndBody() {
        let store = """
        [drive]
        type = drive

        [smb-nas]
        type = smb
        host = 192.168.1.20
        user = lucas

        [s3]
        type = s3
        """

        let updated = RcloneConfigEditor.configText(store, removingSectionNamed: "smb-nas")

        #expect(RcloneConfigEditor.sectionNames(in: updated) == ["drive", "s3"])
        #expect(!updated.contains("192.168.1.20"))
        #expect(!updated.contains("user = lucas"))
        #expect(updated.contains("[s3]"))
    }

    @Test("Le snapshot moteur sépare le type des options éditables")
    func snapshotFromDumpSection() {
        let snapshot = RcloneConfigEditor.snapshot(
            fromDumpSection: [
                "type": "smb",
                "host": "192.168.1.20",
                "user": "lucas",
                "pass": "obscured",
            ],
            named: "smb-nas"
        )

        #expect(snapshot.name == "smb-nas")
        #expect(snapshot.type == "smb")
        #expect(snapshot.options["host"] == "192.168.1.20")
        #expect(snapshot.options["user"] == "lucas")
        // `type` ne doit jamais réapparaître comme option de formulaire.
        #expect(snapshot.options["type"] == nil)
    }

    @Test("Une section sans type reste exploitable")
    func snapshotWithoutType() {
        let snapshot = RcloneConfigEditor.snapshot(
            fromDumpSection: ["host": "nas.local"],
            named: "orphelin"
        )

        #expect(snapshot.type == "unknown")
        #expect(snapshot.options["host"] == "nas.local")
    }

    @Test("L'échec de suppression porte un message actionnable")
    func deletionFailureIsDescribed() {
        let message = RcloneConfigEditor.ConfigError.deletionFailed("smb-nas").errorDescription
        #expect(message?.contains("smb-nas") == true)
        #expect(message?.isEmpty == false)
    }
}

// MARK: - 2 à 5. Câblage

@Suite("Remotes fantômes — câblage")
struct GhostRemoteWiringTests {

    private static let editorPath = "Rclone GUI/Services/RcloneConfigEditor.swift"

    @Test("deleteRemote supprime aussi côté moteur")
    func deleteAlsoHitsEngine() throws {
        let body = try functionBody(
            source(Self.editorPath),
            startingWith: "static func deleteRemote(name: String)"
        )

        // Sans ça, un remote qui n'existe que dans le rclone.conf runtime
        // survit à sa propre suppression.
        #expect(body.contains("config/delete"))
    }

    @Test("deleteRemote vérifie le résultat au lieu de sortir en silence")
    func deleteVerifiesOutcome() throws {
        let body = try functionBody(
            source(Self.editorPath),
            startingWith: "static func deleteRemote(name: String)"
        )

        // Le remote doit avoir disparu du listing, sinon on lève.
        #expect(body.contains("listRemoteNames"))
        #expect(body.contains("deletionFailed"))

        // Le store reste mis à jour, et le moteur rechargé derrière — l'ancien
        // code sortait avant ces deux étapes quand aucun store n'existait.
        #expect(body.contains("ConfigStore.shared.save"))
        #expect(body.contains("refreshRuntimeAndNotify"))
    }

    @Test("L'édition retombe sur le moteur quand le store n'a pas la section")
    func editFallsBackToEngine() throws {
        let body = try functionBody(
            source(Self.editorPath),
            startingWith: "static func remoteConfig(named name: String)"
        )

        #expect(body.contains("engineRemoteConfig"))

        // Le `guard let data = … else { return nil }` d'origine court-circuitait
        // tout le reste dès que le store était absent.
        #expect(!body.contains("guard let data = try await ConfigStore.shared.load() else { return nil }"))
    }

    @Test("Le wizard ne peut pas être fermé au doigt sur une section pré-créée")
    func wizardBlocksInteractiveDismiss() throws {
        let wizard = try source("Rclone GUI/Views/Settings/AddRemote/AddRemoteWizard.swift")

        // Le swipe-down ferme la feuille sans passer par handleCancel(), donc
        // sans le config/delete de nettoyage : c'est ce qui fabriquait les
        // sections orphelines.
        #expect(wizard.contains(".interactiveDismissDisabled(state.remoteWasPreCreated)"))
    }

    @Test("Un échec de suppression n'efface pas la liste des remotes")
    func failedDeletionKeepsList() throws {
        let body = try functionBody(
            source("Rclone GUI/Views/Files/FilesRootView.swift"),
            startingWith: "private func performDelete(_ remote: RemoteSummaryDTO)"
        )

        // `loadState = .failed` remplaçait tous les remotes par un écran
        // « Erreur de chargement » alors que la liste était bien chargée.
        #expect(!body.contains("loadState = .failed"))
        #expect(body.contains("actionError"))
    }
}
