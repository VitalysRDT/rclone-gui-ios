//
//  RemoteMovePlanTests.swift
//  Rclone GUITests
//
//  Aiguillage fichier/dossier des opérations move & rename.
//
//  Bug d'origine (issue #142) : renommer un dossier échouait avec
//  « is a directory not a file ». `renameAsync` appelait systématiquement
//  `operations/movefile`, dont le `NewObject` côté rclone renvoie
//  `fs.ErrorIsDir` dès que le chemin désigne un dossier. Les remotes de type
//  crypt rendaient le bug visible parce qu'ils relaient tel quel l'erreur du
//  backend enveloppé, là où d'autres backends la diluent en « not found ».
//
//  Le correctif centralise la décision dans `RemoteMovePlan`, seul endroit
//  qui choisit entre `operations/movefile` (racine fs + chemin relatif) et
//  `sync/move` (fs complets des deux côtés). Ces tests verrouillent ce choix
//  ET la forme exacte des chaînes fs, les deux API rclone n'ayant PAS le même
//  découpage.
//

import Foundation
import Testing
@testable import Rclone_GUI

@Suite("RemoteMovePlan — aiguillage fichier/dossier des move & rename")
struct RemoteMovePlanTests {

    // MARK: - Non-régression du bug #142

    @Test("RÉGRESSION #142 : renommer un dossier n'utilise jamais operations/movefile")
    func directoryRenameNeverUsesMoveFile() {
        // Le scénario exact du rapport : un dossier sur un remote crypt.
        let plan = RemoteMovePlan.make(
            srcRemote: "crypt",
            srcPath: "Documents/Photos",
            dstRemote: "crypt",
            dstPath: "Documents/Images",
            isDirectory: true
        )

        // Le cas .file déclencherait « is a directory not a file ».
        #expect(plan == .directory(srcFs: "crypt:Documents/Photos", dstFs: "crypt:Documents/Images"))
        if case .file = plan {
            Issue.record("Un dossier a été routé vers operations/movefile — bug #142 réintroduit.")
        }
    }

    @Test("RÉGRESSION #142 : le nom du remote n'influence pas l'aiguillage")
    func routingIgnoresBackendType() {
        // crypt n'était qu'un révélateur : la décision ne dépend QUE du type
        // d'entrée. Un dossier doit passer par sync/move sur tout backend.
        for remote in ["crypt", "drive", "s3", "local", "onedrive"] {
            let plan = RemoteMovePlan.make(
                srcRemote: remote,
                srcPath: "a/b",
                dstRemote: remote,
                dstPath: "a/c",
                isDirectory: true
            )
            #expect(plan == .directory(srcFs: "\(remote):a/b", dstFs: "\(remote):a/c"))
        }
    }

    // MARK: - Forme des chaînes fs (les deux API rclone diffèrent)

    @Test("Fichier → operations/movefile : racine fs + chemin relatif")
    func fileUsesFsRootPlusRelativePath() {
        let plan = RemoteMovePlan.make(
            srcRemote: "drive",
            srcPath: "Docs/note.txt",
            dstRemote: "drive",
            dstPath: "Docs/notes.txt",
            isDirectory: false
        )
        // srcFs s'arrête au « : » — le chemin voyage dans srcRemote/dstRemote.
        #expect(plan == .file(
            srcFs: "drive:",
            srcPath: "Docs/note.txt",
            dstFs: "drive:",
            dstPath: "Docs/notes.txt"
        ))
    }

    @Test("Dossier → sync/move : fs complets des deux côtés")
    func directoryUsesCompleteFsStrings() {
        let plan = RemoteMovePlan.make(
            srcRemote: "drive",
            srcPath: "Docs/2026",
            dstRemote: "drive",
            dstPath: "Archive/2026",
            isDirectory: true
        )
        #expect(plan == .directory(srcFs: "drive:Docs/2026", dstFs: "drive:Archive/2026"))
    }

    // MARK: - Cas limites

    @Test("Renommage à la racine du remote (chemin sans dossier parent)")
    func renameAtRemoteRoot() {
        let dir = RemoteMovePlan.make(
            srcRemote: "crypt", srcPath: "Photos",
            dstRemote: "crypt", dstPath: "Images",
            isDirectory: true
        )
        #expect(dir == .directory(srcFs: "crypt:Photos", dstFs: "crypt:Images"))

        let file = RemoteMovePlan.make(
            srcRemote: "crypt", srcPath: "note.txt",
            dstRemote: "crypt", dstPath: "notes.txt",
            isDirectory: false
        )
        #expect(file == .file(srcFs: "crypt:", srcPath: "note.txt", dstFs: "crypt:", dstPath: "notes.txt"))
    }

    @Test("Déplacement inter-remotes : chaque côté garde son propre remote")
    func crossRemoteMoveKeepsBothRemotes() {
        let dir = RemoteMovePlan.make(
            srcRemote: "crypt", srcPath: "Docs/2026",
            dstRemote: "drive", dstPath: "Backup/2026",
            isDirectory: true
        )
        #expect(dir == .directory(srcFs: "crypt:Docs/2026", dstFs: "drive:Backup/2026"))

        let file = RemoteMovePlan.make(
            srcRemote: "crypt", srcPath: "Docs/a.txt",
            dstRemote: "drive", dstPath: "Backup/a.txt",
            isDirectory: false
        )
        #expect(file == .file(srcFs: "crypt:", srcPath: "Docs/a.txt", dstFs: "drive:", dstPath: "Backup/a.txt"))
    }

    @Test("Noms contenant espaces et accents : aucun échappement parasite")
    func preservesExoticNamesVerbatim() {
        let plan = RemoteMovePlan.make(
            srcRemote: "crypt",
            srcPath: "Mes Documents/Été 2026",
            dstRemote: "crypt",
            dstPath: "Mes Documents/Vacances Été",
            isDirectory: true
        )
        // rclone reçoit ces chaînes en JSON : elles doivent rester intactes.
        #expect(plan == .directory(
            srcFs: "crypt:Mes Documents/Été 2026",
            dstFs: "crypt:Mes Documents/Vacances Été"
        ))
    }

    @Test("Le type d'entrée est le SEUL discriminant")
    func isDirectoryIsTheOnlyDiscriminator() {
        // Mêmes opérandes, seul isDirectory change → deux formes distinctes.
        let asFile = RemoteMovePlan.make(
            srcRemote: "r", srcPath: "x/y", dstRemote: "r", dstPath: "x/z", isDirectory: false)
        let asDir = RemoteMovePlan.make(
            srcRemote: "r", srcPath: "x/y", dstRemote: "r", dstPath: "x/z", isDirectory: true)
        #expect(asFile != asDir)
    }
}
