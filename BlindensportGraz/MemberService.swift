import Foundation
import SwiftData

/// Roster edits — one of audit.md's two explicitly-prioritized areas for
/// visible failure signaling (alongside role changes), since a silently
/// failed roster save is real club-member data loss.
@MainActor
enum MemberService {
    @discardableResult
    static func save(_ member: Member, modelContext: ModelContext) -> Bool {
        PersistenceService.saveAndPush(modelContext: modelContext, modelName: "Member",
                                        failureMessage: "Mitglied konnte nicht gespeichert werden.") {
            CloudKitSync.shared.pushMember(member)
        }
    }

    /// Batch variant for `MemberImportExport`'s roster import — one save for
    /// potentially dozens of rows (the file's own doc comment: "importing a
    /// real club spreadsheet can create dozens of entries at once"), not one
    /// save per row, then pushes every touched member only on save success.
    @discardableResult
    static func saveBatch(_ members: [Member], modelContext: ModelContext) -> Bool {
        PersistenceService.saveAndPush(modelContext: modelContext, modelName: "Member (batch)",
                                        failureMessage: "Mitglieder-Import konnte nicht gespeichert werden.") {
            for member in members {
                CloudKitSync.shared.pushMember(member)
            }
        }
    }

    @discardableResult
    static func delete(_ member: Member, modelContext: ModelContext) -> Bool {
        let id = member.id
        modelContext.delete(member)
        return PersistenceService.deleteAndPush(modelContext: modelContext, modelName: "Member",
                                                 failureMessage: "Mitglied konnte nicht gelöscht werden.") {
            CloudKitSync.shared.deleteMember(id)
        }
    }
}
