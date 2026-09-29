import Foundation
import SwiftData

/// Admin actions on `AccountApproval`s — see that model's doc comment for why
/// approvals are separate admin-owned records.
@MainActor
enum AccountApprovalService {
    /// Confirms that `user` is the person `member` in the Benutzerverwaltung.
    /// Replaces any earlier approval of this account created on this device.
    @discardableResult
    static func approve(_ user: User, as member: Member, by admin: User, modelContext: ModelContext) -> Bool {
        let approval = AccountApproval(userID: user.id, memberID: member.id, approvedBy: admin.id.uuidString)
        modelContext.insert(approval)
        return PersistenceService.saveAndPush(modelContext: modelContext, modelName: "AccountApproval",
                                               failureMessage: "Freigabe konnte nicht gespeichert werden.") {
            CloudKitSync.shared.pushAccountApproval(approval)
        }
    }

    @discardableResult
    static func revoke(_ approval: AccountApproval, modelContext: ModelContext) -> Bool {
        let id = approval.id
        modelContext.delete(approval)
        return PersistenceService.deleteAndPush(modelContext: modelContext, modelName: "AccountApproval",
                                                 failureMessage: "Freigabe konnte nicht entzogen werden.") {
            CloudKitSync.shared.deleteAccountApproval(id)
        }
    }

    /// Creates a one-time activation code for an account that has no password
    /// yet. Returns the code to show the admin once (only its hash is stored),
    /// or nil if saving failed.
    static func createActivationCode(for user: User, by admin: User, modelContext: ModelContext) -> String? {
        let code = ActivationCode.generate()
        let salt = PasswordHashing.makeSalt()
        let approval = AccountApproval(userID: user.id, memberID: nil, approvedBy: admin.id.uuidString,
                                       activationCodeHash: PasswordHashing.hash(password: ActivationCode.normalized(code), salt: salt),
                                       activationCodeSalt: salt)
        modelContext.insert(approval)
        let saved = PersistenceService.saveAndPush(modelContext: modelContext, modelName: "AccountApproval",
                                                    failureMessage: "Aktivierungscode konnte nicht gespeichert werden.") {
            CloudKitSync.shared.pushAccountApproval(approval)
        }
        return saved ? code : nil
    }
}
