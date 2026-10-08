import Foundation
import Supabase
import SwiftData

nonisolated struct SupabaseRoleRow: Codable, Hashable {
    let userID: UUID
    let role: String
    let assignedAt: Date

    enum CodingKeys: String, CodingKey {
        case role
        case userID     = "user_id"
        case assignedAt = "assigned_at"
    }
}

nonisolated struct SupabaseRoleChange: Codable, Identifiable, Hashable {
    let id: Int
    let userID: UUID
    let oldRole: String?
    let newRole: String?
    let changedBy: UUID?
    let changedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userID    = "user_id"
        case oldRole   = "old_role"
        case newRole   = "new_role"
        case changedBy = "changed_by"
        case changedAt = "changed_at"
    }
}

@MainActor
enum SupabaseRoleService {

    private static var client: SupabaseClient { SupabaseClientSingleton.shared.client }

    // RPC `set_user_role`: needs roles.assign (root), refuses own role and
    // the last root. `nil` removes the role (account becomes pending).
    // The role_change_log row is written by a database trigger.
    static func setRole(_ role: AppRole?, for userID: UUID) async throws {
        nonisolated struct Params: Encodable { let target: UUID; let new_role: String? }
        try await client
            .rpc("set_user_role", params: Params(target: userID, new_role: role?.rawValue))
            .execute()
    }

    // Own row for everyone; all rows for users.approve (RLS).
    static func fetchRoles() async throws -> [SupabaseRoleRow] {
        try await client.from("user_roles").select().execute().value
    }

    static func fetchPermissionTable() async throws -> [AppRole: Set<Permission>] {
        nonisolated struct Row: Decodable { let role: String; let permission: String }
        let rows: [Row] = try await client.from("role_permissions").select().execute().value
        var table: [AppRole: Set<Permission>] = [:]
        for row in rows {
            guard let permission = Permission(rawValue: row.permission) else { continue }
            table[AppRole.normalize(row.role), default: []].insert(permission)
        }
        return table
    }

    static func fetchChangeLog(limit: Int = 200) async throws -> [SupabaseRoleChange] {
        try await client
            .from("role_change_log")
            .select()
            .order("changed_at", ascending: false)
            .limit(limit)
            .execute()
            .value
    }

    // Mirrors visible roles into the local User cache (role picker, lists).
    // Users without a row are pending and shown as plain members.
    static func applyToLocalUsers(_ rows: [SupabaseRoleRow], modelContext: ModelContext) {
        let byUser = Dictionary(rows.map { ($0.userID, AppRole.normalize($0.role)) },
                                uniquingKeysWith: { first, _ in first })
        let users = (try? modelContext.fetch(FetchDescriptor<User>())) ?? []
        for user in users {
            let role = byUser[user.id] ?? .member
            if user.role != role { user.role = role }
            if user.isRoot != (role == .root) { user.isRoot = role == .root }
        }
        try? modelContext.save()
    }
}
