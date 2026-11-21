import XCTest
import Supabase
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

    // MARK: - Expired access token

    private static let expiredJWT = PostgrestError(code: "PGRST301", message: "JWT expired")

    /// An expired token clears up with a fresh session; dropping the write
    /// from the outbox (as for a real refusal) would lose the edit.
    func testAnExpiredTokenIsNotARefusal() {
        XCTAssertFalse(SupabaseSync.isDenied(Self.expiredJWT))
        XCTAssertTrue(SupabaseSync.isExpiredSession(Self.expiredJWT))
        XCTAssertFalse(SupabaseSync.isDenied(StorageError(statusCode: "400", message: "jwt expired", error: "Unauthorized")))
        XCTAssertTrue(SupabaseSync.isExpiredSession(StorageError(statusCode: "400", message: "jwt expired", error: "Unauthorized")))
    }

    func testRealRefusalsAreStillDropped() {
        XCTAssertTrue(SupabaseSync.isDenied(PostgrestError(code: "42501", message: "new row violates row-level security policy")))
        XCTAssertTrue(SupabaseSync.isDenied(PostgrestError(code: "23505", message: "duplicate key")))
        XCTAssertTrue(SupabaseSync.isDenied(PostgrestError(code: "PGRST303", message: "JWT claims validation failed")))
        XCTAssertTrue(SupabaseSync.isDenied(StorageError(statusCode: "403", message: "new row violates row-level security policy")))
        XCTAssertFalse(SupabaseSync.isExpiredSession(PostgrestError(code: "42501", message: "permission denied")))
    }

    func testAnExpiredTokenIsRefreshedAndTheWriteSent() async {
        let sync = SupabaseSync()
        var refreshes = 0
        sync.refreshSession = { refreshes += 1 }
        var attempts = 0

        let outcome = await sync.performWithRetry("test") {
            attempts += 1
            if refreshes == 0 { throw Self.expiredJWT }
        }

        XCTAssertEqual(outcome, .done)
        XCTAssertEqual(refreshes, 1)
        XCTAssertEqual(attempts, 2)
    }

    func testAWriteThatKeepsFailingWithAnExpiredTokenStaysQueued() async {
        let sync = SupabaseSync()
        sync.refreshSession = {}

        let outcome = await sync.performWithRetry("test") { throw Self.expiredJWT }

        XCTAssertEqual(outcome, .failed, ".failed keeps the outbox row for the next drain; .denied would drop it")
    }
}
