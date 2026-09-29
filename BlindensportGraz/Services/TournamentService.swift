import Foundation
import SwiftData

/// `delete` only cancels the local reminder (see `EventReminderService`) and
/// saves the removal — no CloudKit delete push, that scoping still stands
/// per SportEventService.swift's doc comment (no CloudKit delete path exists
/// for Tournament records).
@MainActor
enum TournamentService {
    @discardableResult
    static func save(_ tournament: Tournament, modelContext: ModelContext) -> Bool {
        let saved = PersistenceService.saveAndPush(modelContext: modelContext, modelName: "Tournament",
                                        failureMessage: "Turnier konnte nicht gespeichert werden.") {
            CloudKitSync.shared.pushTournament(tournament)
        }
        if saved {
            EventReminderService.reschedule(eventID: tournament.id, title: tournament.title,
                                             sportLabel: tournament.sport, startDate: tournament.startDate)
        }
        return saved
    }

    /// Caller has already called `modelContext.delete(tournament)` before
    /// this — same contract as `PersistenceService.deleteAndPush`.
    @discardableResult
    static func delete(_ tournament: Tournament, modelContext: ModelContext) -> Bool {
        let id = tournament.id
        return PersistenceService.deleteAndPush(modelContext: modelContext, modelName: "Tournament",
                                                  failureMessage: "Turnier konnte nicht gelöscht werden.") {
            EventReminderService.cancel(eventID: id)
        }
    }
}
