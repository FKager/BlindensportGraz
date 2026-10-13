import Foundation
import SwiftData

/// No `delete` — no view deletes plain SportEvent records (Training and
/// Tournament have their own services, which do delete on the server).
@MainActor
enum SportEventService {
    @discardableResult
    static func save(_ event: SportEvent, modelContext: ModelContext) -> Bool {
        PersistenceService.saveAndPush(modelContext: modelContext, modelName: "SportEvent",
                                        failureMessage: "Event konnte nicht gespeichert werden.") {
            SupabaseSync.shared.pushEvent(event)
        }
    }
}
