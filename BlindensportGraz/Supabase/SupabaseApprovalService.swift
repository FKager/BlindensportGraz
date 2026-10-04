import Foundation
import Supabase
import SwiftData

nonisolated struct SupabaseApproval: Codable {
    let id: UUID
    let userID: UUID
    let memberID: UUID?
    let approvedBy: String
    let approvedAt: Date
    let activationCodeHash: String
    let activationCodeSalt: String

    enum CodingKeys: String, CodingKey {
        case id
        case userID             = "user_id"
        case memberID           = "member_id"
        case approvedBy         = "approved_by"
        case approvedAt         = "approved_at"
        case activationCodeHash = "activation_code_hash"
        case activationCodeSalt = "activation_code_salt"
    }
}

@MainActor
enum SupabaseApprovalService {

    @discardableResult
    static func approve(
        userID: UUID,
        memberID: UUID,
        byAdminID adminID: String
    ) async throws -> SupabaseApproval {
        nonisolated struct Row: Encodable {
            let user_id: String
            let member_id: String
            let approved_by: String
        }
        return try await SupabaseClientSingleton.shared.client
            .from("account_approvals")
            .insert(Row(user_id: userID.uuidString,
                        member_id: memberID.uuidString,
                        approved_by: adminID))
            .select()
            .single()
            .execute()
            .value
    }

    static func revoke(approvalID: UUID) async throws {
        try await SupabaseClientSingleton.shared.client
            .from("account_approvals")
            .delete()
            .eq("id", value: approvalID.uuidString)
            .execute()
    }

    // Creates an activation-code-only approval (no memberID yet) and returns
    // the plain-text code for the admin to hand to the user.
    static func createActivationCode(
        forUserID userID: UUID,
        byAdminID adminID: String
    ) async throws -> String {
        let code = ActivationCode.generate()
        let salt = PasswordHashing.makeSalt()
        let hash = PasswordHashing.hash(
            password: ActivationCode.normalized(code), salt: salt)
        nonisolated struct Row: Encodable {
            let user_id: String
            let approved_by: String
            let activation_code_hash: String
            let activation_code_salt: String
        }
        try await SupabaseClientSingleton.shared.client
            .from("account_approvals")
            .insert(Row(user_id: userID.uuidString,
                        approved_by: adminID,
                        activation_code_hash: hash,
                        activation_code_salt: salt))
            .execute()
        return code
    }

    // Pulls all approvals this device is entitled to see (RLS filters for
    // non-admins) and upserts them into the local SwiftData store.
    // Also removes local AccountApproval rows that no longer exist in Supabase
    // (revoked approvals take effect on all devices immediately).
    static func pullAll(modelContext: ModelContext) async {
        guard let rows: [SupabaseApproval] = try? await SupabaseClientSingleton.shared.client
            .from("account_approvals")
            .select()
            .execute()
            .value
        else { return }

        let remoteIDs = Set(rows.map(\.id))

        for row in rows {
            var descriptor = FetchDescriptor<AccountApproval>(
                predicate: #Predicate { $0.id == row.id })
            descriptor.fetchLimit = 1
            if let existing = try? modelContext.fetch(descriptor).first {
                existing.userID             = row.userID
                existing.memberID           = row.memberID
                existing.approvedBy         = row.approvedBy
                existing.approvedAt         = row.approvedAt
                existing.activationCodeHash = row.activationCodeHash
                existing.activationCodeSalt = row.activationCodeSalt
            } else {
                modelContext.insert(AccountApproval(
                    id: row.id,
                    userID: row.userID,
                    memberID: row.memberID,
                    approvedBy: row.approvedBy,
                    approvedAt: row.approvedAt,
                    activationCodeHash: row.activationCodeHash,
                    activationCodeSalt: row.activationCodeSalt))
            }
        }
        let allLocal = (try? modelContext.fetch(FetchDescriptor<AccountApproval>())) ?? []
        for local in allLocal where !remoteIDs.contains(local.id) {
            modelContext.delete(local)
        }
    }
}
