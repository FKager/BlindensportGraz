import Foundation
import Supabase
import SwiftData

nonisolated struct SupabaseApproval: Codable, Hashable {
    let userID: UUID
    let memberID: UUID
    let approvedBy: UUID?
    let approvedAt: Date

    enum CodingKeys: String, CodingKey {
        case userID     = "user_id"
        case memberID   = "member_id"
        case approvedBy = "approved_by"
        case approvedAt = "approved_at"
    }
}

// All writes go through SECURITY DEFINER RPCs that re-check users.approve
// against the tables; activation codes are generated and hashed server-side.
@MainActor
enum SupabaseApprovalService {

    private static var client: SupabaseClient { SupabaseClientSingleton.shared.client }

    static func approve(userID: UUID, memberID: UUID) async throws {
        nonisolated struct Params: Encodable { let target: UUID; let p_member_id: UUID }
        try await client
            .rpc("approve_account", params: Params(target: userID, p_member_id: memberID))
            .execute()
    }

    static func revoke(userID: UUID) async throws {
        nonisolated struct Params: Encodable { let target: UUID }
        try await client.rpc("revoke_approval", params: Params(target: userID)).execute()
    }

    // Returns the plain code ("ABCD-EFGH") exactly once, for the admin to
    // hand over. Redeeming it approves the account for `memberID`, if given.
    static func createActivationCode(forUserID userID: UUID, memberID: UUID?) async throws -> String {
        nonisolated struct Params: Encodable { let target: UUID; let p_member_id: UUID? }
        return try await client
            .rpc("create_activation_code", params: Params(target: userID, p_member_id: memberID))
            .execute()
            .value
    }

    // For the signed-in user. Returns false for an unknown, used, expired or
    // someone else's code.
    static func redeemActivationCode(_ code: String) async throws -> Bool {
        nonisolated struct Params: Encodable { let code: String }
        return try await client
            .rpc("redeem_activation_code", params: Params(code: code))
            .execute()
            .value
    }

    // Own row for everyone; all rows for users.approve (RLS).
    static func fetchAll() async throws -> [SupabaseApproval] {
        try await client.from("account_approvals").select().execute().value
    }

    // Mirrors the visible approvals into the device-local AccountApproval
    // cache (AccessPolicy, widget). Removes rows that were revoked.
    static func applyToLocal(_ rows: [SupabaseApproval], modelContext: ModelContext) {
        let local = (try? modelContext.fetch(FetchDescriptor<AccountApproval>())) ?? []
        var byUser = Dictionary(grouping: local, by: \.userID)
        for row in rows {
            var existing = byUser.removeValue(forKey: row.userID) ?? []
            let keep = existing.popLast() ?? {
                let approval = AccountApproval(userID: row.userID, memberID: row.memberID,
                                               approvedBy: "")
                modelContext.insert(approval)
                return approval
            }()
            keep.memberID   = row.memberID
            keep.approvedBy = row.approvedBy?.uuidString ?? "system"
            keep.approvedAt = row.approvedAt
            keep.activationCodeHash = ""
            keep.activationCodeSalt = ""
            existing.forEach(modelContext.delete)
        }
        byUser.values.flatMap { $0 }.forEach(modelContext.delete)
        try? modelContext.save()
    }
}
