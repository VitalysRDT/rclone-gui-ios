import Foundation
import Testing
@testable import Rclone_GUI

@Suite("Crypt — récupération d'un listing faussement vide")
struct EncryptedFolderListingRecoveryTests {

    private func entry(
        path: String,
        isDirectory: Bool = false,
        size: Int64 = 1
    ) -> RemoteEntryDTO {
        RemoteEntryDTO(
            pathInRemote: path,
            name: (path as NSString).lastPathComponent,
            isDirectory: isDirectory,
            size: isDirectory ? 0 : size,
            modTime: Date(timeIntervalSinceReferenceDate: 800_000_000),
            mimeType: isDirectory ? "inode/directory" : "application/octet-stream",
            hashMD5: nil,
            hashSHA1: nil
        )
    }

    @Test("Ne garde que les enfants immédiats du dossier demandé")
    func collapsesRecursiveListingToImmediateChildren() {
        let recursive = [
            entry(path: "Vault/Alpha", isDirectory: true),
            entry(path: "Vault/Alpha/one.txt"),
            entry(path: "Vault/Beta", isDirectory: true),
            entry(path: "Vault/Beta/two.txt"),
            entry(path: "Elsewhere/ignored.txt"),
        ]

        let result = RemoteService.immediateEntries(fromRecursive: recursive, under: "Vault")

        #expect(result.map(\.pathInRemote) == ["Vault/Alpha", "Vault/Beta"])
        #expect(result.allSatisfy { $0.isDirectory })
    }

    @Test("Synthétise le dossier parent si le backend ne renvoie que son descendant")
    func synthesizesMissingImmediateDirectory() {
        let recursive = [entry(path: "Vault/Gamma/Nested/three.txt", size: 42)]

        let result = RemoteService.immediateEntries(fromRecursive: recursive, under: "Vault")

        #expect(result.count == 1)
        #expect(result[0].pathInRemote == "Vault/Gamma")
        #expect(result[0].name == "Gamma")
        #expect(result[0].isDirectory)
        #expect(result[0].size == 0)
    }

    @Test("À la racine, conserve fichiers et dossiers directs sans doublon")
    func handlesRemoteRoot() {
        let recursive = [
            entry(path: "readme.txt", size: 10),
            entry(path: "Photos/2026/image.jpg", size: 20),
            entry(path: "Photos", isDirectory: true),
        ]

        let result = RemoteService.immediateEntries(fromRecursive: recursive, under: "")

        #expect(result.map(\.pathInRemote) == ["readme.txt", "Photos"])
        #expect(result[0].isDirectory == false)
        #expect(result[1].isDirectory)
    }

    @Test("Un listing récursif réellement vide reste vide")
    func acceptsConfirmedEmptyFolder() {
        #expect(RemoteService.immediateEntries(fromRecursive: [], under: "Vault/Empty").isEmpty)
    }
}
