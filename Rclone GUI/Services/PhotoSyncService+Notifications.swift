//
//  PhotoSyncService+Notifications.swift
//  Rclone GUI — Services
//
//  Local-notification surface for the Photo backup service. Lives in its own
//  file so the 800-line PhotoSyncService stays focused on sync orchestration.
//
//  Auth model:
//   - We never request authorization implicitly — only when the user toggles
//     the "Notifications après sync" switch in PhotoSyncSettingsView.
//   - postSyncCompleteNotification is best-effort: if the user has not granted
//     permission, the call is a no-op (UNNotificationCenter ignores the request).
//

#if os(iOS) || os(macOS)
import Foundation
#if canImport(UIKit)
import UIKit
#endif
import UserNotifications

extension PhotoSyncService {
    /// Storage key for the user's notification preference. Mirrored by the
    /// @AppStorage binding in PhotoSyncSettingsView so a Settings change
    /// is visible from the service immediately.
    public static let notificationsEnabledKey = "photosync.notificationsEnabled"

    /// Identifier of the notification posted after each sync run. Reusing
    /// the same id collapses earlier "sync done" notifications when a new
    /// run completes — the user only sees the latest status.
    private static let syncCompleteNotificationID = "photosync.syncComplete"

    /// Catégorie de notification qui porte les actions inline Pause / Reprendre.
    /// Routée vers `PhotoSyncNotificationDelegate.handleAction(_:)`.
    public static let progressCategoryID = "PHOTO_SYNC_PROGRESS"
    public static let pauseActionID = "PHOTO_SYNC_PAUSE"
    public static let resumeActionID = "PHOTO_SYNC_RESUME"

    /// Enregistre la catégorie de notification une seule fois au démarrage.
    /// Appeler depuis l'App init (cf. `Rclone_GUIApp.init`).
    public static func registerNotificationCategories() {
        let pause = UNNotificationAction(
            identifier: pauseActionID,
            title: "Mettre en pause",
            options: []
        )
        let resume = UNNotificationAction(
            identifier: resumeActionID,
            title: "Reprendre",
            options: []
        )
        let category = UNNotificationCategory(
            identifier: progressCategoryID,
            actions: [pause, resume],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
        UNUserNotificationCenter.current().delegate = PhotoSyncNotificationDelegate.shared
    }

    /// Met à jour le badge de l'icône d'app. iOS 17+ exige `setBadgeCount`
    /// via UNUserNotificationCenter — `UIApplication.applicationIconBadgeNumber`
    /// est déprécié.
    public static func updateBadgeCount(_ count: Int) {
        UNUserNotificationCenter.current().setBadgeCount(max(0, count)) { _ in }
    }

    /// Request notification authorization. Idempotent — iOS only shows the
    /// permission alert the first time. Logs the result via LogService.
    public func requestNotificationAuthorization() async {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            await LogService.shared.log(
                .info,
                category: "photos",
                message: granted
                    ? "Autorisation notifications photo sync accordée"
                    : "Autorisation notifications photo sync refusée"
            )
        } catch {
            await LogService.shared.log(
                .error,
                category: "photos",
                message: "Demande d'autorisation notifications a échoué : \(error.localizedDescription)"
            )
        }
    }

    /// Post a "sync done" local notification if the user has enabled the
    /// feature. Safe to call after every sync run — it deduplicates by ID.
    ///
    /// `abortedReason` is used when sync exited early without uploading or
    /// failing anything (auth revoked, policy blocked, …). In that case
    /// the count guard is bypassed so the user gets a notification instead
    /// of silence. Pass `nil` for normal completion.
    public func postSyncCompleteNotification(
        uploaded: Int,
        failed: Int,
        abortedReason: String? = nil
    ) async {
        // Synchronise toujours le badge avec l'état réel — même si les
        // notifications sont désactivées, le badge reste utile aux users qui
        // surveillent l'icône.
        let summary = await currentSummary()
        Self.updateBadgeCount(summary.pendingCount + summary.activeCount)

        guard UserDefaults.standard.bool(forKey: Self.notificationsEnabledKey) else { return }
        // Skip empty runs only on the normal-completion path. If the run
        // was aborted, we still want to inform the user.
        if abortedReason == nil {
            guard uploaded + failed > 0 else { return }
        }

        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            return  // permission not granted — silently skip
        }

        let content = UNMutableNotificationContent()
        if let reason = abortedReason {
            content.title = "Synchro Photos interrompue"
            content.body = reason
        } else {
            content.title = "Synchro Photos terminée"
            if failed == 0 {
                content.body = uploaded == 1
                    ? "1 photo sauvegardée."
                    : "\(uploaded) photos sauvegardées."
            } else if uploaded == 0 {
                content.body = failed == 1
                    ? "1 échec — voir les détails dans Rclone GUI."
                    : "\(failed) échecs — voir les détails dans Rclone GUI."
            } else {
                content.body = "\(uploaded) sauvegardée(s), \(failed) échec(s)."
            }
        }
        content.sound = .default
        content.badge = NSNumber(value: summary.pendingCount + summary.activeCount)
        // Catégorie active = boutons Pause / Reprendre visibles dans la
        // notification dépliée.
        content.categoryIdentifier = Self.progressCategoryID

        let request = UNNotificationRequest(
            identifier: Self.syncCompleteNotificationID,
            content: content,
            trigger: nil  // immediate
        )

        do {
            try await center.add(request)
        } catch {
            await LogService.shared.log(
                .error,
                category: "photos",
                message: "Failed posting sync notification: \(error.localizedDescription)"
            )
        }
    }
}

/// Single delegate routing inline notification actions to PhotoSyncService.
/// Lives outside the @MainActor service so UNUserNotificationCenter can call
/// it from its own callback queue. The methods bridge to MainActor explicitly.
public final class PhotoSyncNotificationDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    public static let shared = PhotoSyncNotificationDelegate()

    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .badge]
    }

    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        switch response.actionIdentifier {
        case PhotoSyncService.pauseActionID:
            await PhotoSyncService.shared.pausePhotoSync()
        case PhotoSyncService.resumeActionID:
            await PhotoSyncService.shared.resumePhotoSync()
        default:
            break
        }
    }
}
#endif
