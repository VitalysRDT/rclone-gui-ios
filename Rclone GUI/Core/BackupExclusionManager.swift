//
//  BackupExclusionManager.swift
//  Rclone GUI — Core
//
//  Exclut (ou réintègre) les données de l'app des sauvegardes iCloud / Finder
//  via l'attribut `isExcludedFromBackup` (NSURLIsExcludedFromBackupKey).
//
//  Cibles :
//    - le conteneur App Group : configuration rclone chiffrée, cache de
//      navigation SwiftData, miniatures, coffre-fort, état FileProvider… ;
//    - le dossier Documents de l'app : fichiers téléchargés.
//  Le cache média vit dans Caches, jamais inclus dans une sauvegarde → non
//  concerné. Les identifiants vivent dans le Trousseau (sauvegardé à part).
//
//  Réglage opt-in (défaut : données sauvegardées, pour faciliter la
//  restauration sur un nouvel appareil).
//

import Foundation

public enum BackupExclusionManager {
    /// Clé UserDefaults du toggle. Absente/false ⇒ données incluses au backup.
    public static let defaultsKey = "privacy.excludeFromICloudBackup"

    public static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: defaultsKey)
    }

    /// Données de l'app à marquer/démarquer.
    static var targetURLs: [URL] {
        var urls: [URL] = [AppGroup.containerURL]
        if let documents = try? FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ) {
            urls.append(documents)
        }
        return urls
    }

    /// Applique (`excluded = true`) ou retire (`false`) l'exclusion de backup
    /// sur chaque cible existante. Idempotent — sûr à rappeler à chaque
    /// lancement. Renvoie `false` si au moins une cible a échoué.
    @discardableResult
    public static func apply(excluded: Bool) -> Bool {
        let fileManager = FileManager.default
        var allSucceeded = true

        for url in targetURLs {
            guard fileManager.fileExists(atPath: url.path) else { continue }
            var mutableURL = url
            var values = URLResourceValues()
            values.isExcludedFromBackup = excluded
            do {
                try mutableURL.setResourceValues(values)
            } catch {
                allSucceeded = false
                Task {
                    await LogService.shared.log(
                        .error,
                        category: "backup",
                        message: "isExcludedFromBackup=\(excluded) a échoué pour \(url.lastPathComponent) : \(error.localizedDescription)"
                    )
                }
            }
        }
        return allSucceeded
    }

    /// Ré-affirme l'état persisté au démarrage. N'agit que si l'exclusion est
    /// activée : les nouveaux fichiers créés sous un dossier déjà exclu héritent
    /// de l'exclusion, mais on ré-applique sur la racine par sûreté.
    public static func applyPersistedState() {
        guard isEnabled else { return }
        apply(excluded: true)
    }
}
