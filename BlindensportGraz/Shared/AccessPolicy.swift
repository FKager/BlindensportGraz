import Foundation

/// Who may use the full app. Everyone else — anonymous visitors and signed-in
/// accounts that aren't listed in the Benutzerverwaltung — only sees the
/// upcoming schedule (name, date, location; `UpcomingScheduleSections`).
enum AccessPolicy {
    /// Admins and the root account always have full access (so the club's
    /// own root account can never lock itself out); anyone else needs a
    /// matching entry in the Benutzerverwaltung — matched live by email or
    /// first + last name, the same rule as "Vereinsdaten bearbeiten".
    static func hasFullAccess(_ user: User, roster: [Member]) -> Bool {
        user.role == .admin || user.isRoot || Member.first(matching: user, in: roster) != nil
    }
}
