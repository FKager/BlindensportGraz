import XCTest
@testable import BlindensportGraz

/// Counts in the UI use automatic grammar agreement (`inflect: true`), so
/// "1 Mitglied" / "3 Mitglieder" come out right without hand-written plurals.
final class InflectionTests: XCTestCase {
    private let german = Locale(identifier: "de_AT")

    private func members(_ count: Int) -> String {
        String(AttributedString(localized: "^[\(count) Mitglied](inflect: true)", locale: german).characters)
    }

    private func accounts(_ count: Int) -> String {
        String(AttributedString(localized: "^[\(count) Konto](inflect: true) freigeben?", locale: german).characters)
    }

    func testTeamMemberCountAgreesWithTheNumber() {
        XCTAssertEqual(members(1), "1 Mitglied")
        XCTAssertEqual(members(3), "3 Mitglieder")
        XCTAssertEqual(members(0), "0 Mitglieder")
    }

    func testBulkApprovalTitleAgreesWithTheNumber() {
        XCTAssertEqual(accounts(1), "1 Konto freigeben?")
        XCTAssertEqual(accounts(2), "2 Konten freigeben?")
    }
}
