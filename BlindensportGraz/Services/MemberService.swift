import Foundation
import SwiftData

/// Roster edits — one of audit.md's two explicitly-prioritized areas for
/// visible failure signaling (alongside role changes), since a silently
/// failed roster save is real club-member data loss. Sensitive fields go to
/// `member_private` (`MemberPrivateSync`), the rest to `members`/`member_contacts`.
@MainActor
enum MemberService {
    @discardableResult
    static func save(_ member: Member, modelContext: ModelContext) -> Bool {
        PersistenceService.saveAndPush(modelContext: modelContext, modelName: "Member",
                                        failureMessage: "Mitglied konnte nicht gespeichert werden.") {
            SupabaseSync.shared.pushMember(member)
            MemberPrivateSync.push([member])
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
                SupabaseSync.shared.pushMember(member)
            }
            MemberPrivateSync.push(members)
        }
    }

    /// Removes an entry for good. The server decides: only root, only an entry
    /// marked "delete", and `confirmName` must be the person's full name
    /// (`delete_member`, the only way to delete a member). So this needs a
    /// connection, unlike the outbox-backed writes, and the local copy goes
    /// only once the server has agreed.
    static func delete(_ member: Member, confirmName: String, modelContext: ModelContext) async throws {
        nonisolated struct Params: Encodable { let target: UUID; let confirm_name: String }
        try await SupabaseClientSingleton.shared.client
            .rpc("delete_member", params: Params(target: member.id, confirm_name: confirmName))
            .execute()
        modelContext.delete(member)
        PersistenceService.deleteAndPush(modelContext: modelContext, modelName: "Member",
                                         failureMessage: "Mitglied konnte nicht gelöscht werden.") {}
    }
}
