//
//  FileProviderRelayTests.swift
//  Rclone GUITests
//
//  Tests du relais de listing entre l'extension FileProvider et l'app
//  principale. Le bug d'origine : en ouvrant un dossier jamais visité depuis
//  Fichiers.app, l'extension déléguait le listing à l'app principale et pollait
//  60 s. Or Rclone GUI est suspendue dès que Fichiers est au premier plan, et
//  une notification Darwin ne réveille pas un process suspendu — personne ne
//  répondait. Fichiers restait sur un spinner jusqu'à ce que l'utilisateur
//  bascule manuellement sur l'app, ce qui débloquait le relais.
//
//  Le correctif ajoute un accusé de réception (`.status`) écrit par l'app dès
//  la prise en charge, et un `activationTimeout` court côté extension : sans
//  ack, on tranche « app inactive » et on liste depuis l'extension.
//

import Foundation
import Testing
@testable import Rclone_GUI

@Suite("FileProvider — décision d'attente du relais de listing")
struct FileProviderRelayPollDecisionTests {

    /// t0 fixe : toutes les dates des tests en dérivent, aucun appel à Date().
    private let startedAt = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let activationTimeout: TimeInterval = 1.5

    private func decide(
        manifestMTime: Date? = nil,
        errorMessage: String? = nil,
        sawAck: Bool = false,
        elapsed: TimeInterval
    ) -> FileProviderBridge.RelayPollDecision {
        FileProviderBridge.relayPollDecision(
            manifestMTime: manifestMTime,
            errorMessage: errorMessage,
            sawAck: sawAck,
            startedAt: startedAt,
            now: startedAt.addingTimeInterval(elapsed),
            activationTimeout: activationTimeout
        )
    }

    // MARK: - Non-régression du bug

    @Test("RÉGRESSION : app suspendue (aucun ack) → appInactive avant le timeout complet")
    func inactiveAppIsDetectedEarly() {
        // Le scénario exact du bug : rien n'arrive jamais côté App Group.
        #expect(decide(elapsed: 1.6) == .appInactive)
        // Et surtout : bien avant les 60 s de timeout du relais.
        #expect(decide(elapsed: 59) == .appInactive)
    }

    @Test("Avant activationTimeout, on laisse sa chance à l'app principale")
    func waitsUntilActivationTimeout() {
        #expect(decide(elapsed: 0) == .keepWaiting(sawAck: false))
        #expect(decide(elapsed: 1.4) == .keepWaiting(sawAck: false))
    }

    @Test("Pile sur activationTimeout on attend encore : seul un dépassement tranche")
    func boundaryIsExclusive() {
        #expect(decide(elapsed: activationTimeout) == .keepWaiting(sawAck: false))
    }

    // MARK: - App active

    @Test("Ack reçu : on attend le manifest sans jamais conclure à l'inactivité")
    func ackSuppressesInactivity() {
        #expect(decide(sawAck: true, elapsed: 2) == .keepWaiting(sawAck: true))
        #expect(decide(sawAck: true, elapsed: 59) == .keepWaiting(sawAck: true))
    }

    @Test("Manifest réécrit après le début de la requête → prêt")
    func freshManifestWins() {
        let fresh = startedAt.addingTimeInterval(0.5)
        #expect(decide(manifestMTime: fresh, sawAck: true, elapsed: 0.6) == .manifestReady)
    }

    @Test("Un manifest antérieur à la requête ne compte pas comme une réponse")
    func staleManifestIsIgnored() {
        let stale = startedAt.addingTimeInterval(-30)
        #expect(decide(manifestMTime: stale, sawAck: true, elapsed: 1) == .keepWaiting(sawAck: true))
    }

    /// Course réelle : l'app répond en moins d'un tour de boucle (200 ms) et son
    /// `defer` a déjà effacé l'ack. Sans la priorité au manifest, on conclurait
    /// à tort « app inactive » et on relisterait pour rien.
    @Test("Manifest prêt sans ack visible → prêt, pas inactif")
    func manifestBeatsMissingAck() {
        let fresh = startedAt.addingTimeInterval(0.1)
        #expect(decide(manifestMTime: fresh, sawAck: false, elapsed: 5) == .manifestReady)
    }

    @Test("Échec signalé par l'app principale → propagé tel quel")
    func errorIsPropagated() {
        #expect(decide(errorMessage: "quota exceeded", sawAck: true, elapsed: 1) == .failed("quota exceeded"))
    }

    @Test("Une erreur ne masque pas un manifest déjà écrit")
    func manifestTakesPrecedenceOverError() {
        let fresh = startedAt.addingTimeInterval(0.5)
        #expect(decide(manifestMTime: fresh, errorMessage: "boom", elapsed: 1) == .manifestReady)
    }

    @Test("Une erreur arrivée avant activationTimeout prime sur l'inactivité")
    func errorBeatsInactivity() {
        #expect(decide(errorMessage: "boom", sawAck: false, elapsed: 10) == .failed("boom"))
    }
}

@Suite("FileProvider — contrat IPC entre extension et app principale")
struct FileProviderIPCContractTests {

    /// L'extension attend l'ack à `pendingFetchStatusURL(requestID:)`, l'app
    /// l'écrit à `<pending>.json` + extension `status`. Si les deux chemins
    /// divergent, l'ack n'est jamais vu et le spinner revient — en silence.
    @Test("Les deux côtés désignent le même fichier d'accusé de réception")
    func ackPathsMatch() {
        let requestID = "F1B0C0DE-0000-4000-8000-00000000ABCD"

        let extensionSide = FileProviderBridge.pendingFetchStatusURL(requestID: requestID)
        // Reproduit le calcul de FileProviderFetchService : le pending est
        // découvert par scan du répertoire, puis suffixé.
        let appSide = AppGroup.pendingFetchesDir
            .appending(path: requestID)
            .appendingPathExtension("json")
            .appendingPathExtension("status")

        #expect(extensionSide.standardizedFileURL == appSide.standardizedFileURL)
        #expect(extensionSide.lastPathComponent == "\(requestID).json.status")
    }

    @Test("Les deux côtés désignent le même répertoire de requêtes")
    func pendingDirectoriesMatch() {
        #expect(
            FileProviderBridge.pendingFetchesDir.standardizedFileURL
                == AppGroup.pendingFetchesDir.standardizedFileURL
        )
    }

    @Test("Le statut écrit par l'app est décodable par l'extension")
    func statusDecodesAcrossTargets() throws {
        let appStatus = AppGroupFetchStatus(
            stage: "running",
            jobID: nil,
            bytesTransferred: 0,
            bytesTotal: 0,
            updatedAt: Date(timeIntervalSinceReferenceDate: 800_000_000),
            message: nil
        )
        let data = try JSONEncoder().encode(appStatus)
        let decoded = try JSONDecoder().decode(FetchStatus.self, from: data)

        #expect(decoded.stage == "running")
        #expect(decoded.bytesTotal == 0)
        #expect(decoded.updatedAt == appStatus.updatedAt)
    }
}

@Suite("FileProvider — manifest de dossier écrit par l'extension")
struct FileProviderFolderManifestTests {

    private func entry(name: String, isDirectory: Bool = false) -> FolderManifestEntry {
        FolderManifestEntry(
            path: "Docs/\(name)",
            name: name,
            isDirectory: isDirectory,
            size: isDirectory ? 0 : 4_096,
            modTime: Date(timeIntervalSinceReferenceDate: 799_000_000),
            mimeType: isDirectory ? nil : "application/pdf"
        )
    }

    /// L'extension écrit désormais le cache elle-même quand elle liste en direct.
    /// Le format doit rester lisible par le chemin de lecture existant, sinon le
    /// dossier réapparaîtrait vide au passage suivant.
    @Test("Round-trip du manifest écrit en repli direct")
    func manifestRoundTrips() throws {
        let entries = [entry(name: "Rapport.pdf"), entry(name: "Archives", isDirectory: true)]

        let data = try JSONEncoder().encode(entries)
        let decoded = try JSONDecoder().decode([FolderManifestEntry].self, from: data)

        #expect(decoded.count == 2)
        #expect(decoded[0].name == "Rapport.pdf")
        #expect(decoded[0].path == "Docs/Rapport.pdf")
        #expect(decoded[0].isDirectory == false)
        #expect(decoded[0].size == 4_096)
        #expect(decoded[0].mimeType == "application/pdf")
        #expect(decoded[1].isDirectory == true)
        #expect(decoded[1].mimeType == nil)
        #expect(decoded[0].modTime == entries[0].modTime)
    }

    @Test("La clé de fichier manifest est stable et sans séparateur de chemin")
    func manifestKeyIsFilesystemSafe() {
        let url = FileProviderBridge.folderManifestURL(remote: "r2 vitalys", path: "Docs/Sous-dossier")
        let component = url.lastPathComponent

        #expect(component.hasSuffix(".json"))
        // Le nom encode remote+chemin : aucun "/" ne doit survivre, sinon
        // l'écriture viserait un sous-répertoire inexistant.
        #expect(!component.dropLast(5).contains("/"))
        #expect(
            url.deletingLastPathComponent().standardizedFileURL
                == FileProviderBridge.folderManifestsDir.standardizedFileURL
        )
    }

    @Test("Deux dossiers distincts n'écrivent pas dans le même manifest")
    func manifestKeysAreDistinct() {
        let a = FileProviderBridge.folderManifestURL(remote: "drive", path: "Docs")
        let b = FileProviderBridge.folderManifestURL(remote: "drive", path: "Photos")
        let c = FileProviderBridge.folderManifestURL(remote: "autre", path: "Docs")

        #expect(a != b)
        #expect(a != c)
    }
}
