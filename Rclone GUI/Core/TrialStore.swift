//
//  TrialStore.swift
//  Rclone GUI — Core
//
//  Source de vérité de la période d'essai gratuit « 7 jours sans paywall »
//  gérée par l'app (et non par l'offre intro Apple, qui reste branchée sur
//  l'abonnement mensuel pour APRÈS l'essai).
//
//  Objectif clé : l'essai doit survivre à une désinstallation/réinstallation
//  pour qu'un utilisateur ne puisse pas se redonner 7 jours en supprimant
//  puis réinstallant l'app. Deux stockages persistants hors sandbox app :
//    1. Keychain (kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly) — survit
//       à la désinstallation sur le MÊME appareil.
//    2. iCloud Key-Value Store (NSUbiquitousKeyValueStore) — survit au
//       changement / à la restauration d'appareil (lié à l'Apple ID).
//
//  On lit la date de début la PLUS ANCIENNE trouvée dans les deux stores
//  (anti-gaming) et on auto-répare celui qui aurait été effacé. Un petit
//  garde-fou anti-recul d'horloge (`lastSeen` monotone) empêche de prolonger
//  l'essai en remettant la date du téléphone en arrière.
//
//  `nonisolated` : le projet utilise SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor.
//  TrialStore ne touche aucun état UI et doit être appelable depuis n'importe
//  quel contexte, donc on l'affranchit de l'isolation par défaut.
//

import Foundation
import Security

public nonisolated enum TrialStore {
    /// Durée de l'essai gratuit app-managé.
    public static let duration: TimeInterval = 7 * 24 * 3600

    // Tags Keychain (kSecAttrService). Distincts du master key rclone.
    private static let startService = "com.rougetet.rclone-gui.trial.start"
    private static let lastSeenService = "com.rougetet.rclone-gui.trial.lastseen"

    // Clés iCloud Key-Value Store.
    private static let startKVSKey = "trial.startDate"
    private static let lastSeenKVSKey = "trial.lastSeen"

    // MARK: - API publique

    /// Date de début d'essai effective : la plus ancienne connue entre Keychain
    /// et iCloud KVS. Retourne nil si l'essai n'a jamais été ancré.
    public static func trialStartDate() -> Date? {
        let candidates = [keychainDate(service: startService), kvsDate(forKey: startKVSKey)]
            .compactMap { $0 }
        return candidates.min()
    }

    /// Ancre l'essai au tout premier lancement si nécessaire. Idempotent :
    /// si une date existe déjà (dans l'un des stores), on la ré-écrit dans les
    /// deux (auto-réparation) et on la retourne ; sinon on écrit `Date()`.
    @discardableResult
    public static func startTrialIfNeeded() -> Date {
        if let existing = trialStartDate() {
            // Auto-réparation : s'assure que les deux stores portent la date la
            // plus ancienne, au cas où l'un aurait été effacé (réinstallation
            // qui a wipé le Keychain, nouvel appareil sans la valeur KVS, etc.).
            persistStart(existing)
            return existing
        }
        let now = Date()
        persistStart(now)
        // Initialise aussi le garde-fou anti-recul d'horloge.
        persistLastSeen(now)
        return now
    }

    /// Date de fin d'essai (début + durée), ou nil si non ancré.
    public static var trialEndDate: Date? {
        guard let start = trialStartDate() else { return nil }
        return start.addingTimeInterval(duration)
    }

    /// Vrai tant que l'essai gratuit est en cours. Faux si non ancré ou expiré.
    /// Utilise `effectiveNow()` (monotone) pour résister à un recul d'horloge.
    public static var isTrialActive: Bool {
        guard let end = trialEndDate else { return false }
        return effectiveNow() < end
    }

    // MARK: - Anti-recul d'horloge

    /// « Maintenant » non-régressif : le plus tard entre l'horloge système et
    /// la dernière date vue persistée. Remet aussi à jour `lastSeen`. Ainsi,
    /// reculer l'horloge du téléphone ne prolonge pas l'essai.
    private static func effectiveNow() -> Date {
        let now = Date()
        let previous = lastSeenDate()
        let effective = max(now, previous ?? now)
        persistLastSeen(effective)
        return effective
    }

    /// Plus grande date vue, lue depuis les deux stores (on prend le max ici,
    /// contrairement à la date de début où on prend le min).
    private static func lastSeenDate() -> Date? {
        let candidates = [keychainDate(service: lastSeenService), kvsDate(forKey: lastSeenKVSKey)]
            .compactMap { $0 }
        return candidates.max()
    }

    // MARK: - Écritures combinées

    private static func persistStart(_ date: Date) {
        setKeychainDate(date, service: startService)
        setKVSDate(date, forKey: startKVSKey)
    }

    private static func persistLastSeen(_ date: Date) {
        setKeychainDate(date, service: lastSeenService)
        setKVSDate(date, forKey: lastSeenKVSKey)
    }

    // MARK: - iCloud Key-Value Store

    private static func kvsDate(forKey key: String) -> Date? {
        let store = NSUbiquitousKeyValueStore.default
        // object(forKey:) vaut nil si la clé est absente — double(forKey:)
        // renverrait 0 sans distinguer « absent » de « 1970 ».
        guard let value = store.object(forKey: key) as? Double, value > 0 else { return nil }
        return Date(timeIntervalSince1970: value)
    }

    private static func setKVSDate(_ date: Date, forKey key: String) {
        let store = NSUbiquitousKeyValueStore.default
        store.set(date.timeIntervalSince1970, forKey: key)
        store.synchronize()
    }

    // MARK: - Keychain (calqué sur ConfigStore.baseKeychainQuery)

    /// Lit une date depuis le Keychain. Essaie d'abord l'access group partagé
    /// (comme le master key) puis le groupe app-only en fallback.
    private static func keychainDate(service: String) -> Date? {
        if let shared = AppGroup.keychainAccessGroup,
           let data = keychainData(service: service, accessGroup: shared) {
            return decodeDate(data)
        }
        if let data = keychainData(service: service, accessGroup: nil) {
            return decodeDate(data)
        }
        return nil
    }

    private static func keychainData(service: String, accessGroup: String?) -> Data? {
        var query = baseQuery(service: service, accessGroup: accessGroup)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else { return nil }
        return item as? Data
    }

    /// Écrit une date dans le Keychain. Écrit dans le groupe partagé si
    /// provisionné, sinon dans le groupe app-only (best-effort, non bloquant).
    private static func setKeychainDate(_ date: Date, service: String) {
        let data = encodeDate(date)
        if let shared = AppGroup.keychainAccessGroup,
           storeKeychainData(data, service: service, accessGroup: shared) {
            return
        }
        _ = storeKeychainData(data, service: service, accessGroup: nil)
    }

    @discardableResult
    private static func storeKeychainData(_ data: Data, service: String, accessGroup: String?) -> Bool {
        var attrs = baseQuery(service: service, accessGroup: accessGroup)
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        attrs[kSecValueData as String] = data

        let status = SecItemAdd(attrs as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let query = baseQuery(service: service, accessGroup: accessGroup)
            let update: [String: Any] = [kSecValueData as String: data]
            return SecItemUpdate(query as CFDictionary, update as CFDictionary) == errSecSuccess
        }
        return status == errSecSuccess
    }

    private static func baseQuery(service: String, accessGroup: String?) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        if let accessGroup, !accessGroup.isEmpty {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }

    // MARK: - Encodage Date ⇄ Data (8 octets, timeIntervalSince1970)

    private static func encodeDate(_ date: Date) -> Data {
        var ti = date.timeIntervalSince1970
        return Data(bytes: &ti, count: MemoryLayout<Double>.size)
    }

    private static func decodeDate(_ data: Data) -> Date? {
        guard data.count == MemoryLayout<Double>.size else { return nil }
        let ti = data.withUnsafeBytes { $0.loadUnaligned(as: Double.self) }
        guard ti > 0, ti.isFinite else { return nil }
        return Date(timeIntervalSince1970: ti)
    }
}
