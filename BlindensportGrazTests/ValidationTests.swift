import XCTest
@testable import BlindensportGraz

/// Coverage for `Validation.swift` (audit.md Security Findings 4/5,
/// Enhancement #7). Every check here is advisory-only in the app itself —
/// these tests only verify the pure functions' own correctness, not any UI
/// wiring (see MemberImportExportTests for confirmation the import path
/// keeps accepting malformed data unchanged).
final class ValidationTests: XCTestCase {

    // MARK: - isPlausibleEmail

    func testBlankEmailIsNotFlaggedAsMalformed() {
        XCTAssertTrue(Validation.isPlausibleEmail(""))
        XCTAssertTrue(Validation.isPlausibleEmail("   "))
    }

    func testWellFormedEmailPasses() {
        XCTAssertTrue(Validation.isPlausibleEmail("franz.kager@gmx.net"))
        XCTAssertTrue(Validation.isPlausibleEmail("blindensport.gvsc@gmail.com"))
    }

    func testObviouslyMalformedEmailFails() {
        XCTAssertFalse(Validation.isPlausibleEmail("not-an-email"))
        XCTAssertFalse(Validation.isPlausibleEmail("missing-domain@"))
        XCTAssertFalse(Validation.isPlausibleEmail("@missing-local.com"))
        XCTAssertFalse(Validation.isPlausibleEmail("two@at@signs.com"))
        XCTAssertFalse(Validation.isPlausibleEmail("has space@example.com"))
        XCTAssertFalse(Validation.isPlausibleEmail("no-tld@example"))
    }

    // MARK: - ibanChecksumIsValid

    func testBlankIBANIsNotFlagged() {
        XCTAssertTrue(Validation.ibanChecksumIsValid(""))
    }

    func testKnownValidIBANPassesChecksum() {
        // Austria's own published IBAN example — real, well-known test IBAN.
        XCTAssertTrue(Validation.ibanChecksumIsValid("AT611904300234573201"))
    }

    func testWellFormedButWrongChecksumIBANFails() {
        // Same as above with one digit changed — same length/shape, wrong checksum.
        XCTAssertFalse(Validation.ibanChecksumIsValid("AT611904300234573202"))
    }

    func testObviouslyMalformedIBANFails() {
        XCTAssertFalse(Validation.ibanChecksumIsValid("not an iban"))
    }

    // MARK: - isPlausibleAustrianSVNR

    func testBlankSVNRIsNotFlagged() {
        XCTAssertTrue(Validation.isPlausibleAustrianSVNR(""))
    }

    func testTenDigitSVNRPasses() {
        XCTAssertTrue(Validation.isPlausibleAustrianSVNR("1234010180"))
        XCTAssertTrue(Validation.isPlausibleAustrianSVNR("1234 010180")) // separators allowed
    }

    func testWrongLengthSVNRFails() {
        XCTAssertFalse(Validation.isPlausibleAustrianSVNR("12345"))
        XCTAssertFalse(Validation.isPlausibleAustrianSVNR("123456789012"))
    }
}
