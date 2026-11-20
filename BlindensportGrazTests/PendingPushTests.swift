import XCTest
import SwiftData
@testable import BlindensportGraz

/// Coverage for the `PendingPush` outbox (architecture-review.md 2.2/2.3) —
/// the pure, `ModelContext`-only enqueue/dedupe/clear logic. Deliberately
/// does NOT touch `SupabaseSync.shared` or the network; the actual drain
/// against Supabase stays uncovered like the rest of that class.
@MainActor
final class PendingPushTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        let schema = Schema([PendingPush.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return ModelContext(try ModelContainer(for: schema, configurations: [config]))
    }

    private func enqueueSave(_ context: ModelContext, recordName: String, payload: Data) {
        PendingPush.enqueue(in: context, operation: PendingPush.saveOperation,
                            recordType: "teams", recordName: recordName, payload: payload)
    }

    // MARK: - enqueue / dedupe

    func testEnqueueInsertsOneRow() throws {
        let context = try makeContext()
        enqueueSave(context, recordName: "A", payload: Data([1, 2, 3]))

        XCTAssertEqual(PendingPush.count(in: context), 1)
        let row = try XCTUnwrap(PendingPush.all(in: context).first)
        XCTAssertEqual(row.operation, PendingPush.saveOperation)
        XCTAssertEqual(row.recordName, "A")
        XCTAssertEqual(row.payloadData, Data([1, 2, 3]))
    }

    func testSecondSaveForSameRecordReplacesPayloadAndResetsAttempts() throws {
        let context = try makeContext()
        enqueueSave(context, recordName: "A", payload: Data([1]))
        let first = try XCTUnwrap(PendingPush.all(in: context).first)
        first.attemptCount = 4
        first.lastError = "boom"
        try context.save()

        enqueueSave(context, recordName: "A", payload: Data([9, 9]))

        XCTAssertEqual(PendingPush.count(in: context), 1, "same record must not create a second queued row")
        let row = try XCTUnwrap(PendingPush.all(in: context).first)
        XCTAssertEqual(row.payloadData, Data([9, 9]))
        XCTAssertEqual(row.attemptCount, 0, "a fresh user edit resets the retry counter")
        XCTAssertNil(row.lastError)
    }

    func testDeleteSupersedesAPendingSaveAndClearsItsPayload() throws {
        let context = try makeContext()
        enqueueSave(context, recordName: "A", payload: Data([1, 2, 3]))

        PendingPush.enqueue(in: context, operation: PendingPush.deleteOperation,
                            recordType: "teams", recordName: "A", payload: Data())

        XCTAssertEqual(PendingPush.count(in: context), 1)
        let row = try XCTUnwrap(PendingPush.all(in: context).first)
        XCTAssertEqual(row.operation, PendingPush.deleteOperation)
        XCTAssertTrue(row.payloadData.isEmpty, "a queued delete carries no record payload")
    }

    func testDifferentRecordsQueueSeparately() throws {
        let context = try makeContext()
        enqueueSave(context, recordName: "A", payload: Data([1]))
        enqueueSave(context, recordName: "B", payload: Data([2]))

        XCTAssertEqual(PendingPush.count(in: context), 2)
    }

    func testClearRemovesTheRowForThatRecordOnly() throws {
        let context = try makeContext()
        enqueueSave(context, recordName: "A", payload: Data([1]))
        enqueueSave(context, recordName: "B", payload: Data([2]))

        PendingPush.clear(recordName: "A", recordType: "teams", in: context)

        XCTAssertEqual(PendingPush.count(in: context), 1)
        XCTAssertEqual(PendingPush.all(in: context).first?.recordName, "B")
    }

    func testClearIsANoOpWhenNothingMatches() throws {
        let context = try makeContext()
        enqueueSave(context, recordName: "A", payload: Data([1]))

        PendingPush.clear(recordName: "does-not-exist", recordType: "teams", in: context)

        XCTAssertEqual(PendingPush.count(in: context), 1)
    }

    func testAllReturnsOldestFirst() throws {
        let context = try makeContext()
        enqueueSave(context, recordName: "first", payload: Data([1]))
        let older = try XCTUnwrap(PendingPush.all(in: context).first)
        older.enqueuedAt = Date(timeIntervalSince1970: 0)
        try context.save()
        enqueueSave(context, recordName: "second", payload: Data([2]))

        XCTAssertEqual(PendingPush.all(in: context).map(\.recordName), ["first", "second"])
    }

    // MARK: - uploads

    func testUploadKeepsItsRowPayload() throws {
        let context = try makeContext()
        PendingPush.enqueue(in: context, operation: PendingPush.uploadOperation,
                            recordType: "event_images", recordName: "A", payload: Data([4, 2]))

        let row = try XCTUnwrap(PendingPush.all(in: context).first)
        XCTAssertEqual(row.operation, PendingPush.uploadOperation)
        XCTAssertEqual(row.payloadData, Data([4, 2]))
    }

    func testDeletingAPhotoSupersedesItsPendingUpload() throws {
        let context = try makeContext()
        PendingPush.enqueue(in: context, operation: PendingPush.uploadOperation,
                            recordType: "event_images", recordName: "A", payload: Data([4, 2]))

        PendingPush.enqueue(in: context, operation: PendingPush.deleteOperation,
                            recordType: "event_images", recordName: "A", payload: Data())

        let row = try XCTUnwrap(PendingPush.all(in: context).first)
        XCTAssertEqual(PendingPush.count(in: context), 1)
        XCTAssertEqual(row.operation, PendingPush.deleteOperation)
        XCTAssertTrue(row.payloadData.isEmpty)
    }

    // MARK: - versions (two quick edits of one record)

    func testEveryEnqueueForTheSameRecordGetsALaterStamp() throws {
        let context = try makeContext()
        let first = PendingPush.enqueue(in: context, operation: PendingPush.saveOperation,
                                        recordType: "teams", recordName: "A", payload: Data([1]))
        let second = PendingPush.enqueue(in: context, operation: PendingPush.saveOperation,
                                         recordType: "teams", recordName: "A", payload: Data([2]))

        XCTAssertGreaterThan(second, first)
        XCTAssertEqual(PendingPush.all(in: context).first?.enqueuedAt, second)
    }

    func testNextStampMovesPastAStampFromTheSameInstant() {
        let instant = Date(timeIntervalSince1970: 1_000)
        XCTAssertGreaterThan(PendingPush.nextStamp(after: instant, now: instant), instant)
        XCTAssertGreaterThan(PendingPush.nextStamp(after: instant, now: instant.addingTimeInterval(-5)), instant)
        XCTAssertEqual(PendingPush.nextStamp(after: instant, now: instant.addingTimeInterval(5)),
                       instant.addingTimeInterval(5))
    }

    /// The lost-write race: edit A is sent, edit B is queued while A is in
    /// flight, A's success arrives. B must stay queued, or a failed send of
    /// B is never retried.
    func testConfirmingAnOlderVersionKeepsTheNewerEditQueued() throws {
        let context = try makeContext()
        let versionA = PendingPush.enqueue(in: context, operation: PendingPush.saveOperation,
                                           recordType: "teams", recordName: "A", payload: Data([1]))
        let versionB = PendingPush.enqueue(in: context, operation: PendingPush.saveOperation,
                                           recordType: "teams", recordName: "A", payload: Data([2]))

        PendingPush.clear(recordName: "A", recordType: "teams", enqueuedAt: versionA, in: context)

        let row = try XCTUnwrap(PendingPush.all(in: context).first, "edit B must stay in the outbox")
        XCTAssertEqual(row.payloadData, Data([2]))
        XCTAssertFalse(PendingPush.isCurrent(recordName: "A", recordType: "teams", enqueuedAt: versionA, in: context))
        XCTAssertTrue(PendingPush.isCurrent(recordName: "A", recordType: "teams", enqueuedAt: versionB, in: context))

        PendingPush.clear(recordName: "A", recordType: "teams", enqueuedAt: versionB, in: context)

        XCTAssertEqual(PendingPush.count(in: context), 0)
        XCTAssertFalse(PendingPush.isCurrent(recordName: "A", recordType: "teams", enqueuedAt: versionB, in: context))
    }

    // MARK: - table + id dedupe key

    func testSameIDInDifferentTablesQueuesSeparately() throws {
        // A Member is two rows with the same id: `members` and `member_contacts`.
        let context = try makeContext()
        PendingPush.enqueue(in: context, operation: PendingPush.saveOperation,
                            recordType: "members", recordName: "A", payload: Data([1]))
        PendingPush.enqueue(in: context, operation: PendingPush.saveOperation,
                            recordType: "member_contacts", recordName: "A", payload: Data([2]))

        XCTAssertEqual(PendingPush.count(in: context), 2)

        PendingPush.clear(recordName: "A", recordType: "members", in: context)

        XCTAssertEqual(PendingPush.all(in: context).map(\.recordType), ["member_contacts"])
    }
}
