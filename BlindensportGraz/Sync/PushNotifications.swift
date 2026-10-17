import UIKit
import UserNotifications
import os

/// Asks for notification permission and registers with APNs; the token is
/// stored in Supabase by `PushRegistration`.
///
/// The pushes (sent by the `notify-schedule` Edge Function) are plain
/// "alert" pushes whose title/body iOS resolves itself from
/// `Localizable.xcstrings` via `title-loc-key`/`loc-key`, so they show with
/// no app code running, even if the app is fully terminated. That
/// reliability is why this avoids "silent push + build a local notification
/// in app code", which iOS does not guarantee for a terminated app.
enum PushNotifications {
    /// Requests alert/sound/badge permission and registers for remote
    /// notifications so this device has an APNs token for schedule pushes. Safe to call on every launch/login — both
    /// the permission prompt (only shown once by the OS) and the
    /// registration call are idempotent no-ops on subsequent calls.
    static func requestAuthorizationIfNeeded() {
        Task {
            do {
                _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            } catch {
                logger.error("Push authorization request failed: \(String(describing: error), privacy: .public)")
            }
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    private static let logger = Logger(subsystem: "it.a11y.BlindensportGraz", category: "PushNotifications")
}
