import CloudKit
import SwiftData
import Foundation

extension CloudKitSync {
    func pushRoleChangeLog(_ entry: RoleChangeLog) {
        let record = CKRecord(recordType: CKSchema.RoleChangeLog.recordType, recordID: recordID(entry.id))
        record[CKSchema.RoleChangeLog.userID] = entry.userID.uuidString
        record[CKSchema.RoleChangeLog.oldRole] = entry.oldRole
        record[CKSchema.RoleChangeLog.newRole] = entry.newRole
        record[CKSchema.RoleChangeLog.changedBy] = entry.changedBy
        record[CKSchema.RoleChangeLog.changedAt] = entry.changedAt
        save(record)
    }

    func pullRoleChangeLogs(modelContext: ModelContext) async {
        for record in await fetchAll(recordType: CKSchema.RoleChangeLog.recordType) {
            guard let id = UUID(uuidString: record.recordID.recordName),
                  let userIDString = record[CKSchema.RoleChangeLog.userID] as? String, let userID = UUID(uuidString: userIDString) else { continue }
            let oldRole = record[CKSchema.RoleChangeLog.oldRole] as? String ?? ""
            let newRole = record[CKSchema.RoleChangeLog.newRole] as? String ?? ""
            let changedBy = record[CKSchema.RoleChangeLog.changedBy] as? String ?? ""
            let changedAt = record[CKSchema.RoleChangeLog.changedAt] as? Date ?? .now

            var descriptor = FetchDescriptor<RoleChangeLog>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            if let existing = try? modelContext.fetch(descriptor).first {
                existing.userID = userID
                existing.oldRole = oldRole
                existing.newRole = newRole
                existing.changedBy = changedBy
                existing.changedAt = changedAt
            } else {
                let entry = RoleChangeLog(id: id, userID: userID, oldRole: oldRole, newRole: newRole,
                                           changedBy: changedBy, changedAt: changedAt)
                modelContext.insert(entry)
            }
        }
    }
}
