import CloudKit
import SwiftData
import Foundation

extension CloudKitSync {
    func pushParticipation(_ participation: EventParticipation) {
        let record = CKRecord(recordType: CKSchema.EventParticipation.recordType, recordID: recordID(participation.id))
        record[CKSchema.EventParticipation.userID] = participation.user.id.uuidString
        record[CKSchema.EventParticipation.eventID] = participation.event.id.uuidString
        record[CKSchema.EventParticipation.status] = participation.status
        record[CKSchema.EventParticipation.registeredAt] = participation.registeredAt
        save(record)
    }

    func pullParticipations(modelContext: ModelContext) async {
        for record in await fetchAll(recordType: CKSchema.EventParticipation.recordType) {
            guard let id = UUID(uuidString: record.recordID.recordName),
                  let userIDString = record[CKSchema.EventParticipation.userID] as? String, let userID = UUID(uuidString: userIDString),
                  let eventIDString = record[CKSchema.EventParticipation.eventID] as? String, let eventID = UUID(uuidString: eventIDString),
                  let user = findUser(userID, modelContext: modelContext),
                  let event = findEvent(eventID, modelContext: modelContext) else { continue }
            let status = record[CKSchema.EventParticipation.status] as? String ?? "invited"
            let registeredAt = record[CKSchema.EventParticipation.registeredAt] as? Date ?? .now

            var descriptor = FetchDescriptor<EventParticipation>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            if let existing = try? modelContext.fetch(descriptor).first {
                existing.status = status
            } else {
                let participation = EventParticipation(id: id, user: user, event: event, status: status, registeredAt: registeredAt)
                modelContext.insert(participation)
            }
        }
    }
}
