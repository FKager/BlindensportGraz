import Foundation
import SwiftData

/// Thin passthrough for `SupabaseSync`'s app-level orchestration calls —
/// `syncAll`/`ensureDefaultTeams`/
/// `ensureTrainingTournamentSubscriptions` aren't per-model create/update/
/// delete mutations like the other `*Service` types, but view files calling
/// `SupabaseSync.shared` directly for these was part of the same audit.md
/// Architecture Finding 1 gap, so they move here too rather than being left
/// as an exception to "no view file touches SupabaseSync.shared directly."
@MainActor
enum SyncOrchestrationService {
    /// Coming back to the foreground syncs again — data changed on the
    /// server or by other admins shows up without restarting the app —
    /// unless the last sync finished less than `foregroundSyncInterval` ago.
    static let foregroundSyncInterval: TimeInterval = 30

    static func shouldSyncOnForeground(lastSyncedAt: Date?, now: Date = .now) -> Bool {
        guard let lastSyncedAt else { return true }
        return now.timeIntervalSince(lastSyncedAt) >= foregroundSyncInterval
    }

    static func syncAll(modelContext: ModelContext) async {
        await SupabaseSync.shared.syncAll(modelContext: modelContext)
    }

    /// Re-attempts just the queued `PendingPush` writes, without a full pull
    /// pass — used when the network comes back (architecture-review.md 2.2).
    static func drainOutbox() async {
        await SupabaseSync.shared.drainOutbox()
    }

    static func ensureDefaultTeams(modelContext: ModelContext) async {
        await SupabaseSync.shared.ensureDefaultTeams(modelContext: modelContext)
    }

    /// Registers this device for training/tournament push notifications
    /// (the server decides who gets which push from team memberships).
    static func ensureTrainingTournamentSubscriptions(for user: User) async {
        await PushRegistration.shared.registerIfAllowed()
    }
}
