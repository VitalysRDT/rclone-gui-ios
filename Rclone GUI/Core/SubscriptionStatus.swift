//
//  SubscriptionStatus.swift
//  Rclone GUI — Core
//
//  Modèle d'état d'abonnement partagé entre l'app principale et
//  l'extension FileProvider via le container App Group.
//
//  L'app écrit ce snapshot après chaque résolution StoreKit
//  (refreshEntitlements / observeTransactionUpdates). L'extension
//  ne fait que lire ce fichier au début de chaque entrée publique
//  pour décider si elle sert l'opération ou refuse avec
//  NSFileProviderError.notAuthenticated.
//

import Foundation

// `nonisolated` est requis : le projet utilise SWIFT_DEFAULT_ACTOR_ISOLATION
// = MainActor, donc tout nouveau type est implicitement @MainActor sauf
// indication contraire. Or ces deux modèles doivent être encodables/décodables
// depuis l'extension FileProvider (contexte non-MainActor), donc on les
// affranchit explicitement de l'isolation par défaut.
public nonisolated enum SubscriptionEntitlement: String, Codable, Sendable {
    /// Aucune trace d'abonnement actif. Paywall hard.
    case none
    /// Période d'essai gratuit en cours (Introductory Offer Apple).
    case trial
    /// Abonnement payant actif (mensuel ou annuel).
    case active
    /// Abonnement précédent expiré sans renouvellement. Paywall hard.
    case expired
}

public nonisolated struct SubscriptionSnapshot: Codable, Sendable, Equatable {
    public let entitlement: SubscriptionEntitlement
    public let productID: String?
    public let expirationDate: Date?
    public let updatedAt: Date

    public init(
        entitlement: SubscriptionEntitlement,
        productID: String? = nil,
        expirationDate: Date? = nil,
        updatedAt: Date = Date()
    ) {
        self.entitlement = entitlement
        self.productID = productID
        self.expirationDate = expirationDate
        self.updatedAt = updatedAt
    }

    /// État "verrouillé absent" utilisé par défaut (1er lancement, lecture
    /// échouée). Plus sûr de considérer l'utilisateur comme non abonné
    /// par défaut que d'ouvrir l'app — la commande StoreKit asynchrone
    /// mettra à jour le snapshot dès que le verdict est connu.
    public static let locked = SubscriptionSnapshot(entitlement: .none)

    /// L'app et l'extension sont autorisées à servir uniquement si le
    /// snapshot est .trial ou .active. Toute autre valeur (none, expired)
    /// déclenche le paywall.
    public var isUnlocked: Bool {
        entitlement == .trial || entitlement == .active
    }
}

/// IDs StoreKit utilisés partout dans l'app. Conservés ici pour qu'extension
/// et main app référencent les mêmes constantes.
public enum SubscriptionProductID {
    // Apple n'autorise pas les tirets dans les productId IAP (seuls
    // alphanumériques, underscores et points sont valides). Le bundle ID
    // utilise un tiret mais on bascule sur underscore ici.
    public static let monthly = "com.rougetet.rclone_gui.premium.monthly"
    public static let yearly = "com.rougetet.rclone_gui.premium.yearly"
    /// Achat unique « à vie » (non-consommable). Déverrouille l'app de façon
    /// permanente : pas d'expiration, pas de renouvellement. Résolu comme
    /// `.active` par refreshEntitlements et prioritaire sur tout abonnement.
    public static let lifetime = "com.rougetet.rclone_gui.premium.lifetime"
    public static let all: [String] = [monthly, yearly, lifetime]

    /// Vrai pour le produit non-consommable « à vie ». Utilisé pour adapter
    /// l'UI (libellés, CTA, mention légale) qui diffère d'un abonnement.
    public static func isLifetime(_ productID: String?) -> Bool {
        productID == lifetime
    }
}
