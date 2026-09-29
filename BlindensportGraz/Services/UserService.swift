import Foundation
import SwiftData

@MainActor
enum UserService {
    @discardableResult
    static func save(_ user: User, modelContext: ModelContext) -> Bool {
        PersistenceService.saveAndPush(modelContext: modelContext, modelName: "User",
                                        failureMessage: "Benutzer konnte nicht gespeichert werden.") {
            CloudKitSync.shared.pushUserIdentity(user)
        }
    }

    @discardableResult
    static func delete(_ user: User, modelContext: ModelContext) -> Bool {
        let id = user.id
        modelContext.delete(user)
        return PersistenceService.deleteAndPush(modelContext: modelContext, modelName: "User",
                                                 failureMessage: "Benutzer konnte nicht gelöscht werden.") {
            CloudKitSync.shared.deleteUserIdentity(id)
        }
    }
}
