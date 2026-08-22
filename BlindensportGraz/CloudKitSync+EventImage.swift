import CloudKit
import SwiftData
import Foundation

extension CloudKitSync {
    /// Images are stored as a CKAsset (a file reference), not a raw Data field,
    /// since CloudKit expects large binaries to go through assets. That means
    /// staging the bytes to a temp file before the CKRecord save and cleaning
    /// it up afterward, unlike every other push in this app.
    ///
    /// Doesn't go through the shared `save(_:)` helper: the temp file backing
    /// the `CKAsset` must stay on disk for the ENTIRE retry sequence (all up
    /// to 4 attempts), and get removed exactly once after the last attempt —
    /// so this calls `performWithRetry` directly inside its own `Task`,
    /// wrapping the whole thing in one `defer` instead of per-attempt cleanup.
    func pushEventImage(_ image: EventImage) {
        let record = CKRecord(recordType: CKSchema.EventImage.recordType, recordID: recordID(image.id))
        record[CKSchema.EventImage.uploadedBy] = image.uploadedBy
        record[CKSchema.EventImage.uploadedAt] = image.uploadedAt
        record[CKSchema.EventImage.eventID] = image.event?.id.uuidString

        let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(image.id.uuidString).jpg")
        do {
            try image.imageData.write(to: tmpURL)
        } catch {
            logger.error("failed to stage image asset for \(image.id, privacy: .public): \(String(describing: error), privacy: .public)")
            return
        }
        record[CKSchema.EventImage.asset] = CKAsset(fileURL: tmpURL)

        Task {
            defer { try? FileManager.default.removeItem(at: tmpURL) }
            await self.performWithRetry("push for EventImage \(record.recordID.recordName)") {
                try await self.upsert(record)
            }
        }
    }

    func deleteEventImage(_ id: UUID) {
        delete(recordType: CKSchema.EventImage.recordType, id: id)
    }

    func pullEventImages(modelContext: ModelContext) async {
        for record in await fetchAll(recordType: CKSchema.EventImage.recordType) {
            guard let id = UUID(uuidString: record.recordID.recordName) else { continue }

            // Images are immutable once uploaded, and CKAsset downloads aren't free —
            // skip straight past anything already local instead of re-fetching bytes.
            var existingDescriptor = FetchDescriptor<EventImage>(predicate: #Predicate { $0.id == id })
            existingDescriptor.fetchLimit = 1
            if (try? modelContext.fetch(existingDescriptor).first) != nil { continue }

            guard let asset = record[CKSchema.EventImage.asset] as? CKAsset,
                  let fileURL = asset.fileURL,
                  let data = try? Data(contentsOf: fileURL) else { continue }

            let uploadedBy = record[CKSchema.EventImage.uploadedBy] as? String ?? ""
            let uploadedAt = record[CKSchema.EventImage.uploadedAt] as? Date ?? .now
            // New records only carry eventID; pre-refactor records carried the
            // FK under trainingID/tournamentID instead — fall back to those so
            // a device syncing for the first time after this change still
            // resolves images uploaded before it.
            let eventIDString = (record[CKSchema.EventImage.eventID] as? String)
                ?? (record[CKSchema.EventImage.trainingIDCompat] as? String)
                ?? (record[CKSchema.EventImage.tournamentIDCompat] as? String)
            let event = eventIDString.flatMap { UUID(uuidString: $0) }
                .flatMap { findEvent($0, modelContext: modelContext) }

            let image = EventImage(id: id, imageData: data, uploadedBy: uploadedBy, uploadedAt: uploadedAt,
                                    event: event)
            modelContext.insert(image)
        }
    }
}
