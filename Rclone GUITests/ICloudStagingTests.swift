//
//  ICloudStagingTests.swift
//  Rclone GUITests
//
//  Tests du move coordonné staging→destination (optimisation iOS anti-gel
//  iCloud : télécharger en Caches puis publier via NSFileCoordinator).
//

import Foundation
import Testing
@testable import Rclone_GUI

@Suite("TransferQueue — publication coordonnée (staging → destination)")
struct ICloudStagingTests {

    private func tempDir() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("staging-test-\(UUID().uuidString)", isDirectory: true)
    }

    @Test("Déplace le fichier staged vers la destination et supprime la source")
    func movesStagedFileToDestination() throws {
        let fm = FileManager.default
        let root = tempDir()
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let staged = root.appendingPathComponent("staged.bin")
        let payload = Data("bonjour daisychain".utf8)
        try payload.write(to: staged)

        // Destination dans un sous-dossier encore inexistant (créé par le helper).
        let dest = root.appendingPathComponent("sub/dir/final.bin")

        try TransferQueue.publishFileCoordinated(from: staged, to: dest)

        #expect(fm.fileExists(atPath: dest.path))
        #expect(!fm.fileExists(atPath: staged.path))
        #expect(try Data(contentsOf: dest) == payload)
    }

    @Test("Remplace un fichier existant à la destination (.forReplacing)")
    func replacesExistingDestination() throws {
        let fm = FileManager.default
        let root = tempDir()
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let dest = root.appendingPathComponent("final.bin")
        try Data("ancien".utf8).write(to: dest)

        let staged = root.appendingPathComponent("staged.bin")
        let fresh = Data("nouveau contenu".utf8)
        try fresh.write(to: staged)

        try TransferQueue.publishFileCoordinated(from: staged, to: dest)

        #expect(try Data(contentsOf: dest) == fresh)
        #expect(!fm.fileExists(atPath: staged.path))
    }

    @Test("Les chemins iCloud déclenchent le staging, les locaux non")
    func icloudDetectionGatesStaging() {
        // La décision de stager repose sur isICloudDrivePath (déjà testé) —
        // on revérifie le contrat exact utilisé par downloadFolderViaFiles.
        #expect(TransferQueue.isICloudDrivePath(
            "/var/mobile/Library/Mobile Documents/com~apple~CloudDocs/Downloads/x") == true)
        #expect(TransferQueue.isICloudDrivePath(
            "/var/mobile/Containers/Data/Application/A/Documents/x") == false)
    }
}
