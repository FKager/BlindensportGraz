import Foundation
import SwiftData

/// A root user's decision about another account's app role (Mitglied /
/// Trainer:in / Admin). The account's effective role is the latest trusted
/// assignment (`RoleAssignmentResolver`).
///
/// Separate record created by the root user, not a write to the other
/// account's `UserIdentity`: CloudKit's public database only lets a record's
/// creator change it (`WRITE _creator`), so a root user changing someone
/// else's role there never reached iCloud — it stayed on the root user's
/// device. Same pattern as `AccountApproval`.
@Model
final class RoleAssignment {
    @Attribute(.unique) var id: UUID = UUID()
    var userID: UUID = UUID()
    /// `AppRole.rawValue`.
    var role: String = AppRole.member.rawValue
    /// The assigning root user's `User.id.uuidString`, or "system:rootcli".
    var assignedBy: String = ""
    var assignedAt: Date = Date.now

    init(id: UUID = UUID(), userID: UUID, role: String, assignedBy: String, assignedAt: Date = .now) {
        self.id = id
        self.userID = userID
        self.role = role
        self.assignedBy = assignedBy
        self.assignedAt = assignedAt
    }
}
