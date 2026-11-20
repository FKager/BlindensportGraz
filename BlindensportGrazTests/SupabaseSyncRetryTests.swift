import XCTest
@testable import BlindensportGraz

/// `performWithRetry` must stop sending an edit once a newer edit of the same
/// record has replaced it, so the older one can't overwrite the newer one on
/// the server. Uses a fresh `SupabaseSync` (not `.shared`) and fake
/// operations — no network.
@MainActor
final class SupabaseSyncRetryTests: XCTestCase {
    private struct Offline: Error {}

    func testASupersededWriteIsNeverSent() async {
        let sync = SupabaseSync()
        var attempts = 0

        let outcome = await sync.performWithRetry("test", isCurrent: { false }) { attempts += 1 }

        XCTAssertEqual(outcome, .superseded)
        XCTAssertEqual(attempts, 0)
    }

    func testRetriesStopOnceANewerEditIsQueued() async {
        let sync = SupabaseSync()
        var attempts = 0
        var current = true

        let outcome = await sync.performWithRetry("test", isCurrent: { current }) {
            attempts += 1
            current = false // a newer edit arrives while this attempt fails
            throw Offline()
        }

        XCTAssertEqual(outcome, .superseded)
        XCTAssertEqual(attempts, 1, "the older write must not be retried after it was replaced")
    }
}
