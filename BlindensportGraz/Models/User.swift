import Foundation
import SwiftData

@Model
final class User {
    @Attribute(.unique) var id: UUID = UUID()
    var email: String = ""
    var firstName: String = ""
    var lastName: String = ""
    var role: AppRole = AppRole.member
    var appleUserIdentifier: String = ""
    var createdAt: Date = Date.now
    // Set automatically on account creation by matching against the Member roster.
    var isGrazerVSCMember: Bool = false
    // Legacy super-user flag. Root is now `role == .root` (Supabase
    // `user_roles`); kept in the schema and mirrored by AuthContext so no
    // SwiftData migration is needed. Don't read it for access decisions.
    var isRoot: Bool = false

    // Legacy (pre-Supabase) password material — always blanked now;
    // passwords live only in Supabase Auth. Kept to avoid a schema migration.
    var passwordHash: String = ""
    var passwordSalt: String = ""

    // Webcal feed token, generated/rotated server-side
    // (`profiles.calendar_token`, RPC `rotate_calendar_token`).
    var calendarToken: String = ""

    @Relationship(deleteRule: .cascade, inverse: \TeamMembership.user)
    var memberships: [TeamMembership] = []

    @Relationship(deleteRule: .cascade, inverse: \EventParticipation.user)
    var participations: [EventParticipation] = []

    init(id: UUID = UUID(),
         email: String,
         firstName: String,
         lastName: String,
         role: AppRole = .member,
         appleUserIdentifier: String = "",
         createdAt: Date = .now,
         isGrazerVSCMember: Bool = false,
         isRoot: Bool = false,
         passwordHash: String = "",
         passwordSalt: String = "") {
        self.id = id
        self.email = email
        self.firstName = firstName
        self.lastName = lastName
        self.role = role
        self.appleUserIdentifier = appleUserIdentifier
        self.createdAt = createdAt
        self.isGrazerVSCMember = isGrazerVSCMember
        self.isRoot = isRoot
        self.passwordHash = passwordHash
        self.passwordSalt = passwordSalt
    }
}

nonisolated extension User {
    /// Combines firstName/lastName for display; not stored, so it can't be
    /// used as a @Query sort key path — sort by lastName/firstName instead.
    /// Mirrors Member.fullName's pattern so existing display call sites
    /// (avatar initial, headers, member pickers) didn't need their own
    /// formatting logic.
    var displayName: String {
        [firstName, lastName].filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.joined(separator: " ")
    }

    /// The club's own account; made root on the server by the
    /// v0.2.0 account migration (never granted by the app).
    static let designatedRootEmail = "blindensport.gvsc@gmail.com"

    /// Centralizes the GVSC-membership-or-elevated-role gate for the
    /// account-tiers refactor (RSVP self-service, roster self-editing):
    /// coaches get this unconditionally, matching every other role-based
    /// gate already in the app (EventsListView/TeamsViews/TrainingsViews/
    /// TournamentsViews' identical `canManageEvents`/`canManageTeams`, none
    /// of which additionally require isGrazerVSCMember for a coach) — a
    /// coach may well be an external trainer, not a club member, but
    /// already has full CRUD rights over events/trainings/teams elsewhere.
    /// `approved`: an admin has linked this account to the Benutzerverwaltung
    /// (`AccessPolicy.approvedMember`) — checked live by the caller instead of
    /// the stored `isGrazerVSCMember` flag, which is only refreshed at login.
    func hasGVSCPrivileges(approved: Bool) -> Bool {
        approved || role == .coach || role == .admin || role == .root
    }
}
