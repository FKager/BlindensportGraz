import Foundation
import Supabase

// Writes to the Supabase `role_change_log` table (admin-read, root-insert RLS).
// Replaces RoleChangeLogService's CloudKit push for accounts whose role
// assignment goes through SupabaseRoleService.
@MainActor
enum SupabaseRoleChangeLogService {

    static func insert(
        userID: UUID,
        oldRole: String,
        newRole: String,
        changedBy: String
    ) async throws {
        nonisolated struct Row: Encodable {
            let user_id: String
            let old_role: String
            let new_role: String
            let changed_by: String
        }
        try await SupabaseClientSingleton.shared.client
            .from("role_change_log")
            .insert(Row(user_id: userID.uuidString,
                        old_role: oldRole,
                        new_role: newRole,
                        changed_by: changedBy))
            .execute()
    }
}
