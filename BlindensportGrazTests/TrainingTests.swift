import XCTest
@testable import BlindensportGraz

/// Coverage for `Training`'s own pure logic — the Offen/Durchgeführt/Abgesagt
/// status (user request 2026-09-10) and the existing endDate recompute. No
/// CloudKit/SwiftData context involved.
@MainActor
final class TrainingTests: XCTestCase {

    func testDefaultStatusIsOpen() {
        let training = Training(title: "Techniktraining", sport: "Torball", location: "Halle", startDate: .now)
        XCTAssertEqual(training.status, Training.openStatus)
        XCTAssertEqual(training.statusLabel, "Offen")
    }

    func testStatusLabelsMatchEachKnownStatus() {
        let training = Training(title: "Techniktraining", sport: "Torball", location: "Halle", startDate: .now)

        training.status = Training.heldStatus
        XCTAssertEqual(training.statusLabel, "Durchgeführt")

        training.status = Training.cancelledStatus
        XCTAssertEqual(training.statusLabel, "Abgesagt")
    }

    func testStatusLabelFallsBackToRawValueForAnUnknownStatus() {
        let training = Training(title: "Techniktraining", sport: "Torball", location: "Halle", startDate: .now)
        training.status = "some-future-status"
        XCTAssertEqual(training.statusLabel, "some-future-status")
    }

    func testRecomputeEndDateFollowsStartDateAndDuration() {
        let start = Date(timeIntervalSince1970: 0)
        let training = Training(title: "Techniktraining", sport: "Torball", location: "Halle",
                                startDate: start, durationMinutes: 60)
        XCTAssertEqual(training.endDate, start.addingTimeInterval(3600))

        training.durationMinutes = 90
        training.recomputeEndDate()
        XCTAssertEqual(training.endDate, start.addingTimeInterval(5400))
    }
}
