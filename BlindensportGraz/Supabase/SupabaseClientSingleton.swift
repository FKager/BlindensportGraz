import Supabase

// Holds the single shared SupabaseClient for the lifetime of the app.
// Under SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor the class is implicitly
// @MainActor; all Supabase*Service enums are @MainActor and access `shared`
// from there. SupabaseClient is Sendable so it can cross actor boundaries
// when the SDK performs network I/O on its own executor.
final class SupabaseClientSingleton {
    static let shared = SupabaseClientSingleton()
    let client: SupabaseClient

    private init() {
        client = SupabaseClient(
            supabaseURL: SupabaseConfig.projectURL,
            supabaseKey: SupabaseConfig.anonKey
        )
    }
}
