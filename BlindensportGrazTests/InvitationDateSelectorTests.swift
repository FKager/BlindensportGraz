import XCTest
@testable import BlindensportGraz

/// Invitations mention many dates; only the playing days should be picked.
@MainActor
final class InvitationDateSelectorTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }()
    /// Fixed "today" before all the example tournaments.
    private var now: Date { day(2026, 1, 15) }

    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func assertDates(_ text: String, start: Date, end: Date, file: StaticString = #filePath, line: UInt = #line) {
        let dates = InvitationDateSelector.eventDates(in: text, now: now, calendar: calendar)
        XCTAssertEqual(dates?.start, start, "start", file: file, line: line)
        XCTAssertEqual(dates?.end, end, "end", file: file, line: line)
    }

    func testStartsOnArrivalDayAndIgnoresLetterDateTimeAndDeadlines() {
        assertDates("""
            Graz, 12. Jänner 2026
            Einladung zum 12. Internationalen Torball-Turnier
            Termin: 14.–15. März 2026
            Spielbeginn: 9:00 Uhr
            Anmeldeschluss: 28. Februar 2026
            Überweisung des Startgeldes bis 5.3.2026
            Anreise am 13.03.2026 möglich
            """, start: day(2026, 3, 13), end: day(2026, 3, 15))
    }

    func testAnkunftBeforeWeekendRange() {
        assertDates("""
            Ankunft: Freitag, 5. Juni 2026 ab 18 Uhr
            Samstag, 6. Juni 2026 bis Sonntag, 7. Juni 2026 – Showdown Open
            """, start: day(2026, 6, 5), end: day(2026, 6, 7))
    }

    func testArrivalDeadlineIsNotTheArrivalDay() {
        assertDates("""
            Termin: 14.–15. März 2026
            Bitte teilt uns eure Anreise spätestens am 12. März 2026 mit.
            """, start: day(2026, 3, 14), end: day(2026, 3, 15))
    }

    func testArrivalMoreThanAWeekBeforeIsIgnored() {
        assertDates("""
            Termin: 14.–15. März 2026
            Anreise: 1. März 2026
            """, start: day(2026, 3, 14), end: day(2026, 3, 15))
    }

    func testPrefersFindetStattOverRegistrationDeadline() {
        assertDates("""
            Anmeldeschluss: 1. Mai 2026
            Das Goalball-Turnier findet am 23. Mai 2026 in Wien statt.
            """, start: day(2026, 5, 23), end: day(2026, 5, 23))
    }

    func testSkipsLetterDateWithoutAnyKeywords() {
        assertDates("""
            Wien, 3. Februar 2026

            Liebe Sportfreunde,
            wir freuen uns, euch am 18.04.2026 in Linz begrüßen zu dürfen.
            """, start: day(2026, 4, 18), end: day(2026, 4, 18))
    }

    func testDateOnTheLineAfterTermin() {
        assertDates("""
            Einladung
            Termin:
            21. März 2026
            Bitte bis spätestens 1. März 2026 anmelden.
            """, start: day(2026, 3, 21), end: day(2026, 3, 21))
    }

    func testWeekdayRangeAndNennschluss() {
        assertDates("""
            Salzburg, am 10. Jänner 2026
            Samstag, 6. Juni 2026 bis Sonntag, 7. Juni 2026 – Showdown Open
            Nennschluss 15. Mai 2026
            """, start: day(2026, 6, 6), end: day(2026, 6, 7))
    }

    func testVomBisRangeAndHotelDeadline() {
        assertDates("""
            Das Turnier findet vom 7. bis 8. November 2026 statt.
            Zimmerreservierung bis 1. Oktober 2026.
            """, start: day(2026, 11, 7), end: day(2026, 11, 8))
    }

    func testNumericRange() {
        assertDates("""
            Turniertermin: 14.-15.03.2026
            Anmeldung bis 20.02.2026
            """, start: day(2026, 3, 14), end: day(2026, 3, 15))
    }

    /// Every common way of writing the tournament date, inside an invitation
    /// that also has a letter date, a start time and a deadline.
    func testRecognisesCommonDateFormats() {
        let cases: [(written: String, start: Date, end: Date)] = [
            ("14 März 2026", day(2026, 3, 14), day(2026, 3, 14)),
            ("Samstag 14 März 2026", day(2026, 3, 14), day(2026, 3, 14)),
            ("14/03/2026", day(2026, 3, 14), day(2026, 3, 14)),
            ("14.03.26", day(2026, 3, 14), day(2026, 3, 14)),
            ("Sa, 14.3.", day(2026, 3, 14), day(2026, 3, 14)),
            ("14. März", day(2026, 3, 14), day(2026, 3, 14)),
            ("Samstag, 14.03.", day(2026, 3, 14), day(2026, 3, 14)),
            ("14.–15.3.2026", day(2026, 3, 14), day(2026, 3, 15)),
            ("14. und 15. März 2026", day(2026, 3, 14), day(2026, 3, 15)),
            ("14 und 15 März 2026", day(2026, 3, 14), day(2026, 3, 15)),
            ("14.3.-15.3.2026", day(2026, 3, 14), day(2026, 3, 15)),
            ("14th March 2026", day(2026, 3, 14), day(2026, 3, 14)),
            ("March 14, 2026", day(2026, 3, 14), day(2026, 3, 14)),
            ("2026-03-14", day(2026, 3, 14), day(2026, 3, 14)),
            ("14. 03. 2026", day(2026, 3, 14), day(2026, 3, 14)),
            ("Sa. 14.03.2026 – So. 15.03.2026", day(2026, 3, 14), day(2026, 3, 15)),
            ("von Samstag, 14. bis Sonntag, 15. März 2026", day(2026, 3, 14), day(2026, 3, 15)),
            ("14.-15. Mär. 2026", day(2026, 3, 14), day(2026, 3, 15)),
            ("14.–15. Mrz. 2026", day(2026, 3, 14), day(2026, 3, 15)),
        ]
        for item in cases {
            let text = """
                Graz, 12. Jänner 2026
                Einladung zum Torball-Turnier
                Termin: \(item.written)
                Spielbeginn: 9:00 Uhr
                Anmeldeschluss: 28. Februar 2026
                """
            let dates = InvitationDateSelector.eventDates(in: text, now: now, calendar: calendar)
            XCTAssertEqual(dates?.start, item.start, "start for \"\(item.written)\"")
            XCTAssertEqual(dates?.end, item.end, "end for \"\(item.written)\"")
        }
    }

    func testNoDatesGivesNil() {
        XCTAssertNil(InvitationDateSelector.eventDates(in: "Beginn 9:00 Uhr, Samstag", now: now, calendar: calendar))
    }

    // MARK: AI cross-check

    private let aiText = """
        Graz, 12. Jänner 2026
        Termin: 14.–15. März 2026
        Anmeldeschluss: 28. Februar 2026
        """

    private let aiTextWithArrival = """
        Graz, 12. Jänner 2026
        Termin: 14.–15. März 2026
        Anreise am 13.03.2026
        Anmeldeschluss: 28. Februar 2026
        """

    func testAIFirstPlayingDayMovesToArrivalDay() {
        let dates = TournamentInvitationImporter.checkedEventDates(
            aiStart: day(2026, 3, 14), aiEnd: day(2026, 3, 15), text: aiTextWithArrival, now: now, calendar: calendar)
        XCTAssertEqual(dates?.start, day(2026, 3, 13))
        XCTAssertEqual(dates?.end, day(2026, 3, 15))
    }

    func testAIArrivalDayIsAccepted() {
        let dates = TournamentInvitationImporter.checkedEventDates(
            aiStart: day(2026, 3, 13), aiEnd: day(2026, 3, 15), text: aiTextWithArrival, now: now, calendar: calendar)
        XCTAssertEqual(dates?.start, day(2026, 3, 13))
        XCTAssertEqual(dates?.end, day(2026, 3, 15))
    }

    func testKeepsAIDatesThatMatchTheEvent() {
        let dates = TournamentInvitationImporter.checkedEventDates(
            aiStart: day(2026, 3, 14), aiEnd: day(2026, 3, 15), text: aiText, now: now, calendar: calendar)
        XCTAssertEqual(dates?.start, day(2026, 3, 14))
        XCTAssertEqual(dates?.end, day(2026, 3, 15))
    }

    func testOverrulesAIWhenItPickedTheDeadline() {
        let dates = TournamentInvitationImporter.checkedEventDates(
            aiStart: day(2026, 2, 28), aiEnd: day(2026, 2, 28), text: aiText, now: now, calendar: calendar)
        XCTAssertEqual(dates?.start, day(2026, 3, 14))
        XCTAssertEqual(dates?.end, day(2026, 3, 15))
    }

    func testOverrulesAIWhenItPickedTheLetterDate() {
        let dates = TournamentInvitationImporter.checkedEventDates(
            aiStart: day(2026, 1, 12), aiEnd: nil, text: aiText, now: now, calendar: calendar)
        XCTAssertEqual(dates?.start, day(2026, 3, 14))
    }

    func testOverrulesAIDateThatIsNotInTheText() {
        let dates = TournamentInvitationImporter.checkedEventDates(
            aiStart: day(2026, 7, 1), aiEnd: nil, text: aiText, now: now, calendar: calendar)
        XCTAssertEqual(dates?.start, day(2026, 3, 14))
    }
}
