//
//  VaultManager.swift
//  Rclone GUI — Core
//
//  Coffre-fort biométrique par remote. Un remote « mis au coffre » disparaît
//  entièrement de Fichiers.app (l'extension FileProvider le filtre à
//  l'énumération) et ne s'ouvre qu'après une authentification Face ID / Touch ID
//  dans l'app principale, pour une durée limitée (TTL).
//
//  Source de vérité partagée avec l'extension via l'App Group (l'extension ne
//  peut pas lire le store SwiftData) :
//    - <container>/vault/locked-remotes.json : [String]    (remotes protégés)
//    - <container>/vault/unlocks.json        : [name: epoch] (déverrouillages actifs)
//
//  Après chaque mutation, on réécrit le manifest implicite via
//  FileProviderManager.signalRefresh(.rootContainer) pour que Fichiers.app
//  ré-énumère et fasse apparaître / disparaître le remote.
//

import Foundation
import Observation

@MainActor
@Observable
public final class VaultManager {
    public static let shared = VaultManager()

    /// Clé AppStorage de la durée de déverrouillage (minutes). 0 = à chaque accès.
    public static let unlockMinutesKey = "security.vaultUnlockMinutes"
    private static let defaultUnlockMinutes = 15

    /// Remotes actuellement protégés par le coffre-fort.
    public private(set) var lockedRemotes: Set<String> = []

    /// Échéances de déverrouillage en mémoire ET persistées (name → expiration).
    private var unlockExpiry: [String: Date] = [:]

    /// Tâches de re-verrouillage programmées à l'expiration du TTL.
    private var relockTasks: [String: Task<Void, Never>] = [:]

    private init() {
        load()
    }

    // MARK: - Lecture d'état

    /// True si le remote est dans le coffre-fort (protégé par biométrie).
    public func isLocked(_ name: String) -> Bool {
        lockedRemotes.contains(name)
    }

    /// True si le remote est actuellement déverrouillé (et non expiré).
    public func isUnlocked(_ name: String) -> Bool {
        guard let expiry = unlockExpiry[name] else { return false }
        return expiry > .now
    }

    /// True si le remote est accessible maintenant (hors coffre, ou déverrouillé).
    public func isAccessible(_ name: String) -> Bool {
        !isLocked(name) || isUnlocked(name)
    }

    // MARK: - Gestion du coffre-fort

    /// Ajoute un remote au coffre-fort. Le retire immédiatement de Fichiers.app.
    public func addToVault(_ name: String) {
        guard !lockedRemotes.contains(name) else { return }
        lockedRemotes.insert(name)
        clearUnlock(name)
        persistLocked()
        signalFileProvider(remote: name)
    }

    /// Retire un remote du coffre-fort (supprime la protection). Le rend de
    /// nouveau visible dans Fichiers.app.
    public func removeFromVault(_ name: String) {
        guard lockedRemotes.contains(name) else { return }
        lockedRemotes.remove(name)
        clearUnlock(name)
        persistLocked()
        signalFileProvider(remote: name)
    }

    // MARK: - Déverrouillage / re-verrouillage

    /// Demande Face ID / Touch ID puis déverrouille le remote pour la durée TTL.
    /// Retourne true si l'authentification a réussi.
    @discardableResult
    public func unlock(_ name: String) async -> Bool {
        let result = await BiometricGate.shared.authenticate(reason: .revealRemoteCredentials)
        switch result {
        case .authenticated, .fallback:
            applyUnlock(name)
            return true
        case .userCancelled, .unavailable:
            return false
        }
    }

    /// Re-verrouille immédiatement un remote (sans attendre l'expiration).
    public func relock(_ name: String) {
        guard unlockExpiry[name] != nil else { return }
        clearUnlock(name)
        persistUnlocks()
        signalFileProvider(remote: name)
    }

    /// Vide entièrement le coffre-fort (utilisé après un wipe de la config).
    public func clearAll() {
        guard !lockedRemotes.isEmpty || !unlockExpiry.isEmpty else { return }
        for task in relockTasks.values { task.cancel() }
        relockTasks.removeAll()
        lockedRemotes.removeAll()
        unlockExpiry.removeAll()
        persistLocked()
        persistUnlocks()
        FileProviderManager.shared.signalRefresh(remote: "", path: "")
    }

    private func applyUnlock(_ name: String) {
        let minutes = currentUnlockMinutes
        // TTL = 0 → déverrouillage très court (juste le temps d'ouvrir le remote).
        let ttl = minutes <= 0 ? 90 : TimeInterval(minutes * 60)
        let expiry = Date().addingTimeInterval(ttl)
        unlockExpiry[name] = expiry
        persistUnlocks()
        signalFileProvider(remote: name)
        scheduleRelock(name, at: expiry)
    }

    private func scheduleRelock(_ name: String, at expiry: Date) {
        relockTasks[name]?.cancel()
        let delay = max(0, expiry.timeIntervalSinceNow)
        relockTasks[name] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            guard let self else { return }
            // Vérifie que ce déverrouillage précis n'a pas été prolongé entre-temps.
            if let current = self.unlockExpiry[name], current <= .now {
                self.relock(name)
            }
        }
    }

    private func clearUnlock(_ name: String) {
        unlockExpiry[name] = nil
        relockTasks[name]?.cancel()
        relockTasks[name] = nil
    }

    // MARK: - Persistance

    private func load() {
        if let data = try? Data(contentsOf: AppGroup.vaultLockedRemotesURL),
           let names = try? JSONDecoder().decode([String].self, from: data) {
            lockedRemotes = Set(names)
        }
        if let data = try? Data(contentsOf: AppGroup.vaultUnlocksURL),
           let map = try? JSONDecoder().decode([String: Double].self, from: data) {
            let now = Date().timeIntervalSince1970
            // Purge les déverrouillages expirés au démarrage.
            unlockExpiry = map
                .filter { $0.value > now }
                .mapValues { Date(timeIntervalSince1970: $0) }
            if unlockExpiry.count != map.count {
                persistUnlocks()
            }
            for (name, expiry) in unlockExpiry {
                scheduleRelock(name, at: expiry)
            }
        }
    }

    private func persistLocked() {
        let payload = Array(lockedRemotes).sorted()
        write(payload, to: AppGroup.vaultLockedRemotesURL)
    }

    private func persistUnlocks() {
        let payload = unlockExpiry.mapValues { $0.timeIntervalSince1970 }
        write(payload, to: AppGroup.vaultUnlocksURL)
    }

    private func write<T: Encodable>(_ value: T, to url: URL) {
        do {
            try FileManager.default.createDirectory(
                at: AppGroup.vaultDir,
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(value)
            // PAS de .completeFileProtection : le fichier doit rester lisible par
            // l'extension même appareil verrouillé, sinon un remote au coffre
            // redeviendrait visible quand l'iPhone est verrouillé (l'inverse du
            // comportement voulu).
            try data.write(to: url, options: [.atomic])
        } catch {
            Task { await LogService.shared.log(.error, category: "vault", message: "Écriture coffre-fort échouée : \(error.localizedDescription)") }
        }
    }

    // MARK: - FileProvider

    private func signalFileProvider(remote: String) {
        // Racine : contrôle la visibilité du remote dans la liste Fichiers.app.
        FileProviderManager.shared.signalRefresh(remote: "", path: "")
        // Conteneur du remote : rafraîchit un dossier éventuellement ouvert.
        if !remote.isEmpty {
            FileProviderManager.shared.signalRefresh(remote: remote, path: "")
        }
    }

    private var currentUnlockMinutes: Int {
        UserDefaults.standard.object(forKey: Self.unlockMinutesKey) as? Int ?? Self.defaultUnlockMinutes
    }
}
