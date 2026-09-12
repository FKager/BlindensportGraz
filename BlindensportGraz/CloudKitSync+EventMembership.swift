import CloudKit
import SwiftData
import Foundation

extension CloudKitSync {
    func pushEventMembership(_ membership: EventMembership) {
        let record = CKRecord(recordType: CKSchema.EventMembership.recordType, recordID: recordID(membership.id))
        record[CKSchema.EventMembership.userID] = membership.user?.id.uuidString
        record[CKSchema.EventMembership.memberID] = membership.member?.id.uuidString
        record[CKSchema.EventMembership.eventID] = membership.event.id.uuidString
        record[CKSchema.EventMembership.addedAt] = membership.addedAt
        save(record)
    }

    // Same "was missing, silently reappeared on next pull" gotcha TeamMembership
    // hit (see CloudKitSync+TeamMembership.swift's deleteMembership doc
    // comment / bug-163) — wired up from the start here instead.
    func deleteEventMembership(_ id: UUID) {
        delete(recordType: CKSchema.EventMembership.recordType, id: id)
    }

    func pullEventMemberships(modelContext: ModelContext) async {
        for record in await fetchAll(recordType: CKSchema.EventMembership.recordType) {
            guard let id = UUID(uuidString: record.recordID.recordName),
                  let eventIDString = record[CKSchema.EventMembership.eventID] as? String, let eventID = UUID(uuidString: eventIDString),
                  let event = findEvent(eventID, modelContext: modelContext) else { continue }
            let user = (record[CKSchema.EventMembership.userID] as? String).flatMap { UUID(uuidString: $0) }
                .flatMap { findUser($0, modelContext: modelContext) }
            let member = (record[CKSchema.EventMembership.memberID] as? String).flatMap { UUID(uuidString: $0) }
                .flatMap { findMember($0, modelContext: modelContext) }
            // Exactly one side must resolve — a membership with neither is orphaned data.
            guard user != nil || member != nil else { continue }
            let addedAt = record[CKSchema.EventMembership.addedAt] as? Date ?? .now

            var descriptor = FetchDescriptor<EventMembership>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            if (try? modelContext.fetch(descriptor).first) == nil {
                let membership = EventMembership(id: id, user: user, member: member, event: event, addedAt: addedAt)
                modelContext.insert(membership)
            }
        }
    }
}
