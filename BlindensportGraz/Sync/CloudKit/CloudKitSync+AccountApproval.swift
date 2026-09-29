import CloudKit
import SwiftData
import Foundation

extension CloudKitSync {
    func pushAccountApproval(_ approval: AccountApproval) {
        let record = CKRecord(recordType: CKSchema.AccountApproval.recordType, recordID: recordID(approval.id))
        record[CKSchema.AccountApproval.userID] = approval.userID.uuidString
        record[CKSchema.AccountApproval.memberID] = approval.memberID?.uuidString ?? ""
        record[CKSchema.AccountApproval.approvedBy] = approval.approvedBy
        record[CKSchema.AccountApproval.approvedAt] = approval.approvedAt
        record[CKSchema.AccountApproval.activationCodeHash] = approval.activationCodeHash
        record[CKSchema.AccountApproval.activationCodeSalt] = approval.activationCodeSalt
        save(record)
    }

    func deleteAccountApproval(_ id: UUID) {
        delete(recordType: CKSchema.AccountApproval.recordType, id: id)
    }

    /// Also removes local approvals that no longer exist in CloudKit, so a
    /// revoked approval takes effect on every device at the next sync.
    func pullAccountApprovals(modelContext: ModelContext) async {
        guard let records = try? await fetchAllOrThrow(recordType: CKSchema.AccountApproval.recordType) else { return }
        var remoteIDs = Set<UUID>()
        for record in records {
            guard let id = UUID(uuidString: record.recordID.recordName),
                  let userIDString = record[CKSchema.AccountApproval.userID] as? String,
                  let userID = UUID(uuidString: userIDString) else { continue }
            remoteIDs.insert(id)
            let memberID = (record[CKSchema.AccountApproval.memberID] as? String).flatMap(UUID.init(uuidString:))
            let approvedBy = record[CKSchema.AccountApproval.approvedBy] as? String ?? ""
            let approvedAt = record[CKSchema.AccountApproval.approvedAt] as? Date ?? .now
            let codeHash = record[CKSchema.AccountApproval.activationCodeHash] as? String ?? ""
            let codeSalt = record[CKSchema.AccountApproval.activationCodeSalt] as? String ?? ""

            var descriptor = FetchDescriptor<AccountApproval>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            if let existing = try? modelContext.fetch(descriptor).first {
                existing.userID = userID
                existing.memberID = memberID
                existing.approvedBy = approvedBy
                existing.approvedAt = approvedAt
                existing.activationCodeHash = codeHash
                existing.activationCodeSalt = codeSalt
            } else {
                modelContext.insert(AccountApproval(id: id, userID: userID, memberID: memberID, approvedBy: approvedBy,
                                                    approvedAt: approvedAt, activationCodeHash: codeHash,
                                                    activationCodeSalt: codeSalt))
            }
        }
        for local in (try? modelContext.fetch(FetchDescriptor<AccountApproval>())) ?? [] where !remoteIDs.contains(local.id) {
            modelContext.delete(local)
        }
    }

    /// Whether any account with this email exists in CloudKit — checked on
    /// registration in addition to the local store, which may not be synced
    /// yet. Emails are stored as typed, so both the typed and the lower-cased
    /// form are looked up. Returns nil when CloudKit can't be reached.
    func userIdentityExists(email: String) async -> Bool? {
        let typed = email.trimmingCharacters(in: .whitespaces)
        let variants = Array(Set([typed, typed.lowercased()]))
        let query = CKQuery(recordType: CKSchema.UserIdentity.recordType,
                            predicate: NSPredicate(format: "%K IN %@", CKSchema.UserIdentity.email, variants))
        do {
            let (results, _) = try await publicDB.records(matching: query, resultsLimit: 1)
            return !results.isEmpty
        } catch {
            return nil
        }
    }
}
