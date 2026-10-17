import Foundation
import SwiftData

/// `delete` cancels the local reminder (see `EventReminderService`) and
/// deletes the tournament on the server too, so it disappears for everyone.
@MainActor
enum TournamentService {
    @discardableResult
    static func save(_ tournament: Tournament, modelContext: ModelContext) -> Bool {
        let saved = PersistenceService.saveAndPush(modelContext: modelContext, modelName: "Tournament",
                                        failureMessage: "Turnier konnte nicht gespeichert werden.") {
            SupabaseSync.shared.pushTournament(tournament)
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
            SupabaseSync.shared.deleteEvent(id)
        }
    }
}
