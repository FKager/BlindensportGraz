import Foundation
import Supabase
import UIKit
import os

/// Registers this device's APNs token in Supabase (`device_tokens`) so the
/// `notify-schedule` Edge Function can send "Training neu / geändert /
/// abgesagt" pushes. Who gets which push is decided on the server from team
/// memberships; the app only says "this device belongs to this account".
/// The pushes are plain alert pushes with localization keys, shown by iOS
/// even when the app isn't running.
@MainActor
final class PushRegistration {
    static let shared = PushRegistration()
    private let logger = Logger(subsystem: "it.a11y.BlindensportGraz", category: "PushRegistration")
    private var client: SupabaseClient { SupabaseClientSingleton.shared.client }
    private var token: String?

    /// APNs environment of this build: Debug builds talk to the sandbox,
    /// TestFlight/App Store builds to production.
    private var environment: String {
        #if DEBUG
        "sandbox"
        #else
        "production"
        #endif
    }

    /// Asks for permission (once) and registers with APNs; the token arrives
    /// in `didReceive(deviceToken:)`. Only for signed-in accounts with full
    /// access — anyone else gets no schedule pushes.
    func registerIfAllowed() async {
        guard let auth = AuthContext.current, auth.isSignedIn, auth.hasFullAccess
                || auth.role == .admin || auth.role == .root else { return }
        PushNotifications.requestAuthorizationIfNeeded()
        await upload()
    }

    func didReceive(deviceToken: Data) {
        token = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { await upload() }
    }

    private func upload() async {
        guard let token, let userID = AuthContext.current?.claims?.userID else { return }
        struct Row: Encodable {
            let token: String
            let user_id: UUID
            let apns_env: String
        }
        do {
            try await client.from("device_tokens")
                .upsert(Row(token: token, user_id: userID, apns_env: environment), onConflict: "token",
                        returning: .minimal)
                .execute()
        } catch {
            logger.error("device token upload failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// Called before signing out: this device stops getting the account's pushes.
    func unregister() async {
        guard let token else { return }
        _ = try? await client.from("device_tokens").delete().eq("token", value: token).execute()
    }
}

/// Receives the APNs device token (SwiftUI has no other hook for it).
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { @MainActor in PushRegistration.shared.didReceive(deviceToken: deviceToken) }
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Logger(subsystem: "it.a11y.BlindensportGraz", category: "PushRegistration")
            .error("APNs registration failed: \(String(describing: error), privacy: .public)")
    }
}
