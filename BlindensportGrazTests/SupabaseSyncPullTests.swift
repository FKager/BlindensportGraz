import XCTest
import SwiftData
@testable import BlindensportGraz

/// A pull must not overwrite a record whose local edit is still waiting in
/// the outbox — the server copy is older. Uses a fresh `SupabaseSync` with an
/// in-memory outbox (not `.shared`), no network.
@MainActor
final class SupabaseSyncPullTests: XCTestCase {
    private struct Row { let id: UUID; let title: String }

    private func makeSync() throws -> (SupabaseSync, ModelContext) {
        let schema = Schema([PendingPush.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        let sync = SupabaseSync()
        sync.modelContainer = container
        return (sync, ModelContext(container))
    }

    func testRowsWithAnUnsentLocalEditAreNotApplied() throws {
        let (sync, outbox) = try makeSync()
        let edited = Row(id: UUID(), title: "Training (server, older)")
        let untouched = Row(id: UUID(), title: "Turnier")
        PendingPush.enqueue(in: outbox, operation: PendingPush.saveOperation, recordType: "events",
                            recordName: edited.id.uuidString, payload: Data([1]))

        let applied = sync.rowsToApply([edited, untouched], id: \.id)

        XCTAssertEqual(applied.map(\.id), [untouched.id])
    }

    func testRowsApplyAgainOnceTheEditIsConfirmed() throws {
        let (sync, outbox) = try makeSync()
        let row = Row(id: UUID(), title: "Training")
        let version = PendingPush.enqueue(in: outbox, operation: PendingPush.saveOperation, recordType: "events",
                                          recordName: row.id.uuidString, payload: Data([1]))
        PendingPush.clear(recordName: row.id.uuidString, recordType: "events", enqueuedAt: version, in: outbox)

        XCTAssertEqual(sync.rowsToApply([row], id: \.id).map(\.id), [row.id])
    }

    // MARK: - Cursor overlap

    /// A save that started before the last pull but committed after it is
    /// stamped before the cursor; the next incremental pull must still read it.
    func testIncrementalPullRereadsRowsStampedShortlyBeforeTheCursor() {
        let cursor = Date(timeIntervalSince1970: 1_000_000)
        let lateCommit = cursor.addingTimeInterval(-30)

        XCTAssertLessThanOrEqual(SupabaseSync.queryStart(after: cursor), lateCommit)
    }

    func testOverlapIsBounded() {
        let cursor = Date(timeIntervalSince1970: 1_000_000)

        XCTAssertEqual(cursor.timeIntervalSince(SupabaseSync.queryStart(after: cursor)), SupabaseSync.cursorOverlap)
        XCTAssertLessThanOrEqual(SupabaseSync.cursorOverlap, 300, "re-reading must stay small")
    }

    func testAPendingDeleteAlsoProtectsTheRow() throws {
        let (sync, outbox) = try makeSync()
        let row = Row(id: UUID(), title: "Gelöscht auf diesem Gerät")
        PendingPush.enqueue(in: outbox, operation: PendingPush.deleteOperation, recordType: "events",
                            recordName: row.id.uuidString, payload: Data())

        XCTAssertTrue(sync.rowsToApply([row], id: \.id).isEmpty)
    }
}
