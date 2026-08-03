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
import FileProvider
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
    @MainActor
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

    @Test("Le staging d'upload reste dans l'App Group et conserve seulement l'extension")
    func uploadStagingURLIsPrivateAndStable() {
        let url = FileProviderBridge.uploadStagingURL(
            requestID: "F1B0C0DE-0000-4000-8000-00000000ABCD",
            filename: "private-report.final.pdf"
        )

        #expect(url.deletingLastPathComponent().standardizedFileURL == FileProviderBridge.uploadStagingDir.standardizedFileURL)
        #expect(url.lastPathComponent == "F1B0C0DE-0000-4000-8000-00000000ABCD.pdf")
        #expect(!url.lastPathComponent.contains("private-report"))
    }

    @Test("Un manifest récent est servi, un ancien doit être rafraîchi")
    func manifestFreshnessIsExplicit() {
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

        #expect(FileProviderBridge.folderManifestIsFresh(
            modificationDate: now.addingTimeInterval(-30),
            now: now,
            maximumAge: 60
        ))
        #expect(!FileProviderBridge.folderManifestIsFresh(
            modificationDate: now.addingTimeInterval(-61),
            now: now,
            maximumAge: 60
        ))
        #expect(!FileProviderBridge.folderManifestIsFresh(
            modificationDate: nil,
            now: now,
            maximumAge: 60
        ))
    }

    @Test("Un directory not found 404 devient noSuchItem, pas dossier vide")
    func missingDirectoryMapsToNoSuchItem() {
        let message = "rclone error 404 on 'operations/list': directory not found"
        #expect(
            FileProviderBridge.relayFileProviderErrorCode(for: message)
                == NSFileProviderError.noSuchItem.rawValue
        )
        #expect(
            FileProviderBridge.relayFileProviderErrorCode(for: "quota exceeded")
                == NSFileProviderError.serverUnreachable.rawValue
        )
    }
}

@Suite("FileProvider — politique de file IPC")
struct FileProviderPendingRequestPolicyTests {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func pending(
        id: String,
        kind: String?,
        age: TimeInterval
    ) -> AppGroupPendingFetch {
        AppGroupPendingFetch(
            requestID: id,
            remote: "crypt",
            path: "folder-\(id)",
            destPath: "/tmp/\(id)",
            createdAt: now.addingTimeInterval(-age),
            kind: kind
        )
    }

    @Test("Les anciens listings expirent avant de bloquer un nouveau boot")
    func oldListingsExpire() {
        let backlog = (0..<192).map {
            pending(id: "old-\($0)", kind: "list", age: 10 * 60)
        }

        #expect(backlog.allSatisfy {
            FileProviderPendingRequestPolicy.isExpired($0, now: now)
        })
        #expect(!FileProviderPendingRequestPolicy.isExpired(
            pending(id: "live", kind: "list", age: 30),
            now: now
        ))
    }

    @Test("Un téléchargement vivant garde son contrat de six heures")
    func fullDownloadUsesItsOwnLifetime() {
        #expect(!FileProviderPendingRequestPolicy.isExpired(
            pending(id: "download-live", kind: "full", age: 5 * 60 * 60),
            now: now
        ))
        #expect(FileProviderPendingRequestPolicy.isExpired(
            pending(id: "download-orphan", kind: "full", age: 24 * 60 * 60),
            now: now
        ))
        #expect(
            FileProviderPendingRequestPolicy.lifetime(for: "full")
                > FileProviderPendingRequestPolicy.lifetime(for: "list")
        )
    }

    @Test("Le listing interactif récent passe avant un download")
    func interactiveWorkHasPriority() {
        let list = pending(id: "list", kind: "list", age: 10)
        let download = pending(id: "download", kind: "full", age: 1)

        #expect(FileProviderPendingRequestPolicy.shouldProcessBefore(list, download))
        #expect(!FileProviderPendingRequestPolicy.shouldProcessBefore(download, list))
    }

    @Test("Les doublons d'un dossier partagent une clé réseau, pas leur requestID")
    @MainActor
    func duplicateListingsShareOneNetworkKey() {
        let first = pending(id: "waiter-a", kind: "list", age: 15)
        let second = pending(id: "waiter-b", kind: "list", age: 5)
        let otherPath = AppGroupPendingFetch(
            requestID: "waiter-c",
            remote: first.remote,
            path: "another-folder",
            destPath: "/tmp/waiter-c",
            createdAt: now,
            kind: "list"
        )

        #expect(FileProviderPendingListKey(first) == FileProviderPendingListKey(second))
        #expect(FileProviderPendingListKey(first) != FileProviderPendingListKey(otherPath))
        #expect(FileProviderPendingListKey(pending(id: "download", kind: "full", age: 0)) == nil)
    }
}

@Suite("RemoteService — classification des listings introuvables")
struct RemoteServiceMissingDirectoryTests {
    @Test("Seul le 404 directory not found de operations/list est retentable")
    func typedErrorClassification() {
        #expect(RemoteService.isDirectoryNotFoundListError(
            RcloneError.rcloneError(
                code: 404,
                method: "operations/list",
                message: "error in ListJSON: directory not found"
            )
        ))
        #expect(!RemoteService.isDirectoryNotFoundListError(
            RcloneError.rcloneError(
                code: 500,
                method: "operations/list",
                message: "directory not found"
            )
        ))
        #expect(!RemoteService.isDirectoryNotFoundListError(
            RcloneError.rcloneError(
                code: 404,
                method: "operations/stat",
                message: "directory not found"
            )
        ))
    }
}

@Suite("Support — export File Provider sans métadonnées privées")
struct FileProviderSupportLogTests {
    @Test("L'export conserve étape et code mais retire remote, chemin et fichier")
    func providerMessageIsMetadataOnly() {
        let raw = "upload staging failed id=SECRET-ID remote=private-remote path=Family/Taxes/private.pdf domain=NSCocoaErrorDomain code=257"
        let safe = FileProviderManager.supportDiagnosticMessage(raw)

        #expect(safe == "operation=upload stage=failed code=257")
        #expect(!safe.contains("SECRET"))
        #expect(!safe.contains("private"))
        #expect(!safe.contains("Family"))
        #expect(!safe.contains("pdf"))
        #expect(!safe.contains("NSCocoaErrorDomain"))
    }

    @Test("Un payload IPC arbitraire ne peut injecter ni code ni identifiant numérique")
    func providerPayloadCannotInjectNumericMetadata() {
        let raw = "ipc stream error message=https://provider.invalid/callback?code=12345&count=987654&otp=404&token=SECRET"
        let safe = FileProviderManager.supportDiagnosticMessage(raw)

        #expect(safe == "operation=stream stage=failed")
        #expect(!safe.contains("12345"))
        #expect(!safe.contains("987654"))
        #expect(!safe.contains("404"))
        #expect(!safe.contains("SECRET"))
    }

    @Test("L'export support assainit aussi le ring app et ses aperçus de fichiers")
    func appRingEntryIsMetadataOnly() {
        let raw = LogEntry(
            level: .info,
            category: "list",
            message: "operations/list ok remote=secret-vault path=Family/Taxes recurse=false entries=1628 in 30900ms · [passport.pdf, token.txt]",
            supportMessage: "operation=listing stage=completed count=1628 duration_ms=30900 recursive=false"
        )
        let safe = LogService.supportSafeEntry(raw)

        #expect(
            safe.message
                == "operation=listing stage=completed count=1628 duration_ms=30900 recursive=false"
        )
        #expect(!safe.message.contains("secret"))
        #expect(!safe.message.contains("Family"))
        #expect(!safe.message.contains("passport"))
        #expect(!safe.message.contains("token"))
    }

    @Test("Une erreur librclone conserve le niveau sans URL, code privé, token ni chemin")
    func rcloneEntryDropsSensitivePayload() {
        let raw = LogEntry(
            level: .error,
            category: "rclone",
            message: "request https://provider.invalid/upload/cancel?code=123456&token=SECRET failed 404: directory not found"
        )
        let safe = LogService.supportSafeEntry(raw)

        #expect(safe.message == "operation=rclone stage=failed")
        #expect(!safe.message.contains("http"))
        #expect(!safe.message.contains("SECRET"))
        #expect(!safe.message.contains("123456"))
        #expect(!safe.message.contains("upload"))
        #expect(!safe.message.contains("cancel"))
        #expect(!safe.message.contains("token"))
    }

    @Test("Une pseudo-métadonnée non conforme est rejetée en bloc")
    func malformedSupportMetadataFallsBackSafely() {
        let raw = LogEntry(
            level: .error,
            category: "rclone",
            message: "opaque backend payload",
            supportMessage: "operation=rclone stage=failed code=123456&token=SECRET"
        )
        let safe = LogService.supportSafeEntry(raw)

        #expect(safe.message == "operation=rclone stage=failed")
        #expect(!safe.message.contains("123456"))
        #expect(!safe.message.contains("SECRET"))
    }
}
