//
//  SubscriptionGate.swift
//  Rclone GUI — Views/Subscription
//
//  Wrapper qui affiche son contenu uniquement quand l'utilisateur a un
//  abonnement actif (trial ou paid). Sinon affiche PaywallView en plein écran.
//
//  Réactif : utilise @ObservedObject sur SubscriptionService.shared, donc
//  si l'abonnement expire pendant que l'app est ouverte (push StoreKit /
//  refund Apple), le paywall apparaît automatiquement.
//

import SwiftUI

struct SubscriptionGate<Content: View>: View {
    @ObservedObject private var subs = SubscriptionService.shared
    let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        if subs.snapshot.isUnlocked {
            content()
        } else {
            PaywallView()
        }
    }
}
