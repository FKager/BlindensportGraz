import Foundation
import Supabase

/// One row of `account_admin_log`. Email and name are a snapshot, so they
/// stay readable after the account was deleted.
nonisolated struct SupabaseAccountAdminLogEntry: Decodable, Identifiable, Hashable {
    let id: Int
    let action: String
    let target: UUID
    let targetEmail: String
    let targetName: String
    let actor: UUID?
    let at: Date

    enum CodingKeys: String, CodingKey {
        case id, action, target, actor, at
        case targetEmail = "target_email"
        case targetName  = "target_name"
    }

    var targetLabel: String {
        let name = targetName.trimmingCharacters(in: .whitespaces)
        switch (name.isEmpty, targetEmail.isEmpty) {
        case (false, false): return "\(name) (\(targetEmail))"
        case (false, true): return name
        case (true, false): return targetEmail
        case (true, true): return target.uuidString
        }
    }

    var actionLabel: String {
        switch action {
        case "block": return String(localized: "gesperrt")
        case "unblock": return String(localized: "entsperrt")
        case "delete": return String(localized: "gelöscht")
        default: return action
        }
    }
}

// Root's account administration: block (lock) / unblock and delete another
// account. SECURITY DEFINER RPCs (20261014000002_account_admin) re-check
// roles.assign, refuse the caller's own account and root accounts (demote
// first), and write `account_admin_log`.
@MainActor
enum SupabaseAccountAdminService {

    private static var client: SupabaseClient { SupabaseClientSingleton.shared.client }

    // Blocking ends the account's sessions and refuses sign-in
    // (`user_banned`); unblocking lets it sign in again.
    static func setBlocked(_ blocked: Bool, userID: UUID) async throws {
        nonisolated struct Params: Encodable { let target: UUID; let blocked: Bool }
        try await client
            .rpc("set_account_blocked", params: Params(target: userID, blocked: blocked))
            .execute()
    }

    // Permanent: the auth account and every row hanging off it go.
    static func delete(userID: UUID) async throws {
        nonisolated struct Params: Encodable { let target: UUID }
        try await client.rpc("delete_account", params: Params(target: userID)).execute()
    }

    // Readable with rolelog.read (RLS); newest first.
    static func fetchLog(limit: Int = 200) async throws -> [SupabaseAccountAdminLogEntry] {
        try await client
            .from("account_admin_log")
            .select()
            .order("at", ascending: false)
            .limit(limit)
            .execute()
            .value
    }

    static func fetchBlocked() async throws -> Set<UUID> {
        nonisolated struct Row: Decodable { let user_id: UUID }
        let rows: [Row] = try await client.rpc("blocked_accounts").execute().value
        return Set(rows.map(\.user_id))
    }
}
