import Foundation

/// Fine-grained permissions, mirroring the `app_permission` enum in
/// supabase/migrations. Which role has which permission lives in the
/// `role_permissions` table (loaded into `serverTable` by `AuthContext`);
/// `defaults(for:)` is the offline fallback and must match the seed in
/// 20261008000001_rbac.sql.
nonisolated enum Permission: String, CaseIterable, Sendable {
    case eventsManage        = "events.manage"
    case teamsManage         = "teams.manage"
    case membersManage       = "members.manage"
    case membersPrivateRead  = "members.private.read"
    case membersPrivateWrite = "members.private.write"
    case usersApprove        = "users.approve"
    case rolesAssign         = "roles.assign"
    case budgetManage        = "budget.manage"
    case roleLogRead         = "rolelog.read"
    /// Club-wide scope: all teams/events, delete anyone's uploads.
    case clubManage          = "club.manage"

    /// Server mapping, replaced as a whole by `AuthContext`.
    @MainActor static var serverTable: [AppRole: Set<Permission>] = [:]

    @MainActor static func granted(to role: AppRole?) -> Set<Permission> {
        guard let role else { return [] }
        return serverTable[role] ?? defaults(for: role)
    }

    static func defaults(for role: AppRole?) -> Set<Permission> {
        let coach: Set<Permission> = [.eventsManage, .teamsManage]
        let admin = coach.union([.membersManage, .membersPrivateRead, .membersPrivateWrite,
                                 .usersApprove, .budgetManage, .roleLogRead, .clubManage])
        switch role {
        case .coach: return coach
        case .admin: return admin
        case .root: return admin.union([.rolesAssign])
        case .member, .other, .none: return []
        }
    }
}

/// The custom claims the `custom_access_token_hook` adds to every Supabase
/// access token. Decoded locally only to drive the UI — the server checks
/// permissions itself on every request.
nonisolated struct AccessClaims: Equatable, Sendable {
    let userID: UUID
    let email: String?
    /// nil = signed up but no role yet ("pending").
    let role: AppRole?
    let approved: Bool

    /// Decodes the payload of a JWT without verifying the signature (the
    /// token came from our own auth server over TLS; trust decisions are
    /// made server-side).
    static func decode(jwt: String) -> AccessClaims? {
        let parts = jwt.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var base64 = parts[1]
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        guard let data = Data(base64Encoded: base64),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sub = object["sub"] as? String, let userID = UUID(uuidString: sub)
        else { return nil }
        let role = (object["user_role"] as? String).map(AppRole.normalize)
        return AccessClaims(
            userID: userID,
            email: object["email"] as? String,
            role: role,
            approved: object["approved"] as? Bool ?? false
        )
    }
}

extension User {
    /// UI gating for any account in the local cache (also used where there
    /// is no `AuthContext`, e.g. App Intents). Role comes from Supabase via
    /// `AuthContext`; the server enforces the same rules.
    @MainActor func can(_ permission: Permission) -> Bool {
        Permission.granted(to: role).contains(permission)
    }
}
