import Foundation
import Supabase

// Root's account administration: block (lock) / unblock and delete another
// account. SECURITY DEFINER RPCs (20261014000002_account_admin) re-check
// roles.assign and refuse the caller's own account.
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

    static func fetchBlocked() async throws -> Set<UUID> {
        nonisolated struct Row: Decodable { let user_id: UUID }
        let rows: [Row] = try await client.rpc("blocked_accounts").execute().value
        return Set(rows.map(\.user_id))
    }
}
