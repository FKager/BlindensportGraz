import XCTest
import SwiftData
@testable import BlindensportGraz

/// Photos, receipts and invitation documents go through the outbox: a queued
/// upload keeps the local copy from being pruned, it knows where its file
/// goes, and the resend drops it once the file is gone from this device.
/// Fresh `SupabaseSync` (not `.shared`) with an in-memory store, no network.
@MainActor
final class SupabaseSyncUploadTests: XCTestCase {

    private func makeSync() throws -> (SupabaseSync, ModelContext) {
        let config = ModelConfiguration(schema: AppModelSchema.schema, isStoredInMemoryOnly: true,
                                        cloudKitDatabase: .none)
        let container = try ModelContainer(for: AppModelSchema.schema, configurations: [config])
        let sync = SupabaseSync()
        sync.modelContainer = container
        return (sync, ModelContext(container))
    }

    private func enqueueUpload(_ table: String, id: UUID, payload: Data, in context: ModelContext) {
        PendingPush.enqueue(in: context, operation: PendingPush.uploadOperation, recordType: table,
                            recordName: id.uuidString, payload: payload)
    }

    // MARK: - Where the file goes

    func testPhotoUploadTargetsTheEventImagesBucket() throws {
        let image = EventImage(id: UUID(), imageData: Data([1, 2, 3]), uploadedBy: "u", uploadedAt: .now, event: nil)
        let payload = SupabaseSync.payload(EventImageDBRow(image))

        let target = try SupabaseSync.fileTarget(table: "event_images", payload: payload)

        XCTAssertEqual(target, .init(bucket: "event-images", path: EventImageDBRow.path(for: image.id),
                                     contentType: "image/jpeg"))
    }

    func testDocumentUploadKeepsItsContentType() throws {
        let document = TournamentInvitation(id: UUID(), fileData: Data([1]), fileName: "Ausschreibung.pdf",
                                            contentType: "application/pdf", uploadedBy: "u",
                                            uploadedAt: .now, tournament: nil)
        let row = TournamentInvitationDBRow(document)

        let target = try SupabaseSync.fileTarget(table: "tournament_invitations", payload: SupabaseSync.payload(row))

        XCTAssertEqual(target.bucket, "tournament-invitations")
        XCTAssertEqual(target.path, row.storagePath)
        XCTAssertEqual(target.contentType, "application/pdf")
    }

    func testAnUploadThatCanNeverSucceedCountsAsRefused() {
        XCTAssertThrowsError(try SupabaseSync.fileTarget(table: "teams", payload: Data("{}".utf8))) { error in
            XCTAssertTrue(SupabaseSync.isDenied(error), "unknown table must be dropped, not retried")
        }
        XCTAssertThrowsError(try SupabaseSync.fileTarget(table: "event_images", payload: Data("{}".utf8))) { error in
            XCTAssertTrue(SupabaseSync.isDenied(error), "a row without storage path must be dropped")
        }
    }

    // MARK: - Local copy

    func testAQueuedUploadProtectsTheLocalCopyFromPruning() throws {
        let (sync, context) = try makeSync()
        let id = UUID()
        enqueueUpload("event_images", id: id, payload: Data([1]), in: context)

        XCTAssertTrue(sync.hasPendingPush(id))
    }

    func testLocalFileDataReadsThisDevicesCopy() throws {
        let (sync, context) = try makeSync()
        let receipt = ExpenseReceipt(id: UUID(), imageData: Data([7, 7]), uploadedBy: "u", uploadedAt: .now,
                                     note: "Taxi", month: 11, year: 2026, tournament: nil)
        context.insert(receipt)
        try context.save()

        XCTAssertEqual(sync.localFileData(table: "expense_receipts", id: receipt.id), Data([7, 7]))

        context.delete(receipt)
        try context.save()
        XCTAssertNil(sync.localFileData(table: "expense_receipts", id: receipt.id))
    }

    // MARK: - Resend

    /// The photo was deleted on this device before its upload got through:
    /// the resend drops the entry (no network call — there is nothing to send).
    func testResendDropsAnUploadWhoseFileIsGone() async throws {
        let (sync, context) = try makeSync()
        let image = EventImage(id: UUID(), imageData: Data([1]), uploadedBy: "u", uploadedAt: .now, event: nil)
        enqueueUpload("event_images", id: image.id, payload: SupabaseSync.payload(EventImageDBRow(image)), in: context)
        XCTAssertEqual(PendingPush.count(in: context), 1)

        await sync.drainOutbox()

        XCTAssertEqual(PendingPush.count(in: ModelContext(try XCTUnwrap(sync.modelContainer))), 0)
    }
}
