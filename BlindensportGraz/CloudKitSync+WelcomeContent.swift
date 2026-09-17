import CloudKit
import SwiftData
import Foundation

extension CloudKitSync {
    func pushWelcomeContent(_ content: WelcomeContent) {
        let record = CKRecord(recordType: CKSchema.WelcomeContent.recordType, recordID: recordID(content.id))
        record[CKSchema.WelcomeContent.markdown] = content.markdown
        record[CKSchema.WelcomeContent.isEnabled] = content.isEnabled
        record[CKSchema.WelcomeContent.updatedAt] = content.updatedAt
        save(record)
    }

    /// Pulls the single shared welcome note, if any — unlike most pulls this
    /// only ever expects at most one record (fixed `WelcomeContent.sharedID`),
    /// but still queries by type rather than `publicDB.record(for:)` so a
    /// not-yet-created record is just an empty pull instead of a thrown
    /// "unknown item" error to special-case.
    func pullWelcomeContent(modelContext: ModelContext) async {
        guard let record = await fetchAll(recordType: CKSchema.WelcomeContent.recordType).first else { return }
        let markdown = record[CKSchema.WelcomeContent.markdown] as? String ?? ""
        let isEnabled = record[CKSchema.WelcomeContent.isEnabled] as? Bool ?? false
        let updatedAt = record[CKSchema.WelcomeContent.updatedAt] as? Date ?? .now

        if let existing = WelcomeContent.current(in: modelContext) {
            // A locally-pending edit still sitting in the outbox always wins
            // over whatever this pull just fetched (same guard every other
            // pull uses, see pullTrainings) — otherwise an admin's own
            // just-saved edit could be clobbered by a still-in-flight older
            // server copy landing on the very same sync pass.
            guard !hasPendingPush(recordName: existing.id.uuidString) else { return }
            existing.markdown = markdown
            existing.isEnabled = isEnabled
            existing.updatedAt = updatedAt
        } else {
            modelContext.insert(WelcomeContent(id: WelcomeContent.sharedID, markdown: markdown,
                                                isEnabled: isEnabled, updatedAt: updatedAt))
        }
    }
}
