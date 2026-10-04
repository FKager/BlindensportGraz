import Foundation
import Supabase
import SwiftData

nonisolated struct SupabaseRoleAssignment: Codable {
    let id: UUID
    let userID: UUID
    let role: String
    let assignedBy: String
    let assignedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, role
        case userID     = "user_id"
        case assignedBy = "assigned_by"
        case assignedAt = "assigned_at"
    }
}

@MainActor
enum SupabaseRoleService {

    // Inserts a role_assignments row. RLS requires the caller's profile to
    // have is_root = true — enforced server-side; mirrors the existing
    // RoleAssignmentService + RoleAssignmentResolver trusted-assigner pattern.
    static func assign(
        _ role: AppRole,
        toUserID userID: UUID,
        byAssignerID assignerID: String
    ) async throws {
        nonisolated struct Row: Encodable {
            let user_id: String
            let role: String
            let assigned_by: String
        }
        try await SupabaseClientSingleton.shared.client
            .from("role_assignments")
            .insert(Row(user_id: userID.uuidString,
                        role: role.rawValue,
                        assigned_by: assignerID))
            .execute()
    }

    // Appends a role_change_log row. RLS requires is_root = true.
    static func logChange(
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

    // Pulls all role_assignments from Supabase and applies them to local
    // SwiftData store via RoleAssignmentResolver.
    static func pullAll(modelContext: ModelContext) async {
        guard let rows: [SupabaseRoleAssignment] = try? await SupabaseClientSingleton.shared.client
            .from("role_assignments")
            .select()
            .execute()
            .value
        else { return }

        for row in rows {
            var descriptor = FetchDescriptor<RoleAssignment>(
                predicate: #Predicate { $0.id == row.id })
            descriptor.fetchLimit = 1
            if let existing = try? modelContext.fetch(descriptor).first {
                existing.userID     = row.userID
                existing.role       = row.role
                existing.assignedBy = row.assignedBy
                existing.assignedAt = row.assignedAt
            } else {
                modelContext.insert(RoleAssignment(
                    id: row.id,
                    userID: row.userID,
                    role: row.role,
                    assignedBy: row.assignedBy,
                    assignedAt: row.assignedAt))
            }
        }
        RoleAssignmentResolver.apply(in: modelContext)
    }
}
