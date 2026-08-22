import XCTest
import CloudKit
@testable import BlindensportGraz

/// Exercises the exact same CKRecord field mapping
/// `CloudKitSync.pushExpenseReceipt`/`pullExpenseReceipts` use, without
/// touching `CloudKitSync.shared` — that lazily constructs a real
/// `CKContainer`, which hard-crashes under this sandbox's unsigned test
/// runs (missing iCloud entitlement, see cerebrum.md bug-202). `CKRecord`
/// and `CKAsset` themselves need no container/entitlement — they're plain
/// local value objects — so encoding into one, staging a real temp-file
/// asset, and decoding back out is safe to test directly.
final class ExpenseReceiptCloudKitRoundTripTests: XCTestCase {

    /// Mirrors `pushExpenseReceipt`'s field assignments exactly (minus the
    /// actual network upsert/retry).
    private func encode(_ receipt: ExpenseReceipt) throws -> (record: CKRecord, tmpURL: URL) {
        let record = CKRecord(recordType: CKSchema.ExpenseReceipt.recordType,
                               recordID: CKRecord.ID(recordName: receipt.id.uuidString))
        record[CKSchema.ExpenseReceipt.uploadedBy] = receipt.uploadedBy
        record[CKSchema.ExpenseReceipt.uploadedAt] = receipt.uploadedAt
        record[CKSchema.ExpenseReceipt.note] = receipt.note
        record[CKSchema.ExpenseReceipt.month] = receipt.month
        record[CKSchema.ExpenseReceipt.year] = receipt.year
        record[CKSchema.ExpenseReceipt.tournamentID] = receipt.tournament?.id.uuidString

        let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(receipt.id.uuidString).jpg")
        try receipt.imageData.write(to: tmpURL)
        record[CKSchema.ExpenseReceipt.asset] = CKAsset(fileURL: tmpURL)

        return (record, tmpURL)
    }

    /// Mirrors `pullExpenseReceipts`'s field-reading exactly (minus the
    /// actual `fetchAll`/local-existence-skip logic and Tournament lookup,
    /// which needs a ModelContext — tournament resolution is covered
    /// separately below via a plain id round-trip).
    private func decode(_ record: CKRecord) throws -> (imageData: Data, uploadedBy: String, uploadedAt: Date,
                                                         note: String, month: Int?, year: Int?, tournamentIDString: String?) {
        let asset = try XCTUnwrap(record[CKSchema.ExpenseReceipt.asset] as? CKAsset)
        let fileURL = try XCTUnwrap(asset.fileURL)
        let data = try Data(contentsOf: fileURL)
        let uploadedBy = record[CKSchema.ExpenseReceipt.uploadedBy] as? String ?? ""
        let uploadedAt = try XCTUnwrap(record[CKSchema.ExpenseReceipt.uploadedAt] as? Date)
        let note = record[CKSchema.ExpenseReceipt.note] as? String ?? ""
        let month = record[CKSchema.ExpenseReceipt.month] as? Int
        let year = record[CKSchema.ExpenseReceipt.year] as? Int
        let tournamentIDString = record[CKSchema.ExpenseReceipt.tournamentID] as? String
        return (data, uploadedBy, uploadedAt, note, month, year, tournamentIDString)
    }

    func testMonthScopedReceiptRoundTripsAllFields() throws {
        let uploadedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let imageData = Data([0xFF, 0xD8, 0xFF, 0x01, 0x02, 0x03])
        let receipt = ExpenseReceipt(imageData: imageData, uploadedBy: "user-123", uploadedAt: uploadedAt,
                                      note: "Fahrtkosten Turnier", month: 9, year: 2026)

        let (record, tmpURL) = try encode(receipt)
        defer { try? FileManager.default.removeItem(at: tmpURL) }
        let decoded = try decode(record)

        XCTAssertEqual(decoded.imageData, imageData)
        XCTAssertEqual(decoded.uploadedBy, "user-123")
        XCTAssertEqual(decoded.uploadedAt, uploadedAt)
        XCTAssertEqual(decoded.note, "Fahrtkosten Turnier")
        XCTAssertEqual(decoded.month, 9)
        XCTAssertEqual(decoded.year, 2026)
        XCTAssertNil(decoded.tournamentIDString)
    }

    func testTournamentScopedReceiptRoundTripsTournamentIDAndOmitsMonthYear() throws {
        let tournament = Tournament(title: "Landesmeisterschaft", sport: "Torball", location: "Graz",
                                     startDate: .now, endDate: .now.addingTimeInterval(3600))
        let imageData = Data([0xFF, 0xD8, 0xFF])
        let receipt = ExpenseReceipt(imageData: imageData, uploadedBy: "user-456", tournament: tournament)

        let (record, tmpURL) = try encode(receipt)
        defer { try? FileManager.default.removeItem(at: tmpURL) }
        let decoded = try decode(record)

        XCTAssertEqual(decoded.imageData, imageData)
        XCTAssertEqual(decoded.tournamentIDString, tournament.id.uuidString)
        XCTAssertNil(decoded.month)
        XCTAssertNil(decoded.year)
    }

    func testRecordIDRoundTripsAsTheReceiptsID() throws {
        let receipt = ExpenseReceipt(imageData: Data([0x01]), uploadedBy: "u")
        let (record, tmpURL) = try encode(receipt)
        defer { try? FileManager.default.removeItem(at: tmpURL) }

        XCTAssertEqual(UUID(uuidString: record.recordID.recordName), receipt.id)
    }
}
