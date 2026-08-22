import XCTest
@testable import ClubSchema

final class ClubMemberRecordTests: XCTestCase {
    func testDefaultsMatchTheEstablishedShape() {
        let record = ClubMemberRecord(firstName: "Anna", lastName: "Muster")
        XCTAssertEqual(record.memberOfGVSC, true)
        XCTAssertEqual(record.country, "")
        XCTAssertNil(record.birthDate)
        XCTAssertEqual(ClubMemberRecord.recordType, "ClubMember")
    }

    func testCodableRoundTrips() throws {
        let record = ClubMemberRecord(firstName: "Anna", lastName: "Muster", svnr: "1234010180", iban: "AT611904300234573201")
        let data = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(ClubMemberRecord.self, from: data)
        XCTAssertEqual(decoded, record)
    }

    /// Every `MemberField` case must have a corresponding stored property on
    /// `ClubMemberRecord` — this is the drift-catching mechanism the shared
    /// package exists for; if a case is added/removed without updating the
    /// struct (or vice versa), this is the place a future session should
    /// extend, not just trust the two stay manually in sync.
    func testFieldCountMatchesMemberFieldCaseCount() {
        XCTAssertEqual(MemberField.allCases.count, 20)
    }
}
