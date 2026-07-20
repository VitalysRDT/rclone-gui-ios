//
//  DestructiveDialogCaptureTests.swift
//  Rclone GUITests
//
//  Garde-fou de non-régression pour le bug « Supprimer / Corbeille ne fait
//  rien » remonté en 2.0 sur FolderView (aucune suppression, aucun log).
//
//  Cause : le closure d'action du `confirmationDialog` lançait un `Task` qui
//  relisait la cible depuis le `@State private var deleteTarget`. SwiftUI ferme
//  le dialog avant que ce `Task` ne s'exécute, ce qui déclenche le `set:` du
//  binding `isPresented` (`deleteTarget = nil`) ; le `guard let target =
//  deleteTarget` échouait alors en silence — pas d'appel rclone, pas de log,
//  donc un bug invisible côté diagnostic.
//
//  L'invariant : dans un dialog destructif, la cible doit être CAPTURÉE au
//  moment du tap (via `presenting:` ou un `if let` synchrone dans le closure du
//  bouton) et passée en paramètre — jamais relue depuis l'état différé.
//
//  Ce test lit le source (via `#filePath`) car le défaut vit dans le câblage
//  SwiftUI lui-même : aucun helper pur ne peut l'attraper, et les UI tests ne
//  tournent pas dans cette infra.
//

import Foundation
import Testing

/// Racine du dépôt, déduite du chemin de ce fichier de test.
private var repoRoot: URL {
    URL(fileURLWithPath: #filePath)      // …/Rclone GUITests/DestructiveDialogCaptureTests.swift
        .deletingLastPathComponent()     // …/Rclone GUITests
        .deletingLastPathComponent()     // …/
}

/// Lit un source Swift **débarrassé de ses commentaires** : on veut vérifier le
/// code, pas la prose. (Sans ça, un commentaire qui *décrit* le pattern fautif —
/// comme celui qui documente ce correctif dans FolderView — ferait échouer le test.)
private func source(_ relativePath: String) throws -> String {
    let url = repoRoot.appending(path: relativePath)
    let raw = try String(contentsOf: url, encoding: .utf8)
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
                break
            }
        }
        if let lineComment = text.range(of: "//") {
            text = String(text[..<lineComment.lowerBound])
        }
        out += text + "\n"
    }
    return out
}

@Suite("Dialogs destructifs — capture de la cible")
struct DestructiveDialogCaptureTests {

    @Test("FolderView : le dialog de suppression passe sa cible via presenting:")
    func folderViewUsesPresenting() throws {
        let src = try source("Rclone GUI/Views/Folders/FolderView.swift")
        #expect(src.contains("presenting: deleteTarget"),
                "Le confirmationDialog de suppression doit utiliser `presenting: deleteTarget` pour capturer la cible au tap.")
    }

    @Test("FolderView : performDelete reçoit la cible, ne la relit pas depuis le @State")
    func performDeleteTakesTargetAsParameter() throws {
        let src = try source("Rclone GUI/Views/Folders/FolderView.swift")

        // La régression exacte : la cible relue dans le corps async.
        #expect(!src.contains("guard let target = deleteTarget"),
                "performDelete ne doit pas relire `deleteTarget` — il est déjà nil quand le Task s'exécute.")

        // La signature corrigée prend la cible en entrée.
        #expect(src.contains("private func performDelete(_ target: RemoteEntryDTO, permanent: Bool) async"),
                "performDelete doit recevoir la cible en paramètre.")

        // Aucun appel ne doit repasser par la variante sans cible.
        #expect(!src.contains("performDelete(permanent:"),
                "Plus aucun appel ne doit s'appuyer sur l'état différé.")
    }

    @Test("Les écrans de suppression capturent tous leur cible avant le Task")
    func allDestructiveScreensCaptureTarget() throws {
        // Écrans du repo qui suppriment un élément désigné par un @State optionnel.
        // Chacun doit soit utiliser `presenting:`, soit faire un `if let` synchrone
        // dans le closure du bouton (pattern de TrashView).
        let screens = [
            "Rclone GUI/Views/Folders/FolderView.swift",
            "Rclone GUI/Views/Files/FilesRootView.swift",
            "Rclone GUI/Views/Settings/TrashView.swift",
        ]

        for path in screens {
            let src = try source(path)
            let capturesViaPresenting = src.contains("presenting:")
            let capturesSynchronously = src.contains("if let entry = pending")
            #expect(capturesViaPresenting || capturesSynchronously,
                    "\(path) doit capturer la cible du dialog avant de lancer son Task.")
        }
    }
}
