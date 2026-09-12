import Foundation
import SwiftData

@MainActor
enum EventMembershipService {
    @discardableResult
    static func save(_ membership: EventMembership, modelContext: ModelContext) -> Bool {
        PersistenceService.saveAndPush(modelContext: modelContext, modelName: "EventMembership",
                                        failureMessage: "Mitglied konnte nicht hinzugefügt werden.") {
            CloudKitSync.shared.pushEventMembership(membership)
        }
    }

    @discardableResult
    static func delete(_ membership: EventMembership, modelContext: ModelContext) -> Bool {
        let id = membership.id
        modelContext.delete(membership)
        return PersistenceService.deleteAndPush(modelContext: modelContext, modelName: "EventMembership",
                                                 failureMessage: "Mitglied konnte nicht entfernt werden.") {
            CloudKitSync.shared.deleteEventMembership(id)
        }
    }
}
