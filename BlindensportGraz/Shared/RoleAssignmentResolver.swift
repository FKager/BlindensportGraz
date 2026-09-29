import Foundation
import SwiftData

/// Works out each account's effective role from `RoleAssignment`s and writes
/// it into the local `User.role` — on this device only, never uploaded for
/// other people's accounts — so every existing `role == .admin` / `.coach`
/// check in the app keeps working unchanged.
///
/// Only assignments from a root user (or RootCLI, "system:rootcli") count; the
/// latest one wins. Accounts without a trusted assignment keep the role
/// stored in their own record (the first account's bootstrap, older changes).
nonisolated enum RoleAssignmentResolver {
    static let rootCLIAssigner = "system:rootcli"

    static func isTrustedAssigner(_ assignerID: String, users: [User]) -> Bool {
        assignerID == rootCLIAssigner || users.contains { $0.id.uuidString == assignerID && $0.isRoot }
    }

    /// The role from the latest trusted assignment for this account, if any.
    static func effectiveRole(for user: User, assignments: [RoleAssignment], users: [User]) -> AppRole? {
        assignments
            .filter { $0.userID == user.id && isTrustedAssigner($0.assignedBy, users: users) }
            .max { $0.assignedAt < $1.assignedAt }
            .map { AppRole.normalize($0.role) }
    }

    /// Applies the effective roles to the local store (no CloudKit push).
    static func apply(in modelContext: ModelContext) {
        let users = (try? modelContext.fetch(FetchDescriptor<User>())) ?? []
        let assignments = (try? modelContext.fetch(FetchDescriptor<RoleAssignment>())) ?? []
        for user in users {
            if let role = effectiveRole(for: user, assignments: assignments, users: users), role != user.role {
                user.role = role
            }
        }
    }
}
