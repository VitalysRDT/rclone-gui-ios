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
    @ObservedObject private var subs = SubscriptionService.shared
    @State private var selectedProductID: String = SubscriptionProductID.monthly
    @State private var showOfferCodeSheet = false

    /// Apple ID numérique de l'app sur l'App Store. Sert à l'URL de
    /// redemption des offer codes sur macOS, où la sheet StoreKit native
    /// n'existe pas.
    private static let appStoreID = "6770088773"

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                hero
                    .padding(.top, 24)

                bullets
                    .padding(.top, 28)
                    .padding(.horizontal, 28)

                priceCards
                    .padding(.top, 24)
                    .padding(.horizontal, 20)

                ctaSection
                    .padding(.top, 20)
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
        let monthlyPrice = subs.product(for: SubscriptionProductID.monthly)?.displayPrice ?? "1,99 €"
        let yearlyPrice  = subs.product(for: SubscriptionProductID.yearly)?.displayPrice  ?? "19,99 €"
        if trialAvailable, let trial = subs.trialDescription(for: SubscriptionProductID.monthly) {
            return "\(trial), puis \(monthlyPrice)/mois ou \(yearlyPrice)/an"
        }
        return "\(monthlyPrice)/mois ou \(yearlyPrice)/an"
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

    private func featureRow(icon: String, tint: Color, title: String, subtitle: String) -> some View {
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
            if product.id == SubscriptionProductID.yearly { return "-16 %" }
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
                        Text(product.displayName.isEmpty ? defaultName(for: product) : product.displayName)
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
        case SubscriptionProductID.monthly: return String(localized: "Mensuel")
        case SubscriptionProductID.yearly:  return String(localized: "Annuel")
        default: return product.id
        }
    }

    private func periodSubtitle(for product: Product) -> String {
        switch product.id {
        case SubscriptionProductID.monthly: return String(localized: "Renouvellement chaque mois")
        case SubscriptionProductID.yearly:  return String(localized: "Renouvellement chaque année")
        default: return ""
        }
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
        // Le libelle "Commencer l'essai gratuit" n'est valide que si Apple a
        // confirme un intro offer ET l'eligibilite de l'utilisateur. Sinon
        // on tombe sur "S'abonner" pour ne pas promettre un trial inexistant.
        if subs.isTrialAvailable(for: selectedProductID) {
            return "Commencer l'essai gratuit"
        }
        return "S'abonner"
    }

    private func purchaseSelected() async {
        guard let product = subs.product(for: selectedProductID) else {
            await subs.loadProducts()
            return
        }
        await subs.purchase(product)
    }

    // MARK: - Legal footer

    private var legalFooter: some View {
        VStack(spacing: 6) {
            Text("L'abonnement se renouvelle automatiquement. Annule à tout moment dans Réglages → Identifiant Apple → Abonnements, au moins 24 h avant la fin de la période en cours.")
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
        #if canImport(UIKit)
        UIApplication.shared.open(url)
        #elseif canImport(AppKit)
        NSWorkspace.shared.open(url)
        #endif
    }
}

#Preview {
    PaywallView()
}
