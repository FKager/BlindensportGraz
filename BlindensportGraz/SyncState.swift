import Foundation
import Observation
import os

/// App-wide sync state — audit.md SwiftData & CloudKit Finding 3 ("no
/// user-visible sync/pending state anywhere") + Enhancement #3. Driven by
/// REAL push/pull activity, not a static decoration: `CloudKitSync`'s
/// `performWithRetry` (Phase 6) reports every push/delete attempt's outcome
/// here, and `syncAll()` brackets its pull pass with `.syncing`/`.synced`.
/// `@Observable` singleton, same shape as `ServiceFailureSignal` — any view
/// can read `SyncState.shared.status`/`.lastSyncedAt` without state being
/// threaded through every call site.
enum SyncStatus: Equatable {
    case idle
    case syncing
    case synced
    case failed
}

@Observable
final class SyncState {
    static let shared = SyncState()

    private static let lastSyncedAtKey = "SyncState.lastSyncedAt"
    private let logger = Logger(subsystem: "it.a11y.BlindensportGraz", category: "SyncState")

    private(set) var status: SyncStatus = .idle
    /// Persisted across launches (see `BlindensportGrazApp`'s local-store
    /// reset fallback, which reads this to log what's about to be
    /// discarded) — the in-memory `status` above deliberately is NOT
    /// persisted, since "syncing"/"failed" from a previous launch is stale
    /// information, but "the last time a sync definitely succeeded" stays
    /// meaningful across launches.
    private(set) var lastSyncedAt: Date?

    private init() {
        lastSyncedAt = UserDefaults.standard.object(forKey: Self.lastSyncedAtKey) as? Date
    }

    /// Called by `CloudKitSync.syncAll()` before the pull pass starts.
    func markSyncing() {
        status = .syncing
    }

    /// Called by `CloudKitSync.syncAll()` after a successful pull pass, and
    /// by `performWithRetry` after any successful push/delete — either one
    /// is real, confirmed activity with CloudKit.
    func markSynced() {
        status = .synced
        let now = Date.now
        lastSyncedAt = now
        UserDefaults.standard.set(now, forKey: Self.lastSyncedAtKey)
    }

    /// Called by `performWithRetry` after all retry attempts are exhausted.
    /// Deliberately does NOT clear `lastSyncedAt` — one failed operation
    /// doesn't erase the fact that other data synced successfully before it.
    func markFailed() {
        status = .failed
        logger.error("Sync state moved to .failed")
    }
}
