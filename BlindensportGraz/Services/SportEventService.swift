import Foundation
import SwiftData

/// Plain events (not trainings or tournaments, which have their own services).
@MainActor
enum SportEventService {
    @discardableResult
    static func save(_ event: SportEvent, modelContext: ModelContext) -> Bool {
        PersistenceService.saveAndPush(modelContext: modelContext, modelName: "SportEvent",
                                        failureMessage: "Event konnte nicht gespeichert werden.") {
            SupabaseSync.shared.pushEvent(event)
        }
    }

    /// Removes the event locally, then deletes it on the server and cancels
    /// its reminder, so it disappears for everyone.
    @discardableResult
    static func delete(_ event: SportEvent, modelContext: ModelContext) -> Bool {
        let id = event.id
        modelContext.delete(event)
        return PersistenceService.deleteAndPush(modelContext: modelContext, modelName: "SportEvent",
                                                 failureMessage: "Event konnte nicht gelöscht werden.") {
            EventReminderService.cancel(eventID: id)
            SupabaseSync.shared.deleteEvent(id)
        }
    }
}
