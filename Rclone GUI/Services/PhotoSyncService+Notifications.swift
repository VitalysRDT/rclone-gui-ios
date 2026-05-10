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

#if os(iOS)
import Foundation
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
#endif
