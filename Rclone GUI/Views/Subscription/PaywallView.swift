//
//  PaywallView.swift
//  Rclone GUI — Views/Subscription
//
//  Écran d'abonnement bloquant (« hard paywall »). Affiché :
//   - à la fin de l'onboarding (step .subscription dans OnboardingView)
//   - dès que SubscriptionGate détecte snapshot.isUnlocked == false runtime.
//
//  Volontairement sans bouton « Plus tard » ni close button : l'utilisateur
//  ne peut sortir qu'en souscrivant ou en restaurant un achat existant.
//
//  Réutilise le design system : RG.accent, RGCryptSeal, featureRow pattern
//  hérité d'OnboardingView pour rester cohérent visuellement.
//

import SwiftUI
import StoreKit
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct PaywallView: View {
    /// `false` (défaut) : hard paywall bloquant (onboarding, SubscriptionGate).
    /// `true` : présenté volontairement (Réglages → « Voir les offres ») —
    /// affiche un bouton de fermeture, l'utilisateur est en période d'essai
    /// ou simplement curieux des plans.
    var isDismissable = false

    @ObservedObject private var subs = SubscriptionService.shared
    @Environment(\.dismiss) private var dismiss
    @State private var selectedProductID: String = SubscriptionProductID.monthly
    @State private var showOfferCodeSheet = false

    /// Apple ID numérique de l'app sur l'App Store. Sert à l'URL de
    /// redemption des offer codes sur macOS, où la sheet StoreKit native
    /// n'existe pas.
    private static let appStoreID = "6770088773"

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if isDismissable {
                    HStack {
                        Spacer()
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 26))
                                .foregroundStyle(.secondary)
                                .symbolRenderingMode(.hierarchical)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("Fermer"))
                    }
                    .padding(.top, 14)
                    .padding(.horizontal, 16)
                }

                hero
                    .padding(.top, isDismissable ? 4 : 24)

                bullets
                    .padding(.top, 28)
                    .padding(.horizontal, 28)

                priceCards
                    .padding(.top, 24)
                    .padding(.horizontal, 20)

                ctaSection
                    .padding(.top, 20)
                    .padding(.horizontal, 24)

                solidaritySection
                    .padding(.top, 22)
                    .padding(.horizontal, 24)

                legalFooter
                    .padding(.top, 18)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)
            }
        }
        .background(Color.rgSystemBackground.ignoresSafeArea())
        .task {
            await subs.loadProducts()
        }
        .alert("Achat", isPresented: errorBinding) {
            Button("OK", role: .cancel) { subs.lastErrorMessage = nil }
        } message: {
            Text(subs.lastErrorMessage ?? "")
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { subs.lastErrorMessage != nil },
            set: { newValue in if !newValue { subs.lastErrorMessage = nil } }
        )
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(spacing: 18) {
            RGCryptSeal(size: 110)
            VStack(spacing: 6) {
                Text("Débloque toute l'app")
                    .font(.system(size: 28, weight: .bold))
                    .multilineTextAlignment(.center)
                Text(heroSubtitle)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 24)
    }

    /// Sous-titre dynamique : ne promet le trial que si Apple l'a confirmé
    /// pour le SKU mensuel ET que l'utilisateur est encore éligible.
    private var heroSubtitle: String {
        let trialAvailable = subs.isTrialAvailable(for: SubscriptionProductID.monthly)
        let monthlyPrice = subs.product(for: SubscriptionProductID.monthly)?.displayPrice ?? "2,99 €"
        let yearlyPrice  = subs.product(for: SubscriptionProductID.yearly)?.displayPrice  ?? "11,99 €"
        let lifetimePrice = subs.product(for: SubscriptionProductID.lifetime)?.displayPrice ?? "29,99 €"
        if trialAvailable, let trial = subs.trialDescription(for: SubscriptionProductID.monthly) {
            return String(localized: "\(trial), puis \(monthlyPrice)/mois, \(yearlyPrice)/an ou \(lifetimePrice) à vie")
        }
        return String(localized: "\(monthlyPrice)/mois, \(yearlyPrice)/an ou \(lifetimePrice) à vie")
    }

    // MARK: - Bullets

    private var bullets: some View {
        VStack(spacing: 14) {
            featureRow(
                icon: "cloud.fill",
                tint: .blue,
                title: "Tous tes remotes, partout",
                subtitle: "80+ backends — S3, R2, Drive, Dropbox, SFTP, B2…"
            )
            featureRow(
                icon: "lock.fill",
                tint: RG.accent,
                title: "Crypt rclone illimité",
                subtitle: "AES-256, déchiffrement à la volée, clés sur ton appareil"
            )
            featureRow(
                icon: "photo.on.rectangle.angled",
                tint: RG.photoSync.accent,
                title: "PhotoSync sans limite",
                subtitle: "Backup automatique de toute ta photothèque"
            )
            featureRow(
                icon: "folder.fill",
                tint: .orange,
                title: "Intégration Fichiers complète",
                subtitle: "Chaque remote disponible dans l'app Fichiers iOS"
            )
        }
    }

    private func featureRow(icon: String, tint: Color, title: LocalizedStringKey, subtitle: LocalizedStringKey) -> some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(tint.opacity(0.18))
                .frame(width: 38, height: 38)
                .overlay {
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(tint)
                }
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Price cards

    private var priceCards: some View {
        VStack(spacing: 12) {
            if subs.products.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 140)
            } else {
                ForEach(subs.products, id: \.id) { product in
                    priceCard(for: product)
                }
            }
        }
    }

    @ViewBuilder
    private func priceCard(for product: Product) -> some View {
        let isSelected = selectedProductID == product.id
        let isMonthly = product.id == SubscriptionProductID.monthly
        // Badge dynamique : la mention "X jours gratuits" n'apparait que si
        // StoreKit confirme (a) qu'un introductory offer est configure sur le
        // SKU, et (b) que l'utilisateur est encore eligible. Sinon, on n'affiche
        // rien sur le monthly et le "-16 %" reste sur le yearly.
        let badgeText: String? = {
            if isMonthly, subs.isTrialAvailable(for: product.id),
               let trial = subs.trialDescription(for: product.id) {
                return trial.uppercased()
            }
            if product.id == SubscriptionProductID.lifetime {
                return String(localized: "Meilleure offre").uppercased()
            }
            if product.id == SubscriptionProductID.yearly { return yearlySavingsBadge }
            return nil
        }()

        Button {
            selectedProductID = product.id
        } label: {
            HStack(alignment: .center, spacing: 12) {
                Circle()
                    .strokeBorder(isSelected ? RG.accent : Color.secondary.opacity(0.4), lineWidth: 2)
                    .background(
                        Circle().fill(isSelected ? RG.accent : Color.clear)
                            .padding(4)
                    )
                    .frame(width: 22, height: 22)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(defaultName(for: product))
                            .font(.system(size: 16, weight: .semibold))
                        if let badge = badgeText {
                            Text(badge)
                                .font(.system(size: 10, weight: .bold))
                                .tracking(0.4)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(RG.accent, in: Capsule())
                                .foregroundStyle(.white)
                        }
                    }
                    Text(periodSubtitle(for: product))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Text(product.displayPrice)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: RG.Radius.card, style: .continuous)
                    .fill(Color.rgGroupedRowBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: RG.Radius.card, style: .continuous)
                    .stroke(isSelected ? RG.accent : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    private func defaultName(for product: Product) -> String {
        switch product.id {
        case SubscriptionProductID.monthly:  return String(localized: "Mensuel")
        case SubscriptionProductID.yearly:   return String(localized: "Annuel")
        case SubscriptionProductID.lifetime: return String(localized: "À vie")
        default: return product.displayName.isEmpty ? product.id : product.displayName
        }
    }

    private func periodSubtitle(for product: Product) -> String {
        switch product.id {
        case SubscriptionProductID.monthly:  return String(localized: "Renouvellement chaque mois")
        case SubscriptionProductID.yearly:   return String(localized: "Renouvellement chaque année")
        case SubscriptionProductID.lifetime: return String(localized: "Paiement unique · accès permanent")
        default: return ""
        }
    }

    /// Badge d'économie de l'annuel vs 12× le mensuel, calculé dynamiquement
    /// à partir des prix StoreKit réels (les prix peuvent varier par storefront,
    /// donc on ne code jamais le pourcentage en dur). Repli "-67 %" si les
    /// produits ne sont pas encore chargés.
    private var yearlySavingsBadge: String {
        guard
            let monthly = subs.product(for: SubscriptionProductID.monthly)?.price,
            let yearly = subs.product(for: SubscriptionProductID.yearly)?.price,
            monthly > 0
        else { return "-67 %" }
        let yearlyEquivalent = monthly * 12
        guard yearlyEquivalent > yearly else { return "-67 %" }
        let savings = (yearlyEquivalent - yearly) / yearlyEquivalent
        let pct = Int((NSDecimalNumber(decimal: savings).doubleValue * 100).rounded())
        return "-\(pct) %"
    }

    // MARK: - CTA

    private var ctaSection: some View {
        VStack(spacing: 12) {
            Button {
                Task { await purchaseSelected() }
            } label: {
                HStack(spacing: 8) {
                    if subs.isPurchasing {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                    }
                    Text(primaryCTALabel)
                        .font(.system(size: 17, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(RG.accent, in: RoundedRectangle(cornerRadius: RG.Radius.card, style: .continuous))
                .foregroundStyle(.white)
                .shadow(color: RG.accent.opacity(0.30), radius: 12, x: 0, y: 6)
            }
            .buttonStyle(.plain)
            .disabled(subs.isPurchasing || subs.products.isEmpty)

            Button {
                Task { await subs.restorePurchases() }
            } label: {
                HStack(spacing: 6) {
                    if subs.isRestoring {
                        ProgressView()
                            .progressViewStyle(.circular)
                    }
                    Text("Restaurer un achat")
                        .font(.system(size: 15, weight: .medium))
                }
                .foregroundStyle(RG.accent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            .disabled(subs.isRestoring)

            offerCodeButton
        }
    }

    /// Redemption d'un offer code Apple (abonnement offert X mois, créé dans
    /// App Store Connect). Sur iOS, la sheet StoreKit native ; sur macOS elle
    /// n'existe pas → page de redemption App Store dans le navigateur. La
    /// transaction résultante arrive via Transaction.updates, déjà écoutée
    /// par SubscriptionService.
    private var offerCodeButton: some View {
        Button {
            #if os(iOS)
            showOfferCodeSheet = true
            #else
            openURL("https://apps.apple.com/redeem?ctx=offercodes&id=\(Self.appStoreID)")
            #endif
        } label: {
            Text("J'ai un code")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        #if os(iOS)
        .offerCodeRedemption(isPresented: $showOfferCodeSheet) { result in
            if case .failure(let error) = result {
                subs.lastErrorMessage = error.localizedDescription
            }
        }
        #endif
    }

    private var primaryCTALabel: String {
        // L'achat à vie n'est pas un abonnement : CTA dédié, jamais "S'abonner"
        // ni "essai gratuit" (pas d'intro offer sur un non-consommable).
        if SubscriptionProductID.isLifetime(selectedProductID) {
            return String(localized: "Débloquer à vie")
        }
        // Le libelle "Commencer l'essai gratuit" n'est valide que si Apple a
        // confirme un intro offer ET l'eligibilite de l'utilisateur. Sinon
        // on tombe sur "S'abonner" pour ne pas promettre un trial inexistant.
        if subs.isTrialAvailable(for: selectedProductID) {
            return String(localized: "Commencer l'essai gratuit")
        }
        return String(localized: "S'abonner")
    }

    private func purchaseSelected() async {
        guard let product = subs.product(for: selectedProductID) else {
            await subs.loadProducts()
            return
        }
        await subs.purchase(product)
    }

    // MARK: - Legal footer

    /// Mention légale contextuelle : un achat à vie (non-consommable) ne se
    /// renouvelle pas, donc on n'affiche jamais la clause d'auto-renouvellement
    /// quand le lifetime est sélectionné — sinon Apple peut rejeter pour
    /// information trompeuse.
    private var legalDisclaimer: LocalizedStringKey {
        if SubscriptionProductID.isLifetime(selectedProductID) {
            return "Paiement unique, sans abonnement. Accès permanent sur tous les appareils liés au même identifiant Apple."
        }
        return "L'abonnement se renouvelle automatiquement. Annule à tout moment dans Réglages → Identifiant Apple → Abonnements, au moins 24 h avant la fin de la période en cours."
    }

    private var legalFooter: some View {
        VStack(spacing: 6) {
            Text(legalDisclaimer)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 6) {
                Button("Conditions d'utilisation") {
                    openURL("https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")
                }
                .font(.system(size: 11))
                Text("·").foregroundStyle(.secondary).font(.system(size: 11))
                Button("Politique de confidentialité") {
                    openURL("https://vitalysrdt.github.io/rclone-gui-ios/privacy.html")
                }
                .font(.system(size: 11))
            }
            .foregroundStyle(RG.accent)
        }
    }

    private func openURL(_ string: String) {
        guard let url = URL(string: string) else { return }
        openURL(url)
    }

    private func openURL(_ url: URL) {
        #if canImport(UIKit)
        UIApplication.shared.open(url)
        #elseif canImport(AppKit)
        NSWorkspace.shared.open(url)
        #endif
    }

    // MARK: - Solidarité / accès selon les moyens

    /// Bloc « paie selon tes moyens ». L'app est libre et son auteur n'a pas non
    /// plus de gros moyens : les personnes qui ne peuvent pas payer le plein
    /// tarif (étudiant·e, chômage, emploi précaire…) peuvent demander un code de
    /// réduction Apple par e-mail, qu'elles redeem ensuite via « J'ai un code »
    /// ci-dessus. Tout reste dans le système IAP d'Apple (offer codes) → aucun
    /// paiement hors App Store, donc conforme aux règles de l'App Review.
    private var solidaritySection: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "heart.circle.fill")
                    .font(.system(size: 24))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(RG.accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Budget serré ?")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Étudiant·e, emploi précaire, chômage… pas de quoi soutenir le développeur en ce moment ? Demande une réduction selon tes moyens, sans justificatif.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            Button {
                if let url = Self.discountRequestURL { openURL(url) }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "envelope.fill")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Demander une réduction selon mes moyens")
                        .font(.system(size: 14, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(RG.accentSoft, in: RoundedRectangle(cornerRadius: RG.Radius.card, style: .continuous))
                .foregroundStyle(RG.accent)
            }
            .buttonStyle(.plain)

            Text("Cette app est faite par un développeur passionné qui n'a pas non plus les moyens. Elle est libre : tu peux la compiler gratuitement depuis le code source. Tes abonnements aident à faire naître de nouvelles apps et à rendre la technologie accessible au plus grand nombre. Merci 🙏")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button("Voir le code source (libre)") {
                openURL("https://github.com/VitalysRDT/rclone-gui-ios")
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(RG.accent)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: RG.Radius.card, style: .continuous)
                .fill(RG.accent.opacity(0.06))
        )
    }

    /// mailto pré-rempli (vers l'adresse du développeur) pour demander un code
    /// de réduction. L'utilisateur reçoit un offer code Apple qu'il redeem via
    /// « J'ai un code » — on ne sort jamais du système de paiement d'Apple.
    private static var discountRequestURL: URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = "vitalys@rougetet.com"
        let subject = String(localized: "Rclone GUI — Demande de réduction (selon mes moyens)")
        let body = String(localized: """
        Bonjour,

        J'aimerais utiliser Rclone GUI mais le plein tarif est au-dessus de mes moyens en ce moment (par ex. étudiant·e, emploi précaire ou chômage).
        Serait-il possible d'obtenir un code de réduction ?

        Merci beaucoup pour cette app,
        """)
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body)
        ]
        return components.url
    }
}

#Preview {
    PaywallView()
}
