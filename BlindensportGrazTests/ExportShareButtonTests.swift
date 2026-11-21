import XCTest
@testable import BlindensportGraz

/// A failed export must stay visible (dimmed button with the reason), so
/// `prepare` keeps the error instead of turning it into nil.
@MainActor
final class ExportShareButtonTests: XCTestCase {
    private struct DiskFull: LocalizedError {
        var errorDescription: String? { "Kein Speicherplatz frei." }
    }

    func testAFailedExportKeepsItsError() {
        let file = ExportShareButton.prepare("Test") { throw DiskFull() }

        guard case .failure(let error) = file else { return XCTFail("expected a failure") }
        XCTAssertEqual(error.localizedDescription, "Kein Speicherplatz frei.")
    }

    func testASuccessfulExportKeepsItsFile() {
        let url = URL(fileURLWithPath: "/tmp/teams.json")

        let file = ExportShareButton.prepare("Test") { url }

        XCTAssertEqual(try file.get(), url)
    }
}
