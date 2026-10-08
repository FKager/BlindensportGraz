import Foundation
import SwiftData

/// The local `User` is a device-only cache of the Supabase profile (see
/// `AuthContext`); accounts, roles and approvals no longer sync through
/// CloudKit. Profile edits go to Supabase via `SupabaseProfileService`.
@MainActor
enum UserService {
    @discardableResult
    static func save(_ user: User, modelContext: ModelContext) -> Bool {
        PersistenceService.saveAndPush(modelContext: modelContext, modelName: "User",
                                        failureMessage: "Benutzer konnte nicht gespeichert werden.") {}
    }

    @discardableResult
    static func delete(_ user: User, modelContext: ModelContext) -> Bool {
        modelContext.delete(user)
        return PersistenceService.deleteAndPush(modelContext: modelContext, modelName: "User",
                                                 failureMessage: "Benutzer konnte nicht gelöscht werden.") {}
    }
}
