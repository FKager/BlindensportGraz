import Foundation

// Fill in these values from your Supabase project dashboard (Settings → API).
// The anon key is non-secret — it is safe to ship in the binary.
// RLS policies (Row Level Security) enforce access control server-side.
nonisolated enum SupabaseConfig {
    static let projectURL = URL(string: "https://YOUR_PROJECT_REF.supabase.co")!
    static let anonKey    = "YOUR_SUPABASE_ANON_KEY"
}
