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

    // MARK: - weeklyRangeDates (AddTrainingView's weekly-range repeat option)

    func testWeeklyRangeDatesReturnsOnlyStartWhenNoEndDateGiven() {
        let start = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(Training.weeklyRangeDates(from: start, through: nil), [start])
    }

    func testWeeklyRangeDatesReturnsOnlyStartWhenEndDateIsBeforeStart() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Vienna")!
        let start = calendar.date(from: DateComponents(year: 2026, month: 9, day: 14, hour: 18))!
        let end = calendar.date(from: DateComponents(year: 2026, month: 9, day: 1))!
        XCTAssertEqual(Training.weeklyRangeDates(from: start, through: end, calendar: calendar), [start])
    }

    func testWeeklyRangeDatesIncludesStartAndEndWhenEndFallsExactlyOnAWeeklyOccurrence() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Vienna")!
        // Monday 2026-09-14, 18:00, repeated weekly through Monday 2026-10-05 -> 4 occurrences.
        let start = calendar.date(from: DateComponents(year: 2026, month: 9, day: 14, hour: 18))!
        let end = calendar.date(from: DateComponents(year: 2026, month: 10, day: 5))!
        let dates = Training.weeklyRangeDates(from: start, through: end, calendar: calendar)

        XCTAssertEqual(dates.count, 4)
        XCTAssertEqual(dates.first, start)
        for date in dates {
            XCTAssertEqual(calendar.component(.weekday, from: date), calendar.component(.weekday, from: start))
            XCTAssertEqual(calendar.component(.hour, from: date), 18)
        }
    }

    func testWeeklyRangeDatesStopsBeforeTheNextOccurrenceWhenEndFallsMidWeek() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Vienna")!
        // Monday 2026-09-14 through Wednesday 2026-09-23: the third Monday
        // (2026-09-28) is past the end date, so only 2 occurrences.
        let start = calendar.date(from: DateComponents(year: 2026, month: 9, day: 14, hour: 18))!
        let end = calendar.date(from: DateComponents(year: 2026, month: 9, day: 23))!
        let dates = Training.weeklyRangeDates(from: start, through: end, calendar: calendar)
        XCTAssertEqual(dates.count, 2)
    }

    func testWeeklyRangeDatesStaysOnSameWeekdayAndTimeAcrossDSTBoundary() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Vienna")!
        // Austria's DST end (clocks back) fell on 2026-10-25 — straddle it.
        let start = calendar.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 18))!
        let end = calendar.date(from: DateComponents(year: 2026, month: 11, day: 2))!
        let dates = Training.weeklyRangeDates(from: start, through: end, calendar: calendar)

        XCTAssertEqual(dates.count, 3)
        for date in dates {
            XCTAssertEqual(calendar.component(.hour, from: date), 18)
            XCTAssertEqual(calendar.component(.weekday, from: date), calendar.component(.weekday, from: start))
        }
    }
}
