import Foundation
import Supabase

// Holds the single shared SupabaseClient for the lifetime of the app.
// The session (access + refresh token) is persisted by the SDK in the
// Keychain; nothing auth-related is kept in UserDefaults.
final class SupabaseClientSingleton {
    static let shared = SupabaseClientSingleton()
    let client: SupabaseClient

    private init() {
        // An unconfigured build still launches (anonymous schedule view);
        // every auth call then fails with a network error.
        let url = SupabaseConfig.projectURL ?? URL(string: "https://unconfigured.invalid")!
        client = SupabaseClient(
            supabaseURL: url,
            supabaseKey: SupabaseConfig.anonKey,
            options: SupabaseClientOptions(
                auth: .init(
                    redirectToURL: SupabaseConfig.redirectURL,
                    // Opt in to the next-major behaviour: show the stored
                    // session immediately, refresh in the background.
                    emitLocalSessionAsInitialSession: true
                )
            )
        )
    }
}
