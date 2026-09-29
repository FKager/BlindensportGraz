import Foundation
import SwiftData

@MainActor
enum BudgetEntryService {
    @discardableResult
    static func save(_ entry: BudgetEntry, modelContext: ModelContext) -> Bool {
        PersistenceService.saveAndPush(modelContext: modelContext, modelName: "BudgetEntry",
                                        failureMessage: "Budgeteintrag konnte nicht gespeichert werden.") {
            CloudKitSync.shared.pushBudgetEntry(entry)
        }
    }

    @discardableResult
    static func delete(_ entry: BudgetEntry, modelContext: ModelContext) -> Bool {
        let id = entry.id
        modelContext.delete(entry)
        return PersistenceService.deleteAndPush(modelContext: modelContext, modelName: "BudgetEntry",
                                                 failureMessage: "Budgeteintrag konnte nicht gelöscht werden.") {
            CloudKitSync.shared.deleteBudgetEntry(id)
        }
    }
}
