import CloudKit
import SwiftData
import Foundation

extension CloudKitSync {
    func pushBudgetEntry(_ entry: BudgetEntry) {
        let record = CKRecord(recordType: CKSchema.BudgetEntry.recordType, recordID: recordID(entry.id))
        record[CKSchema.BudgetEntry.category] = entry.category.rawValue
        record[CKSchema.BudgetEntry.amount] = entry.amount
        record[CKSchema.BudgetEntry.date] = entry.date
        record[CKSchema.BudgetEntry.note] = entry.note
        record[CKSchema.BudgetEntry.eventID] = entry.event?.id.uuidString
        record[CKSchema.BudgetEntry.createdBy] = entry.createdBy
        record[CKSchema.BudgetEntry.createdAt] = entry.createdAt
        save(record)
    }

    func deleteBudgetEntry(_ id: UUID) {
        delete(recordType: CKSchema.BudgetEntry.recordType, id: id)
    }

    func pullBudgetEntries(modelContext: ModelContext) async {
        for record in await fetchAll(recordType: CKSchema.BudgetEntry.recordType) {
            guard let id = UUID(uuidString: record.recordID.recordName) else { continue }
            // Fail-safe default matches BudgetCategory's own philosophy: a
            // missing/corrupt category on the wire must never default to
            // an income category.
            let category = BudgetCategory.normalize(record[CKSchema.BudgetEntry.category] as? String ?? "otherExpense")
            let amount = record[CKSchema.BudgetEntry.amount] as? Double ?? 0
            let date = record[CKSchema.BudgetEntry.date] as? Date ?? .now
            let note = record[CKSchema.BudgetEntry.note] as? String ?? ""
            let event = (record[CKSchema.BudgetEntry.eventID] as? String).flatMap { UUID(uuidString: $0) }
                .flatMap { findEvent($0, modelContext: modelContext) }
            let createdBy = record[CKSchema.BudgetEntry.createdBy] as? String ?? ""
            let createdAt = record[CKSchema.BudgetEntry.createdAt] as? Date ?? .now

            var descriptor = FetchDescriptor<BudgetEntry>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            if let existing = try? modelContext.fetch(descriptor).first {
                // Reconcile in place so a remote edit (via EditBudgetEntryView
                // on another device) is reflected here too, same as
                // TeamMembership's update-in-place pull.
                existing.category = category
                existing.amount = amount
                existing.date = date
                existing.note = note
                existing.event = event
            } else {
                let entry = BudgetEntry(id: id, category: category, amount: amount, date: date, note: note,
                                        event: event, createdBy: createdBy, createdAt: createdAt)
                modelContext.insert(entry)
            }
        }
    }
}
