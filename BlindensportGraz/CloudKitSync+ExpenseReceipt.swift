import CloudKit
import SwiftData
import Foundation

extension CloudKitSync {
    /// Same CKAsset-via-temp-file-plus-`defer`-cleanup pattern as
    /// `pushEventImage` — see that function's doc comment for why this
    /// doesn't go through the shared `save(_:)` helper.
    func pushExpenseReceipt(_ receipt: ExpenseReceipt) {
        let record = CKRecord(recordType: CKSchema.ExpenseReceipt.recordType, recordID: recordID(receipt.id))
        record[CKSchema.ExpenseReceipt.uploadedBy] = receipt.uploadedBy
        record[CKSchema.ExpenseReceipt.uploadedAt] = receipt.uploadedAt
        record[CKSchema.ExpenseReceipt.note] = receipt.note
        record[CKSchema.ExpenseReceipt.month] = receipt.month
        record[CKSchema.ExpenseReceipt.year] = receipt.year
        record[CKSchema.ExpenseReceipt.tournamentID] = receipt.tournament?.id.uuidString

        let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(receipt.id.uuidString).jpg")
        do {
            try receipt.imageData.write(to: tmpURL)
        } catch {
            logger.error("failed to stage receipt asset for \(receipt.id, privacy: .public): \(String(describing: error), privacy: .public)")
            return
        }
        record[CKSchema.ExpenseReceipt.asset] = CKAsset(fileURL: tmpURL)

        Task {
            defer { try? FileManager.default.removeItem(at: tmpURL) }
            await self.performWithRetry("push for ExpenseReceipt \(record.recordID.recordName)") {
                try await self.upsert(record)
            }
        }
    }

    func deleteExpenseReceipt(_ id: UUID) {
        delete(recordType: CKSchema.ExpenseReceipt.recordType, id: id)
    }

    func pullExpenseReceipts(modelContext: ModelContext) async {
        for record in await fetchAll(recordType: CKSchema.ExpenseReceipt.recordType) {
            guard let id = UUID(uuidString: record.recordID.recordName) else { continue }

            // Immutable once uploaded, same as EventImage — skip straight
            // past anything already local instead of re-fetching bytes.
            var existingDescriptor = FetchDescriptor<ExpenseReceipt>(predicate: #Predicate { $0.id == id })
            existingDescriptor.fetchLimit = 1
            if (try? modelContext.fetch(existingDescriptor).first) != nil { continue }

            guard let asset = record[CKSchema.ExpenseReceipt.asset] as? CKAsset,
                  let fileURL = asset.fileURL,
                  let data = try? Data(contentsOf: fileURL) else { continue }

            let uploadedBy = record[CKSchema.ExpenseReceipt.uploadedBy] as? String ?? ""
            let uploadedAt = record[CKSchema.ExpenseReceipt.uploadedAt] as? Date ?? .now
            let note = record[CKSchema.ExpenseReceipt.note] as? String ?? ""
            let month = record[CKSchema.ExpenseReceipt.month] as? Int
            let year = record[CKSchema.ExpenseReceipt.year] as? Int
            let tournament = (record[CKSchema.ExpenseReceipt.tournamentID] as? String)
                .flatMap { UUID(uuidString: $0) }
                .flatMap { findEvent($0, modelContext: modelContext) as? Tournament }

            let receipt = ExpenseReceipt(id: id, imageData: data, uploadedBy: uploadedBy, uploadedAt: uploadedAt,
                                          note: note, month: month, year: year, tournament: tournament)
            modelContext.insert(receipt)
        }
    }
}
