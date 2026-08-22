import XCTest
@testable import BlindensportGraz

/// Coverage for `SyncState` (audit.md SwiftData & CloudKit Finding 3) —
/// confirms the state machine itself transitions correctly. Doesn't touch
/// `CloudKitSync.shared` (the thing that actually DRIVES these transitions
/// in the real app) — see cerebrum.md's standing "never call CloudKitSync
/// from new tests" rule; this tests `SyncState` in isolation instead.
@MainActor
final class SyncStateTests: XCTestCase {

    override func tearDown() {
        // SyncState.shared is a singleton — leave it in a clean, idle-ish
        // state for whichever test runs next.
        SyncState.shared.markSynced()
        super.tearDown()
    }

    func testMarkSyncingSetsStatusToSyncing() {
        SyncState.shared.markSyncing()
        XCTAssertEqual(SyncState.shared.status, .syncing)
    }

    func testMarkSyncedSetsStatusAndUpdatesLastSyncedAt() throws {
        SyncState.shared.markSyncing()
        let before = Date.now
        SyncState.shared.markSynced()

        XCTAssertEqual(SyncState.shared.status, .synced)
        let lastSyncedAt = try XCTUnwrap(SyncState.shared.lastSyncedAt)
        XCTAssertGreaterThanOrEqual(lastSyncedAt, before)
    }

    func testMarkFailedSetsStatusButDoesNotClearLastSyncedAt() {
        SyncState.shared.markSynced()
        let previousLastSyncedAt = SyncState.shared.lastSyncedAt

        SyncState.shared.markFailed()

        XCTAssertEqual(SyncState.shared.status, .failed)
        XCTAssertEqual(SyncState.shared.lastSyncedAt, previousLastSyncedAt,
                        "one failed operation must not erase evidence that other data synced successfully before it")
    }
}
