import XCTest
@testable import BlindensportGraz

final class CalendarEventExportTests: XCTestCase {

    private func makeDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return Calendar.current.date(from: components)!
    }

    // MARK: - fields(for:) mapping

    func testFieldsMapsTitleStartAndEndDirectlyFromTheEvent() {
        let start = makeDate(2026, 9, 5, 18, 0)
        // Training derives endDate from startDate + durationMinutes (no
        // direct endDate param on its initializer) — 120 min -> 20:00.
        let training = Training(title: "Torball-Training", sport: "Torball", location: "Sporthalle Eggenberg",
                                 startDate: start, durationMinutes: 120)

        let fields = CalendarEventExport.fields(for: training)

        XCTAssertEqual(fields.title, "Torball-Training")
        XCTAssertEqual(fields.startDate, start)
        XCTAssertEqual(fields.endDate, start.addingTimeInterval(120 * 60))
    }

    func testFieldsCombinesVenueAndAddressIntoOneLocationString() {
        let training = Training(title: "Training", sport: "Torball", location: "Sporthalle Eggenberg",
                                 startDate: .now)
        training.street = "Eggenberger Allee 1"
        training.zip = "8020"
        training.city = "Graz"
        training.country = "Österreich"

        let fields = CalendarEventExport.fields(for: training)

        XCTAssertEqual(fields.location, "Sporthalle Eggenberg, Eggenberger Allee 1, 8020 Graz, Österreich")
    }

    func testFieldsSkipsEmptyAddressPartsWithoutStrayCommas() {
        let training = Training(title: "Training", sport: "Torball", location: "Halle", startDate: .now)
        // street/zip/city/country all left blank.
        let fields = CalendarEventExport.fields(for: training)
        XCTAssertEqual(fields.location, "Halle")
    }

    func testFieldsWorksForTournamentToo() {
        let start = makeDate(2026, 9, 5, 9, 0)
        let end = makeDate(2026, 9, 6, 17, 0)
        let tournament = Tournament(title: "Landesmeisterschaft", sport: "Torball", location: "Graz",
                                     startDate: start, endDate: end)

        let fields = CalendarEventExport.fields(for: tournament)

        XCTAssertEqual(fields.title, "Landesmeisterschaft")
        XCTAssertEqual(fields.startDate, start)
        XCTAssertEqual(fields.endDate, end)
    }

    // MARK: - icsFile(for:) rendering

    func testIcsFileContainsCorrectTitleLocationAndDates() throws {
        let start = makeDate(2026, 9, 5, 18, 0)
        let end = makeDate(2026, 9, 5, 20, 0)
        let fields = CalendarEventExport.EventFields(title: "Torball-Training", location: "Sporthalle Eggenberg",
                                                        startDate: start, endDate: end)

        let url = try CalendarEventExport.icsFile(for: fields)
        defer { try? FileManager.default.removeItem(at: url) }

        let contents = try String(contentsOf: url, encoding: .utf8)

        XCTAssertTrue(contents.contains("BEGIN:VCALENDAR"))
        XCTAssertTrue(contents.contains("BEGIN:VEVENT"))
        XCTAssertTrue(contents.contains("SUMMARY:Torball-Training"))
        XCTAssertTrue(contents.contains("LOCATION:Sporthalle Eggenberg"))

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        XCTAssertTrue(contents.contains("DTSTART:\(formatter.string(from: start))"))
        XCTAssertTrue(contents.contains("DTEND:\(formatter.string(from: end))"))
    }

    func testIcsFileEscapesCommasAndSemicolonsInTextFields() throws {
        let fields = CalendarEventExport.EventFields(
            title: "Turnier, Halbfinale; Runde", location: "Halle A, Ecke B",
            startDate: .now, endDate: .now.addingTimeInterval(3600))

        let url = try CalendarEventExport.icsFile(for: fields)
        defer { try? FileManager.default.removeItem(at: url) }
        let contents = try String(contentsOf: url, encoding: .utf8)

        XCTAssertTrue(contents.contains("SUMMARY:Turnier\\, Halbfinale\\; Runde"))
        XCTAssertTrue(contents.contains("LOCATION:Halle A\\, Ecke B"))
    }
}
