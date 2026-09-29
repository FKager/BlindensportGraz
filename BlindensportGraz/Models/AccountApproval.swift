import Foundation
import SwiftData

/// An admin's confirmation that an app account (`User`) really belongs to a
/// person in the Benutzerverwaltung (`Member`) — the only thing that grants
/// full app access (see `AccessPolicy`). Matching by name or email alone is
/// NOT enough: registration verifies neither, so anyone could type in a
/// member's name. Name/email matches are only shown to admins as suggestions.
///
/// Created by the approving admin, never by the account itself: CloudKit's
/// public database only lets a record's creator change it (`WRITE _creator`),
/// so an admin can't mark someone else's `UserIdentity` record as approved —
/// but can create and delete an approval they own.
///
/// Also carries an optional one-time activation code (hash + salt only) for
/// accounts that have no password yet: the person must enter the code an
/// admin gave them before they can set a password, so nobody can claim such
/// an account just by knowing its email.
@Model
final class AccountApproval {
    @Attribute(.unique) var id: UUID = UUID()
    /// The approved `User.id`.
    var userID: UUID = UUID()
    /// The linked `Member.id`; nil for an activation code without a roster link.
    var memberID: UUID?
    /// The approving admin's `User.id.uuidString`.
    var approvedBy: String = ""
    var approvedAt: Date = Date.now
    var activationCodeHash: String = ""
    var activationCodeSalt: String = ""

    init(id: UUID = UUID(), userID: UUID, memberID: UUID?, approvedBy: String, approvedAt: Date = .now,
         activationCodeHash: String = "", activationCodeSalt: String = "") {
        self.id = id
        self.userID = userID
        self.memberID = memberID
        self.approvedBy = approvedBy
        self.approvedAt = approvedAt
        self.activationCodeHash = activationCodeHash
        self.activationCodeSalt = activationCodeSalt
    }
}
