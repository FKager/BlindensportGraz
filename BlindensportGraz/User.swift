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
    // Super-user flag, distinct from `role`. Only a root account can change another
    // account's `role`; nobody (including root) can change their own via the app —
    // see EditAccountView/UserListView. Set by RootView on first-ever account
    // creation, automatically for the club's designated account (see
    // elevateIfDesignatedRoot below), or externally via the RootCLI tool talking
    // directly to CloudKit.
    var isRoot: Bool = false

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
         isRoot: Bool = false) {
        self.id = id
        self.email = email
        self.firstName = firstName
        self.lastName = lastName
        self.role = role
        self.appleUserIdentifier = appleUserIdentifier
        self.createdAt = createdAt
        self.isGrazerVSCMember = isGrazerVSCMember
        self.isRoot = isRoot
    }
}

extension User {
    /// Combines firstName/lastName for display; not stored, so it can't be
    /// used as a @Query sort key path — sort by lastName/firstName instead.
    /// Mirrors Member.fullName's pattern so existing display call sites
    /// (avatar initial, headers, member pickers) didn't need their own
    /// formatting logic.
    var displayName: String {
        [firstName, lastName].filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.joined(separator: " ")
    }

    // Grants root/admin automatically to the club's designated account, matched
    // by firstName + lastName + email together — no Apple Sign-In/
    // appleUserIdentifier gate. Originally gated on a verified Apple email
    // (see RootView's old designatedRootEmail), but that account has no real
    // Apple ID and is always created via RegisterView's manual form, so an
    // Apple-verification requirement could never fire. Requiring all three
    // fields (not email alone) keeps the bar for typing your way to root
    // reasonably high even without Apple's server-side verification. Called
    // from every place these three fields can be set/edited: RootView's
    // account-resolution/login paths, RegisterView's manual creation, and
    // EditAccountView whenever firstName/lastName/email change.
    static let designatedRootFirstName = "Blindensport"
    static let designatedRootLastName = "Graz"
    static let designatedRootEmail = "blindensport.gvsc@gmail.com"

    @discardableResult
    func elevateIfDesignatedRoot() -> Bool {
        guard firstName.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(User.designatedRootFirstName) == .orderedSame,
              lastName.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(User.designatedRootLastName) == .orderedSame,
              email.trimmingCharacters(in: .whitespaces).lowercased() == User.designatedRootEmail,
              !isRoot else { return false }
        isRoot = true
        role = .admin
        return true
    }

}
