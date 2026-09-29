import XCTest
@testable import BlindensportGraz

/// Fixtures in Fixtures/ are genuine Word 97–2003 binary files written by
/// macOS `textutil -convert doc` (Compound File signature D0CF11E0).
@MainActor
final class WordDocTextExtractorTests: XCTestCase {

    private func fixture(_ name: String) throws -> URL {
        try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "doc"),
                      "missing test fixture \(name).doc")
    }

    func testExtractsGermanInvitationWithUmlautsEuroAndDashes() throws {
        let text = try WordDocTextExtractor.text(fromFileAt: fixture("WordDocInvitation"))
        XCTAssertTrue(text.hasPrefix("Einladung zum 12. Internationalen Torball-Turnier\n"))
        XCTAssertTrue(text.contains("Datum: Samstag, 14. März 2026 bis Sonntag, 15. März 2026"))
        XCTAssertTrue(text.contains("Ort: Sporthalle Graz-Süd, Straßganger Straße 12, 8054 Graz, Österreich"))
        XCTAssertTrue(text.contains("Startgeld: 50 € pro Team"))
        XCTAssertTrue(text.contains("28. Februar 2026 – bitte"))
    }

    func testExtractsCharactersOutsideWindows1252() throws {
        let text = try WordDocTextExtractor.text(fromFileAt: fixture("WordDocUnicode"))
        XCTAssertTrue(text.contains("Łódź und Kraków"))
        XCTAssertTrue(text.contains("„Ελλάδα“"))
        XCTAssertTrue(text.contains("Wrocław"))
    }

    func testExtractsLongDocumentStoredOutsideTheMiniStream() throws {
        let text = try WordDocTextExtractor.text(fromFileAt: fixture("WordDocLong"))
        XCTAssertGreaterThan(text.count, 4096)
        XCTAssertTrue(text.contains("Absatz 0: Einladung"))
        XCTAssertTrue(text.contains("Absatz 39: Einladung"))
    }

    func testTableCellsBecomeTabSeparatedText() throws {
        let text = try WordDocTextExtractor.text(fromFileAt: fixture("WordDocTable"))
        XCTAssertTrue(text.contains("Turnierplan"))
        XCTAssertTrue(text.contains("Beginn\t09:00"))
        XCTAssertTrue(text.contains("Ort\tGraz"))
    }

    func testRejectsNonWordAndTruncatedFiles() throws {
        XCTAssertThrowsError(try WordDocTextExtractor.text(from: Data("Einladung".utf8))) { error in
            XCTAssertEqual(error as? WordDocTextExtractor.ExtractionError, .notACompoundFile)
        }
        let truncated = try Data(contentsOf: fixture("WordDocInvitation")).prefix(3000)
        XCTAssertThrowsError(try WordDocTextExtractor.text(from: Data(truncated)))
    }

    func testImporterRoutesDocFilesToTheExtractor() throws {
        let text = try TournamentInvitationImporter.extractText(from: fixture("WordDocInvitation"))
        XCTAssertTrue(text.contains("Torball-Turnier"))
    }
}
