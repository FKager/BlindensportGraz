import Foundation

/// Admin actions on app accounts — thin wrappers around the Supabase RPCs
/// (`approve_account`, `revoke_approval`, `create_activation_code`,
/// `set_user_role`), which re-check the caller's permission server-side.
/// After each change the local cache is reloaded from the server.
@MainActor
enum AccountApprovalService {
    static func approve(_ user: User, as member: Member, authContext: AuthContext) async throws {
        try await SupabaseApprovalService.approve(userID: user.id, memberID: member.id)
        await authContext.reload()
    }

    static func revoke(_ user: User, authContext: AuthContext) async throws {
        try await SupabaseApprovalService.revoke(userID: user.id)
        await authContext.reload()
    }

    /// The plain code, shown once to the admin. Redeeming it approves the
    /// account for `member`, if given.
    static func createActivationCode(for user: User, member: Member?) async throws -> String {
        try await SupabaseApprovalService.createActivationCode(forUserID: user.id, memberID: member?.id)
    }

    /// `nil` removes the role (account becomes pending). The audit entry is
    /// written by a database trigger.
    static func setRole(_ role: AppRole?, for user: User, authContext: AuthContext) async throws {
        try await SupabaseRoleService.setRole(role, for: user.id)
        await authContext.reload()
    }
}
