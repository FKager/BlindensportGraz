import CloudKit
import SwiftData
import Foundation

extension CloudKitSync {
    func pushRoleAssignment(_ assignment: RoleAssignment) {
        let record = CKRecord(recordType: CKSchema.RoleAssignment.recordType, recordID: recordID(assignment.id))
        record[CKSchema.RoleAssignment.userID] = assignment.userID.uuidString
        record[CKSchema.RoleAssignment.role] = assignment.role
        record[CKSchema.RoleAssignment.assignedBy] = assignment.assignedBy
        record[CKSchema.RoleAssignment.assignedAt] = assignment.assignedAt
        save(record)
    }

    /// Pulls every assignment, then applies the effective roles locally
    /// (`RoleAssignmentResolver`) — after `pullUserIdentities`, which resets
    /// `User.role` to the value stored in each account's own record.
    func pullRoleAssignments(modelContext: ModelContext) async {
        for record in await fetchAll(recordType: CKSchema.RoleAssignment.recordType) {
            guard let id = UUID(uuidString: record.recordID.recordName),
                  let userIDString = record[CKSchema.RoleAssignment.userID] as? String,
                  let userID = UUID(uuidString: userIDString) else { continue }
            let role = record[CKSchema.RoleAssignment.role] as? String ?? AppRole.member.rawValue
            let assignedBy = record[CKSchema.RoleAssignment.assignedBy] as? String ?? ""
            let assignedAt = record[CKSchema.RoleAssignment.assignedAt] as? Date ?? .now

            var descriptor = FetchDescriptor<RoleAssignment>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            if let existing = try? modelContext.fetch(descriptor).first {
                existing.userID = userID
                existing.role = role
                existing.assignedBy = assignedBy
                existing.assignedAt = assignedAt
            } else {
                modelContext.insert(RoleAssignment(id: id, userID: userID, role: role,
                                                   assignedBy: assignedBy, assignedAt: assignedAt))
            }
        }
        RoleAssignmentResolver.apply(in: modelContext)
    }
}
