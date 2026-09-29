import Foundation
import SwiftData

/// No `delete` — `CloudKitSync` never had a delete path for plain
/// SportEvent (or Training/Tournament) records; not invented here, matching
/// Phase 6's same "don't add functionality that wasn't there" scoping.
@MainActor
enum SportEventService {
    @discardableResult
    static func save(_ event: SportEvent, modelContext: ModelContext) -> Bool {
        PersistenceService.saveAndPush(modelContext: modelContext, modelName: "SportEvent",
                                        failureMessage: "Event konnte nicht gespeichert werden.") {
            CloudKitSync.shared.pushEvent(event)
        }
    }
}
