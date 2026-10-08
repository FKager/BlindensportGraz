import Foundation

// Values come from the SUPABASE_URL / SUPABASE_ANON_KEY build settings
// (project.yml), passed through Info.plist. The anon (publishable) key is
// not a secret — RLS policies enforce access server-side. The service-role
// key must never be added here.
nonisolated enum SupabaseConfig {
    static let redirectURL = URL(string: "blindensportgraz://auth-callback")!

    static var projectURL: URL? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "SupabaseURL") as? String,
              !raw.isEmpty, let url = URL(string: raw) else { return nil }
        return url
    }

    static var anonKey: String {
        (Bundle.main.object(forInfoDictionaryKey: "SupabaseAnonKey") as? String) ?? ""
    }

    static var isConfigured: Bool { projectURL != nil && !anonKey.isEmpty }

    static func isAuthCallback(_ url: URL) -> Bool {
        url.scheme == redirectURL.scheme && url.host == redirectURL.host
    }
}
