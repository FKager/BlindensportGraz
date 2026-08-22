import Foundation
import SwiftData

@MainActor
enum ExpenseReceiptService {
    @discardableResult
    static func save(_ receipt: ExpenseReceipt, modelContext: ModelContext) -> Bool {
        PersistenceService.saveAndPush(modelContext: modelContext, modelName: "ExpenseReceipt",
                                        failureMessage: "Beleg konnte nicht gespeichert werden.") {
            CloudKitSync.shared.pushExpenseReceipt(receipt)
        }
    }

    @discardableResult
    static func delete(_ receipt: ExpenseReceipt, modelContext: ModelContext) -> Bool {
        let id = receipt.id
        modelContext.delete(receipt)
        return PersistenceService.deleteAndPush(modelContext: modelContext, modelName: "ExpenseReceipt",
                                                 failureMessage: "Beleg konnte nicht gelöscht werden.") {
            CloudKitSync.shared.deleteExpenseReceipt(id)
        }
    }
}
