import Foundation
import SwiftData

/// Exactly one of `user`/`member` is set, never both/neither. `user` covers
/// people with a registered app account; `member` covers Grazer VSC roster
/// entries who haven't signed into the app yet — teams routinely include both,
/// since real club rosters aren't 1:1 with app installs.
@Model
final class TeamMembership {
    @Attribute(.unique) var id: UUID = UUID()
    var user: User?
    var member: Member?
    var team: Team
    var role: MembershipRole = MembershipRole.player
    var joinedAt: Date = Date.now

    // Attendance.membership is a non-optional to-one relationship — without
    // this explicit cascade+inverse, deleting a TeamMembership (TeamsViews'
    // roster swipe-to-delete, or via Team's own cascade delete) leaves
    // SwiftData trying to nullify a non-optional property on any dependent
    // Attendance, which corrupts that Attendance's backing row instead of
    // failing cleanly — any later access to `attendance.membership.id`
    // (TrainingDetailView/TournamentDetailView.attendance(for:)) then
    // crashes with a fatal SwiftData assertion. See bug-163.
    @Relationship(deleteRule: .cascade, inverse: \Attendance.membership)
    var attendances: [Attendance] = []

    init(id: UUID = UUID(),
         user: User? = nil,
         member: Member? = nil,
         team: Team,
         role: MembershipRole = .player,
         joinedAt: Date = .now) {
        self.id = id
        self.user = user
        self.member = member
        self.team = team
        self.role = role
        self.joinedAt = joinedAt
    }
}

extension TeamMembership {
    var displayName: String {
        user?.displayName ?? member?.fullName ?? "?"
    }

    // Same user/member fallback chain as displayName — TeamMembership has no
    // stored lastName/firstName of its own, only via whichever of user/member
    // is set.
    var lastName: String { user?.lastName ?? member?.lastName ?? "" }
    var firstName: String { user?.firstName ?? member?.firstName ?? "" }

    /// Secondary line under the name in member lists: indicates whether this
    /// roster entry is linked to a registered app account, or is roster-only
    /// (no account yet). Used to be "@username", but User no longer has a
    /// username field — email can't be shown here instead since it's
    /// deliberately never synced to CloudKit (see CloudKitSync's doc
    /// comment), so a `user` pulled from another device would show blank.
    var subtitle: String {
        if user != nil { return "Konto vorhanden" }
        return "Grazer VSC – kein Konto"
    }
}

extension Sequence where Element == TeamMembership {
    /// Standard sort order for every member list in the app: lastName, then
    /// firstName as a tiebreaker — matches how User/Member rosters are
    /// already sorted (RootView.LoginView, MembersListView).
    func sortedByLastName() -> [TeamMembership] {
        sorted { ($0.lastName, $0.firstName) < ($1.lastName, $1.firstName) }
    }
}
