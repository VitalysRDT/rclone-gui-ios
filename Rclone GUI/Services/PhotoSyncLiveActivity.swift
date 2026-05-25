//
//  PhotoSyncLiveActivity.swift
//  Rclone GUI — Services
//
//  Bridge service that owns the `Activity<PhotoSyncActivityAttributes>`
//  handle and coalesces updates from `PhotoSyncService` (which ticks at
//  500ms via `core/stats` polling) down to a ~2s cadence — well below
//  the ActivityKit rate limit. Critical transitions (pause/resume,
//  phase change) bypass the throttle so the Dynamic Island reflects
//  the user's last action instantly.
//
//  Authorization gate: `ActivityAuthorizationInfo().areActivitiesEnabled`.
//  If the user has disabled Live Activities in iOS Settings, every call
//  no-ops silently — falls back to the existing notification surface.
//
//  Lifecycle:
//    runSync(continueUntilEmpty: true) starts the activity
//    waitForRcloneJob ticks call `update(_:)` with throttling
//    pausePhotoSync/resumePhotoSync bypass throttle for instant feedback
//    runSync exit (defer) ends the activity with `.successAutoDismiss` (30s)
//    app willTerminate ends `.immediate`
//

import Foundation
#if os(iOS)
import ActivityKit
#endif

@available(iOS 16.2, *)
@MainActor
final class PhotoSyncLiveActivity {
    static let shared = PhotoSyncLiveActivity()

    enum DismissalReason {
        case successAutoDismiss
        case userCancelled
        case appTerminating
        case failed
    }

    #if os(iOS)
    private var activity: Activity<PhotoSyncActivityAttributes>?
    private var lastUpdate: Date = .distantPast
    private var pendingState: PhotoSyncActivityAttributes.ContentState?
    private var flushTask: Task<Void, Never>?
    private let minInterval: TimeInterval = 2.0

    private init() {}

    /// True if iOS supports Live Activities AND the user has them enabled
    /// in Settings. Used by every call site as a cheap gate.
    private var canUseActivities: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    /// Démarre une nouvelle Live Activity pour la session courante. No-op
    /// si une activité existe déjà, si l'utilisateur a désactivé les
    /// Live Activities, ou si l'OS ne les supporte pas. Idempotent.
    func start(
        remoteLabel: String,
        backendKind: String,
        initialState: PhotoSyncActivityAttributes.ContentState
    ) async {
        guard canUseActivities else { return }
        guard activity == nil else { return }
        let attributes = PhotoSyncActivityAttributes(
            remoteLabel: remoteLabel,
            backendKind: backendKind,
            startedAt: Date()
        )
        do {
            activity = try Activity.request(
                attributes: attributes,
                content: .init(state: initialState, staleDate: Date().addingTimeInterval(60)),
                pushType: nil
            )
            lastUpdate = Date()
        } catch {
            // ActivityKit can refuse (provisioning, throttling, …) —
            // dégrade silencieusement vers le fallback notification.
            activity = nil
        }
    }

    /// Met à jour la Live Activity. Coalesce les ticks rapides (500ms)
    /// vers une cadence ≥2s pour rester sous le quota ActivityKit. Les
    /// transitions critiques (pause/resume, changement de phase) sont
    /// flushées immédiatement via `force: true`.
    func update(_ state: PhotoSyncActivityAttributes.ContentState, force: Bool = false) async {
        guard let activity else { return }
        if force {
            await flush(state, to: activity)
            return
        }
        pendingState = state
        let now = Date()
        let sinceLast = now.timeIntervalSince(lastUpdate)
        if sinceLast >= minInterval {
            await flush(state, to: activity)
            return
        }
        // Planifie un flush différé. Si un flush est déjà en attente,
        // on garde le pendingState (le plus récent gagne).
        if flushTask == nil {
            let delay = minInterval - sinceLast
            flushTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(delay))
                guard let self else { return }
                if let pending = self.pendingState, let activity = self.activity {
                    await self.flush(pending, to: activity)
                }
                self.flushTask = nil
            }
        }
    }

    private func flush(
        _ state: PhotoSyncActivityAttributes.ContentState,
        to activity: Activity<PhotoSyncActivityAttributes>
    ) async {
        // `staleDate` = now + 60s — si on ne tick plus, iOS marque
        // l'activité stale (visible plus pâle) au lieu de la garder
        // figée éternellement.
        await activity.update(
            ActivityContent(state: state, staleDate: Date().addingTimeInterval(60))
        )
        lastUpdate = Date()
        pendingState = nil
    }

    /// Ferme la Live Activity. Sur succès → dismissal différé de 30s
    /// (l'utilisateur voit le ✓ avant la disparition). Sur cancel /
    /// terminate / fail → dismissal immédiat.
    func end(
        terminalState: PhotoSyncActivityAttributes.ContentState,
        reason: DismissalReason
    ) async {
        guard let activity else { return }
        flushTask?.cancel()
        flushTask = nil
        let policy: ActivityUIDismissalPolicy
        switch reason {
        case .successAutoDismiss:
            policy = .after(Date().addingTimeInterval(30))
        case .userCancelled, .appTerminating, .failed:
            policy = .immediate
        }
        await activity.end(
            ActivityContent(state: terminalState, staleDate: nil),
            dismissalPolicy: policy
        )
        self.activity = nil
        lastUpdate = .distantPast
        pendingState = nil
    }

    /// Termine toute activité orpheline encore présente après un crash
    /// ou un cold-start. À appeler une fois au lancement de l'app avant
    /// `resumeIfNeeded`. Idempotent.
    static func endOrphanActivities() async {
        guard #available(iOS 16.2, *) else { return }
        for activity in Activity<PhotoSyncActivityAttributes>.activities {
            await activity.end(
                nil,
                dismissalPolicy: .immediate
            )
        }
    }
    #else
    private init() {}

    func start(remoteLabel: String, backendKind: String, initialState: Any) async {}
    func update(_ state: Any, force: Bool = false) async {}
    func end(terminalState: Any, reason: DismissalReason) async {}
    static func endOrphanActivities() async {}
    #endif
}
