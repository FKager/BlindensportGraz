import Foundation
import SwiftData

/// Thin passthrough for `CloudKitSync`'s app-level orchestration calls —
/// `syncAll`/`hasAnyUserIdentity`/`ensureDefaultTeams`/
/// `ensureTrainingTournamentSubscriptions` aren't per-model create/update/
/// delete mutations like the other `*Service` types, but view files calling
/// `CloudKitSync.shared` directly for these was part of the same audit.md
/// Architecture Finding 1 gap, so they move here too rather than being left
/// as an exception to "no view file touches CloudKitSync.shared directly."
@MainActor
enum SyncOrchestrationService {
    static func syncAll(modelContext: ModelContext) async {
        await CloudKitSync.shared.syncAll(modelContext: modelContext)
    }

    static func hasAnyUserIdentity() async -> Bool {
        await CloudKitSync.shared.hasAnyUserIdentity()
    }

    static func ensureDefaultTeams(modelContext: ModelContext) async {
        await CloudKitSync.shared.ensureDefaultTeams(modelContext: modelContext)
    }

    static func ensureTrainingTournamentSubscriptions(for user: User) async {
        await CloudKitSync.shared.ensureTrainingTournamentSubscriptions(for: user)
    }
}
