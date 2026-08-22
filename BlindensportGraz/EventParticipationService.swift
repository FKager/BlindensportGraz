import Foundation
import SwiftData

/// No `delete` — see AttendanceService.swift's doc comment.
@MainActor
enum EventParticipationService {
    @discardableResult
    static func save(_ participation: EventParticipation, modelContext: ModelContext) -> Bool {
        PersistenceService.saveAndPush(modelContext: modelContext, modelName: "EventParticipation",
                                        failureMessage: "Teilnahme konnte nicht gespeichert werden.") {
            CloudKitSync.shared.pushParticipation(participation)
        }
    }
}
