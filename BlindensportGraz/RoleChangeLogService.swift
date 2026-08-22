import Foundation
import SwiftData

/// Supersedes `CloudKitSync.logRoleChange` (Phase 2) — same shape, but now
/// routes through `PersistenceService` so a local save failure is logged +
/// signaled via `ServiceFailureSignal` instead of a bare `try?`, and the
/// CloudKit push is skipped on failure. Role-change logging is one of
/// audit.md's two explicitly-prioritized areas for visible failure
/// signaling (alongside roster edits, see MemberService.swift).
@MainActor
enum RoleChangeLogService {
    @discardableResult
    static func log(userID: UUID, oldRole: String, newRole: String, changedBy: String, modelContext: ModelContext) -> Bool {
        let entry = RoleChangeLog(userID: userID, oldRole: oldRole, newRole: newRole, changedBy: changedBy)
        modelContext.insert(entry)
        return PersistenceService.saveAndPush(modelContext: modelContext, modelName: "RoleChangeLog",
                                               failureMessage: "Rollenänderung konnte nicht protokolliert werden.") {
            CloudKitSync.shared.pushRoleChangeLog(entry)
        }
    }
}
