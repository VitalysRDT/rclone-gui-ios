//
//  ReviewPromptService.swift
//  Rclone GUI — Services
//
//  Tracks lightweight local usage signals before asking for an App Store
//  review. The native App Store rating sheet cannot be customized, so the
//  app shows its own polite pre-prompt first.
//

import Foundation

#if canImport(StoreKit)
import StoreKit
#endif

#if canImport(UIKit)
import UIKit
#endif

@MainActor
public final class ReviewPromptService {
    public static let shared = ReviewPromptService()

    private let defaults: UserDefaults
    private var activeSince: Date?

    private enum Key {
        static let firstSeenAt = "reviewPrompt.firstSeenAt"
        static let launchCount = "reviewPrompt.launchCount"
        static let lastLaunchRecordedAt = "reviewPrompt.lastLaunchRecordedAt"
        static let totalActiveSeconds = "reviewPrompt.totalActiveSeconds"
        static let lastPromptedAt = "reviewPrompt.lastPromptedAt"
        static let didAcceptReview = "reviewPrompt.didAcceptReview"
        static let didDismissPermanently = "reviewPrompt.didDismissPermanently"
    }

    private let minimumLaunches = 3
    private let minimumActiveSeconds: TimeInterval = 20 * 60
    private let minimumDaysSinceInstall: TimeInterval = 24 * 60 * 60
    private let snoozeInterval: TimeInterval = 14 * 24 * 60 * 60

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func recordLaunchIfNeeded() {
        if defaults.object(forKey: Key.firstSeenAt) == nil {
            defaults.set(Date(), forKey: Key.firstSeenAt)
        }

        if let lastLaunchRecordedAt = defaults.object(forKey: Key.lastLaunchRecordedAt) as? Date,
           Date().timeIntervalSince(lastLaunchRecordedAt) < 30 * 60 {
            return
        }

        defaults.set(Date(), forKey: Key.lastLaunchRecordedAt)
        defaults.set(defaults.integer(forKey: Key.launchCount) + 1, forKey: Key.launchCount)
    }

    public func appDidBecomeActive() {
        activeSince = activeSince ?? .now
    }

    public func appDidMoveToBackground() {
        flushActiveTime()
        activeSince = nil
    }

    public func shouldShowPrompt(hasCompletedOnboarding: Bool) -> Bool {
        guard hasCompletedOnboarding else { return false }
        guard !defaults.bool(forKey: Key.didAcceptReview) else { return false }
        guard !defaults.bool(forKey: Key.didDismissPermanently) else { return false }

        flushActiveTime()

        let firstSeenAt = defaults.object(forKey: Key.firstSeenAt) as? Date ?? .now
        guard Date().timeIntervalSince(firstSeenAt) >= minimumDaysSinceInstall else { return false }
        guard defaults.integer(forKey: Key.launchCount) >= minimumLaunches else { return false }
        guard defaults.double(forKey: Key.totalActiveSeconds) >= minimumActiveSeconds else { return false }

        if let lastPromptedAt = defaults.object(forKey: Key.lastPromptedAt) as? Date,
           Date().timeIntervalSince(lastPromptedAt) < snoozeInterval {
            return false
        }

        return true
    }

    public func markPromptShown() {
        defaults.set(Date(), forKey: Key.lastPromptedAt)
    }

    public func requestReview() {
        defaults.set(true, forKey: Key.didAcceptReview)

        #if canImport(StoreKit) && canImport(UIKit)
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) else {
            return
        }
        if #available(iOS 18.0, *) {
            AppStore.requestReview(in: scene)
        } else {
            SKStoreReviewController.requestReview(in: scene)
        }
        #endif
    }

    public func remindLater() {
        defaults.set(Date(), forKey: Key.lastPromptedAt)
    }

    public func dismissPermanently() {
        defaults.set(true, forKey: Key.didDismissPermanently)
    }

    private func flushActiveTime() {
        guard let activeSince else { return }
        let elapsed = max(Date().timeIntervalSince(activeSince), 0)
        defaults.set(defaults.double(forKey: Key.totalActiveSeconds) + elapsed, forKey: Key.totalActiveSeconds)
        self.activeSince = .now
    }
}
