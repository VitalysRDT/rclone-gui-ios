//
//  SubscriptionService.swift
//  Rclone GUI — Services
//
//  Wrapper StoreKit 2 du paywall « 7 jours gratuit puis 1,99€/mois
//  ou 19,99€/an ». Singleton @MainActor ObservableObject pour que
//  les vues SwiftUI réagissent automatiquement aux changements d'état.
//
//  Cycle :
//   1. Au lancement (Rclone_GUIApp), refreshEntitlements() reconstruit
//      le snapshot à partir de Transaction.currentEntitlements.
//   2. observeTransactionUpdates() écoute Transaction.updates en arrière-plan
//      pour capter les renouvellements / révocations / refunds.
//   3. À chaque mise à jour, le snapshot est écrit dans App Group via
//      AppGroup.writeSubscription() pour que l'extension FileProvider
//      puisse gater les opérations sans réseau.
//

import Foundation
import Combine
import StoreKit

@MainActor
public final class SubscriptionService: ObservableObject {
    public static let shared = SubscriptionService()

    /// État courant de l'abonnement. Mis à jour via refreshEntitlements()
    /// et observeTransactionUpdates(). Initialisé depuis l'App Group si
    /// disponible — évite un flash de paywall au boot quand l'utilisateur
    /// est déjà abonné mais que StoreKit n'a pas encore répondu.
    @Published public private(set) var snapshot: SubscriptionSnapshot

    /// Produits StoreKit chargés. Vide tant que loadProducts() n'a pas réussi.
    @Published public private(set) var products: [Product] = []

    /// Vrai pendant qu'un achat est en cours (CTA du paywall en spinner).
    @Published public private(set) var isPurchasing = false

    /// Vrai pendant un restore en cours (bouton Restore en spinner).
    @Published public private(set) var isRestoring = false

    /// Dernier message d'erreur user-friendly à afficher dans le paywall.
    @Published public var lastErrorMessage: String?

    /// Map productID → eligibilité au free trial (introductory offer Apple).
    /// Calculé après loadProducts(). Vide tant que les produits ne sont pas chargés.
    /// Le paywall doit s'en servir pour n'afficher "7 jours gratuits" QUE quand
    /// Apple confirme à la fois (a) l'existence d'un intro offer sur le SKU, et
    /// (b) l'éligibilité de l'utilisateur (pas déjà consommé l'offre).
    @Published public private(set) var introOfferEligibility: [String: Bool] = [:]

    /// Date de fin de l'essai gratuit app-managé (7 jours sans paywall) si
    /// celui-ci est la raison du déverrouillage courant. nil si l'utilisateur
    /// a un vrai abonnement Apple ou si l'essai est expiré.
    @Published public private(set) var localTrialEndDate: Date?

    private var transactionListenerTask: Task<Void, Never>?

    /// Tâche planifiée qui ré-évalue les entitlements à l'instant exact où
    /// l'essai local expire, pour faire apparaître le paywall sans relancer l'app.
    private var trialExpiryTask: Task<Void, Never>?

    private init() {
        // On part du dernier snapshot persisté (si présent) pour éviter
        // un faux paywall flash au boot. La vraie résolution arrive juste
        // après via refreshEntitlements().
        self.snapshot = AppGroup.readSubscription() ?? .locked
    }

    // MARK: - Lifecycle

    /// À appeler une fois au démarrage de l'app (.task racine). Lance la
    /// résolution initiale et l'écoute des updates StoreKit en arrière-plan.
    public func bootstrap() {
        // Ancre l'essai gratuit au tout premier lancement (idempotent et
        // robuste à la réinstallation via Keychain + iCloud KVS). Doit se faire
        // AVANT refreshEntitlements() pour que le premier snapshot reflète
        // déjà l'essai en cours et évite tout flash de paywall.
        TrialStore.startTrialIfNeeded()
        Task { await refreshEntitlements() }
        startObservingTransactionUpdates()
    }

    /// Ré-évalue les entitlements (essai local inclus). À appeler quand l'app
    /// repasse au premier plan : l'essai a pu expirer pendant qu'elle dormait.
    public func refreshOnForeground() {
        Task { await refreshEntitlements() }
    }

    private func startObservingTransactionUpdates() {
        // Une seule tâche d'écoute à la fois.
        transactionListenerTask?.cancel()
        transactionListenerTask = Task.detached(priority: .background) { [weak self] in
            for await verification in Transaction.updates {
                guard let self else { return }
                switch verification {
                case .verified(let transaction):
                    await transaction.finish()
                    await self.refreshEntitlements()
                case .unverified:
                    // On ignore les transactions non vérifiées par Apple
                    // (root cert invalide, etc.) — refreshEntitlements ne
                    // les compterait pas non plus.
                    continue
                }
            }
        }
    }

    // MARK: - Products

    /// Charge la fiche des produits depuis StoreKit. Idempotent : si déjà
    /// chargés, ne refait rien. Appelé par PaywallView dès qu'elle apparaît.
    public func loadProducts() async {
        if !products.isEmpty { return }
        do {
            let loaded = try await Product.products(for: SubscriptionProductID.all)
            // Trie : mensuel d'abord (mis en avant pour le free trial), puis annuel.
            self.products = loaded.sorted { lhs, rhs in
                if lhs.id == SubscriptionProductID.monthly { return true }
                if rhs.id == SubscriptionProductID.monthly { return false }
                return lhs.price < rhs.price
            }
            await refreshIntroOfferEligibility()
        } catch {
            self.lastErrorMessage = "Impossible de charger les offres. Vérifiez votre connexion puis réessayez."
        }
    }

    public func product(for id: String) -> Product? {
        products.first(where: { $0.id == id })
    }

    /// Recalcule l'éligibilité au free trial pour chaque produit chargé.
    /// Apple n'expose un intro offer que si :
    ///   (1) le SKU a une "Introductory Offer" configurée dans App Store Connect,
    ///   (2) l'utilisateur n'a jamais consommé cette offre sur son compte iCloud.
    /// Sans ces deux conditions, on ne doit PAS afficher "7 jours gratuits" :
    /// l'achat partirait au prix régulier et l'utilisateur serait trompé.
    public func refreshIntroOfferEligibility() async {
        var result: [String: Bool] = [:]
        for product in products {
            guard let subscription = product.subscription else {
                result[product.id] = false
                continue
            }
            // L'offre intro doit exister côté ASC ET l'utilisateur doit être éligible.
            let hasOffer = subscription.introductoryOffer != nil
            let eligible = await subscription.isEligibleForIntroOffer
            result[product.id] = hasOffer && eligible
        }
        self.introOfferEligibility = result
    }

    /// Vrai si le produit a un intro offer ET que l'utilisateur est éligible.
    /// Le paywall doit consulter ce flag avant d'afficher tout libellé "trial".
    public func isTrialAvailable(for productID: String) -> Bool {
        introOfferEligibility[productID] ?? false
    }

    /// Description localisée de l'intro offer ("7 jours offerts", "1 semaine gratuite"…)
    /// dérivée du SubscriptionPeriod Apple. Renvoie nil si pas d'offre éligible.
    public func trialDescription(for productID: String) -> String? {
        guard isTrialAvailable(for: productID) else { return nil }
        guard let offer = product(for: productID)?.subscription?.introductoryOffer else { return nil }
        return Self.format(period: offer.period, paymentMode: offer.paymentMode)
    }

    private static func format(period: Product.SubscriptionPeriod, paymentMode: Product.SubscriptionOffer.PaymentMode) -> String {
        let count = period.value
        let unit: String
        switch period.unit {
        case .day:   unit = count > 1 ? "jours" : "jour"
        case .week:  unit = count > 1 ? "semaines" : "semaine"
        case .month: unit = count > 1 ? "mois" : "mois"
        case .year:  unit = count > 1 ? "ans" : "an"
        @unknown default: unit = ""
        }
        // paymentMode .freeTrial = vraiment gratuit ; tout autre mode (payAsYouGo,
        // payUpFront, ou nouveaux modes futurs) implique un coût réduit non nul,
        // donc on préfixe "Intro" pour ne jamais induire l'utilisateur en erreur.
        let prefix = (paymentMode == .freeTrial) ? "" : "Intro "
        return "\(prefix)\(count) \(unit) offert\(count > 1 ? "s" : "")"
    }

    // MARK: - Purchase

    /// Lance l'achat ou l'activation du trial pour le produit donné.
    /// Met à jour snapshot via refreshEntitlements() en cas de succès.
    public func purchase(_ product: Product) async {
        guard !isPurchasing else { return }
        isPurchasing = true
        lastErrorMessage = nil
        defer { isPurchasing = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    await transaction.finish()
                    await refreshEntitlements()
                case .unverified:
                    lastErrorMessage = "L'achat n'a pas pu être validé par Apple. Réessayez."
                }
            case .userCancelled:
                // Pas d'erreur à afficher : l'utilisateur a explicitement annulé.
                break
            case .pending:
                // Ask to Buy / parental approval : on ne débloque pas encore,
                // observeTransactionUpdates() s'en chargera après approbation.
                lastErrorMessage = "Achat en attente d'approbation. L'abonnement sera activé automatiquement."
            @unknown default:
                lastErrorMessage = "Résultat d'achat inconnu."
            }
        } catch {
            lastErrorMessage = "Échec de l'achat : \(error.localizedDescription)"
        }
    }

    // MARK: - Restore

    /// Force une re-synchronisation avec l'App Store. Apple recommande
    /// d'exposer un bouton « Restaurer » dans toute UI de paywall.
    public func restorePurchases() async {
        guard !isRestoring else { return }
        isRestoring = true
        lastErrorMessage = nil
        defer { isRestoring = false }

        do {
            try await AppStore.sync()
            await refreshEntitlements()
            if !snapshot.isUnlocked {
                lastErrorMessage = "Aucun abonnement actif trouvé sur ce compte iCloud."
            }
        } catch {
            lastErrorMessage = "Restauration impossible : \(error.localizedDescription)"
        }
    }

    // MARK: - Entitlements

    /// Reconstruit le snapshot à partir des entitlements StoreKit actuels.
    /// Persiste le résultat dans App Group pour que l'extension FileProvider
    /// puisse gater l'accès sans recharger StoreKit (qui n'est pas disponible
    /// dans toutes les .appex).
    public func refreshEntitlements() async {
        var bestEntitlement: SubscriptionEntitlement = .none
        var bestProductID: String?
        var bestExpiration: Date?
        // L'achat « à vie » (non-consommable) déverrouille l'app de façon
        // permanente et prime sur tout abonnement. On le repère pendant
        // l'itération puis on l'applique après la boucle.
        var hasLifetime = false

        for await verification in Transaction.currentEntitlements {
            guard case .verified(let transaction) = verification else { continue }
            guard SubscriptionProductID.all.contains(transaction.productID) else { continue }

            // Une transaction révoquée (refund Apple) ne compte pas.
            if transaction.revocationDate != nil { continue }

            // Le lifetime non-consommable n'a ni expiration ni renouvellement :
            // s'il est présent et non révoqué, il déverrouille définitivement.
            if transaction.productID == SubscriptionProductID.lifetime {
                hasLifetime = true
                continue
            }

            // Une transaction explicitement « upgraded » a été remplacée par une autre.
            if transaction.isUpgraded { continue }

            // Si la transaction a déjà expiré (Apple peut continuer à la lister
            // brièvement), on la marque mais elle ne déverrouille pas l'app.
            if let expirationDate = transaction.expirationDate,
               expirationDate < Date() {
                if bestEntitlement == .none {
                    bestEntitlement = .expired
                    bestProductID = transaction.productID
                    bestExpiration = expirationDate
                }
                continue
            }

            // Trial vs paid : offer.type == .introductory ⇒ free trial Apple.
            // (offerType deprecated iOS 17.2 — utiliser offer.type qui requiert iOS 17.2+).
            let isTrial: Bool
            if #available(iOS 17.2, *) {
                isTrial = (transaction.offer?.type == .introductory)
            } else {
                isTrial = (transaction.offerType == .introductory)
            }
            let candidate: SubscriptionEntitlement = isTrial ? .trial : .active

            // .active a priorité sur .trial qui a priorité sur tout le reste.
            let candidateRank = rank(of: candidate)
            let currentRank = rank(of: bestEntitlement)
            if candidateRank > currentRank {
                bestEntitlement = candidate
                bestProductID = transaction.productID
                bestExpiration = transaction.expirationDate
            }
        }

        // Achat « à vie » : prioritaire sur tout abonnement (accès permanent,
        // sans date d'expiration). Appliqué après la boucle pour écraser un
        // éventuel abonnement actif résolu en parallèle.
        if hasLifetime {
            bestEntitlement = .active
            bestProductID = SubscriptionProductID.lifetime
            bestExpiration = nil
        }

        // Essai gratuit app-managé : si StoreKit ne déverrouille pas (aucun
        // abonnement Apple actif ou intro en cours) mais que l'essai local est
        // encore valide, on force l'entitlement effectif à .trial. Un vrai
        // abonnement Apple (.active) ou une intro Apple (.trial) garde toujours
        // la priorité — on ne downgrade jamais un abonné. L'expiration portée
        // est alors la fin de l'essai local (affichée dans Réglages).
        let storeKitUnlocks = (bestEntitlement == .active || bestEntitlement == .trial)
        if !storeKitUnlocks, TrialStore.isTrialActive {
            bestEntitlement = .trial
            bestProductID = nil
            bestExpiration = TrialStore.trialEndDate
            localTrialEndDate = TrialStore.trialEndDate
        } else {
            localTrialEndDate = nil
        }

        // Planifie le réveil à l'instant exact de l'expiration de l'essai pour
        // faire apparaître le paywall sans attendre un relaunch ou un foreground.
        scheduleTrialExpiryCheck(at: localTrialEndDate)

        let newSnapshot = SubscriptionSnapshot(
            entitlement: bestEntitlement,
            productID: bestProductID,
            expirationDate: bestExpiration,
            updatedAt: Date()
        )

        if newSnapshot != snapshot {
            snapshot = newSnapshot
        }

        // Persistance App Group : critique pour gater l'extension FileProvider.
        // Erreur d'écriture n'est pas bloquante côté UX (snapshot in-memory
        // suffit pour l'app principale).
        do {
            try AppGroup.writeSubscription(newSnapshot)
        } catch {
            // Log silencieux pour ne pas spammer la UI.
            #if DEBUG
            print("[SubscriptionService] writeSubscription failed: \(error)")
            #endif
        }
    }

    /// (Re)planifie une tâche qui dort jusqu'à `date` puis relance
    /// refreshEntitlements(), afin que le paywall apparaisse pile à la fin de
    /// l'essai gratuit même si l'app reste ouverte. Annule toute tâche
    /// précédente. No-op si `date` est nil ou déjà passée.
    private func scheduleTrialExpiryCheck(at date: Date?) {
        trialExpiryTask?.cancel()
        trialExpiryTask = nil
        guard let date else { return }
        let interval = date.timeIntervalSinceNow
        guard interval > 0 else { return }
        trialExpiryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            await self.refreshEntitlements()
        }
    }

    /// Ordre de priorité quand plusieurs transactions valides coexistent
    /// (rare : Apple ne devrait en exposer qu'une dans currentEntitlements,
    /// mais un upgrade/downgrade en transit peut en générer deux).
    private func rank(of entitlement: SubscriptionEntitlement) -> Int {
        switch entitlement {
        case .active: return 3
        case .trial: return 2
        case .expired: return 1
        case .none: return 0
        }
    }
}
