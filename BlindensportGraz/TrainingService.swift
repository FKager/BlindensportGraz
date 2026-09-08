import Foundation
import SwiftData

/// `delete` only cancels the local reminder (see `EventReminderService`) and
/// saves the removal — no CloudKit delete push, that scoping still stands
/// per SportEventService.swift's doc comment (no CloudKit delete path exists
/// for Training records).
@MainActor
enum TrainingService {
    @discardableResult
    static func save(_ training: Training, modelContext: ModelContext) -> Bool {
        let saved = PersistenceService.saveAndPush(modelContext: modelContext, modelName: "Training",
                                        failureMessage: "Training konnte nicht gespeichert werden.") {
            CloudKitSync.shared.pushTraining(training)
        }
        if saved {
            EventReminderService.reschedule(eventID: training.id, title: training.title,
                                             sportLabel: training.sport, startDate: training.startDate)
        }
        return saved
    }

    /// Caller has already called `modelContext.delete(training)` before
    /// this — same contract as `PersistenceService.deleteAndPush`.
    @discardableResult
    static func delete(_ training: Training, modelContext: ModelContext) -> Bool {
        let id = training.id
        return PersistenceService.deleteAndPush(modelContext: modelContext, modelName: "Training",
                                                  failureMessage: "Training konnte nicht gelöscht werden.") {
            EventReminderService.cancel(eventID: id)
        }
    }

    /// Batch variant for `TrainingImportExport`'s import — one save for the
    /// whole file, not one per row, then pushes every touched training only
    /// on save success (previously pushed unconditionally mid-loop, before
    /// the batch save even ran — this fixes that ordering too).
    @discardableResult
    static func saveBatch(_ trainings: [Training], modelContext: ModelContext) -> Bool {
        PersistenceService.saveAndPush(modelContext: modelContext, modelName: "Training (batch)",
                                        failureMessage: "Trainings-Import konnte nicht gespeichert werden.") {
            for training in trainings {
                CloudKitSync.shared.pushTraining(training)
            }
        }
    }

    /// Splits `startDates` into those free for a new training and those
    /// already taken by an existing event of any kind at the same (title,
    /// sport, minute) — the exact uniqueness rule `AddTrainingView` enforces,
    /// applied ahead of a bulk series create so the UI can preview how many
    /// dates will be skipped. Pure: reads the store, writes nothing.
    static func partitionSeriesDates(title: String, sport: String, startDates: [Date],
                                     modelContext: ModelContext) -> (open: [Date], taken: [Date]) {
        var open: [Date] = []
        var taken: [Date] = []
        for start in startDates {
            if SportEvent.duplicate(title: title, sport: sport, startDate: start, in: modelContext) != nil {
                taken.append(start)
            } else {
                open.append(start)
            }
        }
        return (open, taken)
    }

    /// Creates a weekly-recurring series of `Training`s from `favorite`, one
    /// per free date in `startDates` (architecture-review.md §5). Skips any
    /// date that would collide with an existing event and applies the same
    /// sport-driven auto-assigned-team rule as `AddTrainingView`. Returns how
    /// many were created vs. skipped.
    @discardableResult
    static func createSeries(from favorite: TrainingFavorite, startDates: [Date],
                             allTeams: [Team], createdBy: String,
                             modelContext: ModelContext) -> (created: Int, skipped: Int) {
        let (open, taken) = partitionSeriesDates(title: favorite.title, sport: favorite.sport,
                                                 startDates: startDates, modelContext: modelContext)
        let autoNames: Set<String> = Set((Team.autoAssignTeamNames[favorite.sport] ?? []).map { $0.lowercased() })
        let autoTeams = autoNames.isEmpty ? [] : allTeams.filter { autoNames.contains($0.name.lowercased()) }

        for start in open {
            var teams = favorite.teams
            for team in autoTeams where !teams.contains(where: { $0.id == team.id }) {
                teams.append(team)
            }
            let training = Training(
                title: favorite.title, sport: favorite.sport, location: favorite.location,
                street: favorite.street, zip: favorite.zip, city: favorite.city, country: favorite.country,
                startDate: start, durationMinutes: favorite.durationMinutes,
                createdBy: createdBy, teams: teams
            )
            modelContext.insert(training)
            save(training, modelContext: modelContext)
        }
        return (created: open.count, skipped: taken.count)
    }
}
