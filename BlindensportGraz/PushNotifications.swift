import UIKit
import UserNotifications

/// Registers this device for push notifications so CloudKit's
/// `CKQuerySubscription`s (see `CloudKitSync.ensureTrainingTournamentSubscriptions`)
/// can actually deliver a native alert when a Training/Tournament is created
/// for one of the current user's teams.
///
/// Deliberately does NOT use an AppDelegate/`didReceiveRemoteNotification` —
/// the subscriptions this feeds are plain "alert" pushes (title/body
/// resolved by iOS itself from `Localizable.xcstrings`, via
/// `CKSubscription.NotificationInfo`'s `titleLocalizationKey`/
/// `alertLocalizationKey`+`Args`), which the OS displays directly with no
/// app code running at all, even if the app is fully terminated. That
/// reliability — it still works for a team member who hasn't opened the
/// app in weeks — is why this avoids the alternative "silent/
/// content-available push + construct a local notification in app code"
/// pattern, which iOS does not guarantee delivering to a fully terminated
/// app.
enum PushNotifications {
    /// Requests alert/sound/badge permission and registers for remote
    /// notifications so this device has an APNs token CloudKit can route
    /// subscription pushes to. Safe to call on every launch/login — both
    /// the permission prompt (only shown once by the OS) and the
    /// registration call are idempotent no-ops on subsequent calls.
    static func requestAuthorizationIfNeeded() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, error in
            if let error {
                print("PushNotifications authorization request failed: \(error)")
            }
            DispatchQueue.main.async {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }
}
