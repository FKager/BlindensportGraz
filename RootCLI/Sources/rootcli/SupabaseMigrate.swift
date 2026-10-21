import Foundation
import CloudKitS2SCore

/// Supabase account commands: password-reset emails after the v0.2.0 auth
/// migration, and role assignment. Needs SUPABASE_URL / SUPABASE_SERVICE_KEY.
enum SupabaseMigrate {
    static let redirectURL = "blindensportgraz://auth-callback"

    // MARK: - supabase-send-resets

    static func runSendResets(_ args: [String]) async throws {
        let apply = try applyFlag(args, usage: "rootcli supabase-send-resets --dry-run|--apply")
        let supabase = try SupabaseAdminClient.fromEnvironment()
        let users = try await supabase.listUsers().filter { !($0.email ?? "").isEmpty }
        print("\(users.count) accounts with email.")
        for user in users {
            print("  → \(user.email!)")
            if apply {
                try await supabase.sendPasswordReset(email: user.email!, redirectTo: redirectURL)
                // Stay well below the auth email rate limit.
                try await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
        if !apply { print("Dry run — no emails sent. Re-run with --apply.") }
    }

    // MARK: - set-role

    enum Role: String { case member, coach, admin, root }

    static func runSetRole(_ args: [String]) async throws {
        guard args.count == 2, let role = Role(rawValue: args[1]) else {
            throw CLIError.message("Usage: rootcli set-role <email|user id> <member|coach|admin|root>")
        }
        let supabase = try SupabaseAdminClient.fromEnvironment()
        let needle = args[0].lowercased()
        let users = try await supabase.listUsers()
        guard let user = users.first(where: { $0.id.uuidString.lowercased() == needle || $0.email?.lowercased() == needle }) else {
            throw CLIError.message("No Supabase account with email or id '\(args[0])'.")
        }
        // Service key: the role_change_log trigger records changed_by = null (System).
        try await supabase.upsert(table: "user_roles",
                                  rows: [["user_id": user.id.uuidString.lowercased(), "role": role.rawValue,
                                          "assigned_at": iso(Date())]],
                                  onConflict: "user_id")
        print("Updated \(user.email ?? user.id.uuidString): role -> \(role.rawValue)")
    }

    // MARK: - helpers

    private static func applyFlag(_ args: [String], usage: String) throws -> Bool {
        switch args.first {
        case "--apply": return true
        case "--dry-run", nil: return false
        default: throw CLIError.message("Usage: \(usage)")
        }
    }

    private static func iso(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}
