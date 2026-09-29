import Foundation
import SwiftData

/// Root users changing someone's app role — see `RoleAssignment`.
@MainActor
enum RoleAssignmentService {
    /// Records the new role as a `RoleAssignment` owned by `assigner`, applies
    /// it locally right away, and logs it in "Rollenänderungen". Never
    /// uploads the other account's own record.
    @discardableResult
    static func assign(_ role: AppRole, to user: User, by assigner: User, modelContext: ModelContext) -> Bool {
        let oldRole = user.role
        guard role != oldRole else { return true }
        let assignment = RoleAssignment(userID: user.id, role: role.rawValue, assignedBy: assigner.id.uuidString)
        modelContext.insert(assignment)
        user.role = role
        let saved = PersistenceService.saveAndPush(modelContext: modelContext, modelName: "RoleAssignment",
                                                    failureMessage: "Rollenänderung konnte nicht gespeichert werden.") {
            CloudKitSync.shared.pushRoleAssignment(assignment)
        }
        guard saved else { return false }
        RoleChangeLogService.log(userID: user.id, oldRole: oldRole.rawValue, newRole: role.rawValue,
                                 changedBy: assigner.id.uuidString, modelContext: modelContext)
        return true
    }
}
