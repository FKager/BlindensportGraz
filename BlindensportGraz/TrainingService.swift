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
}
