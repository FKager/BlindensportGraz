import XCTest
@testable import CloudKitS2SCore

/// Row mapping between `MemberRecord` and the `members` / `member_contacts`
/// tables (no network).
final class MemberStoreTests: XCTestCase {

    func testRecordSplitsIntoMemberAndContactRowsWithoutProtectedFields() {
        let record = MemberRecord(id: UUID().uuidString, firstName: "Anna", lastName: "Muster",
                                  street: "Gasse 1", email: "anna@example.org", memberNumber: "42",
                                  joinedAt: Date(timeIntervalSince1970: 1_700_000_000), sportId: "torball",
                                  svnr: "1234", iban: "AT00", defaultFunction: "Spielerin", memberOfGVSC: false)

        let member = record.memberRow
        let contact = record.contactRow
        XCTAssertEqual(member["first_name"] as? String, "Anna")
        XCTAssertEqual(member["member_number"] as? String, "42")
        XCTAssertEqual(member["member_of_gvsc"] as? Bool, false)
        XCTAssertEqual(contact["street"] as? String, "Gasse 1")
        XCTAssertEqual(contact["email"] as? String, "anna@example.org")
        let columns = Set(member.keys).union(contact.keys)
        XCTAssertTrue(columns.isDisjoint(with: ["svnr", "iban", "birth_date", "last_medical_examination"]),
                      "protected fields go only to member_private")
    }

    func testRowsMapBackWithUppercaseIDAndFractionalTimestamp() throws {
        let id = UUID()
        let record = MemberRecord(
            member: ["id": id.uuidString.lowercased(), "first_name": "Bert", "last_name": "Beispiel",
                     "member_number": "7", "sport_id": "goalball", "default_function": "",
                     "member_of_gvsc": true, "joined_at": "2026-10-13T20:55:51.439+00:00"],
            contact: ["id": id.uuidString.lowercased(), "city": "Graz", "phone": "0664"])

        XCTAssertEqual(record.id, id.uuidString)
        XCTAssertEqual(record.city, "Graz")
        XCTAssertEqual(record.sportId, "goalball")
        XCTAssertEqual(record.joinedAt.timeIntervalSince1970, 1_791_924_951.439, accuracy: 0.001)
        XCTAssertTrue(record.privateData.isEmpty)
    }

    func testMissingContactRowGivesEmptyContactFields() {
        let record = MemberRecord(member: ["id": UUID().uuidString, "first_name": "C", "last_name": "D",
                                           "joined_at": "2026-01-01T00:00:00+00:00"],
                                  contact: [:])
        XCTAssertEqual(record.street, "")
        XCTAssertEqual(record.email, "")
        XCTAssertTrue(record.memberOfGVSC)
    }

    func testTimestampRoundTrips() throws {
        let date = Date(timeIntervalSince1970: 1_800_000_000.25)
        let parsed = try XCTUnwrap(SupabaseTimestamp.parse(SupabaseTimestamp.format(date)))
        XCTAssertEqual(parsed.timeIntervalSince1970, date.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertNotNil(SupabaseTimestamp.parse("2026-10-13T20:55:51+00:00"))
    }
}
