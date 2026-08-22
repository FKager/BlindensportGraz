import Foundation
import SwiftData

/// Audit trail entry for a `User.role`/`isRoot` change — added per audit.md's
/// P0 enhancement #2, directly following Security Findings 1 & 2 (the
/// now-removed test-admin backdoor and the designated-root escalation path).
/// Deliberately holds only the affected user's `id` (not a live relationship)
/// so an entry survives even if the user record is later deleted, matching
/// how an audit log is meant to outlive the thing it describes.
///
/// `oldRole`/`newRole` stay plain `String` (not `AppRole`) deliberately —
/// this is a historical audit log, not a live field; it must be able to
/// record whatever string was ACTUALLY in `User.role` at the time, even a
/// legacy/garbled one, without going through `AppRole`'s own normalization
/// first (that normalization happens, if at all, only when something reads
/// the log back for display — see `AppRole.normalize`).
@Model
final class RoleChangeLog {
    @Attribute(.unique) var id: UUID = UUID()
    var userID: UUID
    var oldRole: String = ""
    var newRole: String = ""
    // The acting admin/root's own User.id (as a UUID string), or a fixed
    // "system:<mechanism>" tag for grants that happen without an acting
    // user in the loop (e.g. "system:designatedRoot" for the bootstrap
    // auto-grant, "system:rootcli" for a RootCLI-issued change).
    var changedBy: String = ""
    var changedAt: Date = Date.now

    init(id: UUID = UUID(),
         userID: UUID,
         oldRole: String,
         newRole: String,
         changedBy: String,
         changedAt: Date = .now) {
        self.id = id
        self.userID = userID
        self.oldRole = oldRole
        self.newRole = newRole
        self.changedBy = changedBy
        self.changedAt = changedAt
    }
}
