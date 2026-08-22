import CloudKit
import SwiftData
import Foundation

extension CloudKitSync {
    func pushUserIdentity(_ user: User) {
        let record = CKRecord(recordType: CKSchema.UserIdentity.recordType, recordID: recordID(user.id))
        record[CKSchema.UserIdentity.firstName] = user.firstName
        record[CKSchema.UserIdentity.lastName] = user.lastName
        record[CKSchema.UserIdentity.role] = user.role.rawValue
        record[CKSchema.UserIdentity.isGrazerVSCMember] = user.isGrazerVSCMember
        record[CKSchema.UserIdentity.isRoot] = user.isRoot
        save(record)
    }

    func deleteUserIdentity(_ id: UUID) {
        delete(recordType: CKSchema.UserIdentity.recordType, id: id)
    }

    /// Cheap existence check used to decide whether a brand-new account should
    /// bootstrap itself as root (only the very first account, ever, should).
    /// On failure (offline, etc.) conservatively reports `true` so an account
    /// created without network access never self-grants root — if that ever
    /// blocks legitimate bootstrapping, RootCLI can grant root out-of-band.
    func hasAnyUserIdentity() async -> Bool {
        let query = CKQuery(recordType: CKSchema.UserIdentity.recordType, predicate: NSPredicate(value: true))
        do {
            let (results, _) = try await publicDB.records(matching: query, resultsLimit: 1)
            return !results.isEmpty
        } catch {
            return true
        }
    }

    func pullUserIdentities(modelContext: ModelContext) async {
        for record in await fetchAll(recordType: CKSchema.UserIdentity.recordType) {
            guard let id = UUID(uuidString: record.recordID.recordName) else { continue }
            let firstName = record[CKSchema.UserIdentity.firstName] as? String ?? ""
            let lastName = record[CKSchema.UserIdentity.lastName] as? String ?? ""
            let role = AppRole.normalize(record[CKSchema.UserIdentity.role] as? String ?? "member")
            let isGrazerVSCMember = record[CKSchema.UserIdentity.isGrazerVSCMember] as? Bool ?? false
            let isRoot = record[CKSchema.UserIdentity.isRoot] as? Bool ?? false

            var descriptor = FetchDescriptor<User>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            if let existing = try? modelContext.fetch(descriptor).first {
                // Local email/appleUserIdentifier are never published, so never overwritten here.
                existing.firstName = firstName
                existing.lastName = lastName
                existing.role = role
                existing.isGrazerVSCMember = isGrazerVSCMember
                existing.isRoot = isRoot
            } else {
                let user = User(id: id, email: "", firstName: firstName, lastName: lastName,
                                 role: role, isGrazerVSCMember: isGrazerVSCMember, isRoot: isRoot)
                modelContext.insert(user)
            }
        }
    }
}
