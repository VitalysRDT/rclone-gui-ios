//
//  SubscriptionStatusTests.swift
//  Rclone GUITests
//

import Foundation
import Testing
@testable import Rclone_GUI

@Suite("Subscription status presentation")
struct SubscriptionStatusTests {
    @Test("Lifetime access is permanent and not auto-renewable")
    func classifiesLifetimePurchase() {
        let snapshot = SubscriptionSnapshot(
            entitlement: .active,
            productID: SubscriptionProductID.lifetime
        )

        #expect(snapshot.isUnlocked)
        #expect(snapshot.hasLifetimeAccess)
        #expect(!snapshot.hasActiveAutoRenewableSubscription)
    }

    @Test("Paid monthly and yearly plans are auto-renewable")
    func classifiesPaidSubscriptions() {
        for productID in [SubscriptionProductID.monthly, SubscriptionProductID.yearly] {
            let snapshot = SubscriptionSnapshot(entitlement: .active, productID: productID)

            #expect(snapshot.isUnlocked)
            #expect(!snapshot.hasLifetimeAccess)
            #expect(snapshot.hasActiveAutoRenewableSubscription)
        }
    }

    @Test("An Apple introductory trial remains a managed subscription")
    func classifiesAppleTrial() {
        let snapshot = SubscriptionSnapshot(
            entitlement: .trial,
            productID: SubscriptionProductID.monthly
        )

        #expect(snapshot.isUnlocked)
        #expect(snapshot.hasActiveAutoRenewableSubscription)
    }

    @Test("The app-managed trial has no Apple subscription to manage")
    func classifiesLocalTrial() {
        let snapshot = SubscriptionSnapshot(entitlement: .trial, productID: nil)

        #expect(snapshot.isUnlocked)
        #expect(!snapshot.hasLifetimeAccess)
        #expect(!snapshot.hasActiveAutoRenewableSubscription)
    }

    @Test("An expired subscription is not presented as active")
    func rejectsExpiredSubscription() {
        let snapshot = SubscriptionSnapshot(
            entitlement: .expired,
            productID: SubscriptionProductID.yearly
        )

        #expect(!snapshot.isUnlocked)
        #expect(!snapshot.hasLifetimeAccess)
        #expect(!snapshot.hasActiveAutoRenewableSubscription)
    }
}
