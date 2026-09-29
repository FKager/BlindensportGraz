import Foundation
import SwiftData

@MainActor
enum TeamMembershipService {
    @discardableResult
    static func save(_ membership: TeamMembership, modelContext: ModelContext) -> Bool {
        PersistenceService.saveAndPush(modelContext: modelContext, modelName: "TeamMembership",
                                        failureMessage: "Mitgliedschaft konnte nicht gespeichert werden.") {
            CloudKitSync.shared.pushMembership(membership)
        }
    }

    @discardableResult
    static func delete(_ membership: TeamMembership, modelContext: ModelContext) -> Bool {
        let id = membership.id
        modelContext.delete(membership)
        return PersistenceService.deleteAndPush(modelContext: modelContext, modelName: "TeamMembership",
                                                 failureMessage: "Mitgliedschaft konnte nicht gelöscht werden.") {
            CloudKitSync.shared.deleteMembership(id)
        }
    }
}
