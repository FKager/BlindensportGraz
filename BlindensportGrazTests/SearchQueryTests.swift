import XCTest
@testable import BlindensportGraz

/// List searches ignore case and accents, so typing without umlauts finds
/// "Müller" — the previous lowercased().contains() did not.
final class SearchQueryTests: XCTestCase {
    func testIgnoresAccentsAndCase() {
        XCTAssertTrue(SearchQuery.matches("muller", in: "Anna Müller"))
        XCTAssertTrue(SearchQuery.matches("MÜLLER", in: "Anna Müller"))
        XCTAssertTrue(SearchQuery.matches("fussball", in: "Blindenfussball"))
    }

    func testEmptyOrBlankQueryMatchesEverything() {
        XCTAssertTrue(SearchQuery.matches("", in: "Anna"))
        XCTAssertTrue(SearchQuery.matches("   ", in: "Anna"))
    }

    func testTrimsTheQuery() {
        XCTAssertTrue(SearchQuery.matches("  anna ", in: "Anna Müller"))
    }

    func testAnyFieldMayMatch() {
        XCTAssertTrue(SearchQuery.matches("example.at", in: "Anna Müller", "anna@example.at"))
        XCTAssertFalse(SearchQuery.matches("berger", in: "Anna Müller", "anna@example.at"))
    }
}
