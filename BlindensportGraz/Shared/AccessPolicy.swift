import Foundation

/// Who may use the full app. Everyone else — anonymous visitors and signed-in
/// accounts without an admin approval — only sees the upcoming schedule
/// (name, date, location; `UpcomingScheduleSections`).
///
/// Full access needs an `AccountApproval` from an admin linking the account to
/// an entry in the Benutzerverwaltung. A matching name or email alone is NOT
/// enough: registration verifies neither, so anyone could register with a
/// member's name. Such matches are only offered to admins as suggestions
/// (`suggestedMember`).
nonisolated enum AccessPolicy {
    /// Admins and root always have full access (so the club's own root
    /// account can never lock itself out); anyone else needs an approval by
    /// an admin/root for a Benutzerverwaltung entry that still exists.
    static func hasFullAccess(_ user: User, roster: [Member], approvals: [AccountApproval], users: [User]) -> Bool {
        user.role == .admin || user.isRoot
            || approvedMember(for: user, roster: roster, approvals: approvals, users: users) != nil
    }

    /// The Benutzerverwaltung entry an admin confirmed as this account's — the
    /// only entry "Vereinsdaten bearbeiten" may open.
    static func approvedMember(for user: User, roster: [Member], approvals: [AccountApproval], users: [User]) -> Member? {
        let approvedIDs = approvals
            .filter { $0.userID == user.id && isTrustedApprover($0.approvedBy, users: users) }
            .sorted { $0.approvedAt > $1.approvedAt }
            .compactMap(\.memberID)
        for id in approvedIDs {
            if let member = roster.first(where: { $0.id == id }) { return member }
        }
        return nil
    }

    /// The approval currently linking this account, if any (for revoking).
    static func activeApproval(for user: User, roster: [Member], approvals: [AccountApproval], users: [User]) -> AccountApproval? {
        guard let member = approvedMember(for: user, roster: roster, approvals: approvals, users: users) else { return nil }
        return approvals
            .filter { $0.userID == user.id && $0.memberID == member.id && isTrustedApprover($0.approvedBy, users: users) }
            .max { $0.approvedAt < $1.approvedAt }
    }

    /// A likely roster entry for an unapproved account — for admins only.
    /// Email match first (`.email`), else first + last name (`.name`).
    static func suggestedMember(for user: User, roster: [Member]) -> (member: Member, byEmail: Bool)? {
        let email = user.email.trimmingCharacters(in: .whitespaces).lowercased()
        if !email.isEmpty, let member = roster.first(where: {
            $0.email.trimmingCharacters(in: .whitespaces).lowercased() == email
        }) {
            return (member, true)
        }
        return Member.first(matching: user, in: roster).map { ($0, false) }
    }

    /// Approvals only count when made by someone who is admin or root now.
    static func isTrustedApprover(_ approverID: String, users: [User]) -> Bool {
        users.contains { $0.id.uuidString == approverID && ($0.role == .admin || $0.isRoot) }
    }

    /// Whether another account already uses this email (case-insensitive).
    /// Emails identify accounts at login and the club's root account, so they
    /// must be unique.
    static func isEmailTaken(_ email: String, by users: [User], except user: User? = nil) -> Bool {
        let needle = email.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return false }
        return users.contains { $0.id != user?.id && $0.email.trimmingCharacters(in: .whitespaces).lowercased() == needle }
    }
}
