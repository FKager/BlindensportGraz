import XCTest
import SwiftData
import ZIPFoundation
@testable import BlindensportGraz

final class TrainingsfrequenzlisteCalculationTests: XCTestCase {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            User.self, SportEvent.self, Tournament.self, Training.self, Team.self,
            TeamMembership.self, EventParticipation.self, Member.self,
            EventImage.self, Attendance.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func makeTraining(_ context: ModelContext, team: Team, day: Int, month: Int = 7, year: Int = 2026) -> Training {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 18
        let date = Calendar.current.date(from: components)!
        let training = Training(title: "Training \(day).\(month).", sport: team.sport, location: "Graz", startDate: date, teams: [team])
        context.insert(training)
        return training
    }

    // MARK: - summary

    func testSummaryMarksAttendedDatesAsPresent() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let team = Team(name: "Torball 1", sport: "Torball")
        context.insert(team)
        let member = Member(firstName: "Anna", lastName: "Sportlerin")
        context.insert(member)
        let membership = TeamMembership(member: member, team: team, role: "player")
        context.insert(membership)

        let training1 = makeTraining(context, team: team, day: 5)
        let training2 = makeTraining(context, team: team, day: 12)
        context.insert(Attendance(event: training1, membership: membership, attended: true))
        context.insert(Attendance(event: training2, membership: membership, attended: false))

        let summary = TrainingsfrequenzlisteCalculator.summary(sport: team.sport, halfYear: .second, year: 2026, in: context)

        XCTAssertEqual(summary.trainingDates.count, 2)
        XCTAssertEqual(summary.people.count, 1)
        let person = try XCTUnwrap(summary.people.first)
        let day5 = Calendar.current.startOfDay(for: training1.startDate)
        let day12 = Calendar.current.startOfDay(for: training2.startDate)
        XCTAssertTrue(person.attended(on: day5))
        XCTAssertFalse(person.attended(on: day12))
        XCTAssertEqual(summary.totalPresent(on: day5), 1)
        XCTAssertEqual(summary.totalPresent(on: day12), 0)
    }

    func testSummaryTreatsMissingAttendanceRecordAsNotPresent() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let team = Team(name: "Torball 1", sport: "Torball")
        context.insert(team)
        let member = Member(firstName: "Bernd", lastName: "Neu")
        context.insert(member)
        let membership = TeamMembership(member: member, team: team, role: "player")
        context.insert(membership)
        let training = makeTraining(context, team: team, day: 5)
        // No Attendance row inserted at all — matches the app's "created lazily
        // on first toggle" convention, must still resolve to "n", not crash/blank.

        let summary = TrainingsfrequenzlisteCalculator.summary(sport: team.sport, halfYear: .second, year: 2026, in: context)
        let person = try XCTUnwrap(summary.people.first)
        XCTAssertFalse(person.attended(on: Calendar.current.startOfDay(for: training.startDate)))
    }

    func testSummaryFiltersToRequestedSportHalfYearAndYear() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let team = Team(name: "Torball 1", sport: "Torball")
        let otherTeam = Team(name: "Torball 2", sport: "Torball")
        let otherSportTeam = Team(name: "Blindenfußball", sport: "Blindenfußball")
        context.insert(team)
        context.insert(otherTeam)
        context.insert(otherSportTeam)

        _ = makeTraining(context, team: team, day: 5, month: 7, year: 2026) // in 2. Halbjahr
        _ = makeTraining(context, team: team, day: 5, month: 9, year: 2026) // also in 2. Halbjahr
        _ = makeTraining(context, team: team, day: 5, month: 1, year: 2026) // wrong half (1. Halbjahr)
        _ = makeTraining(context, team: team, day: 5, month: 7, year: 2025) // wrong year
        _ = makeTraining(context, team: otherTeam, day: 6, month: 7, year: 2026) // same sport, different team — now included, the list is scoped by sport not team
        _ = makeTraining(context, team: otherSportTeam, day: 7, month: 7, year: 2026) // wrong sport

        let summary = TrainingsfrequenzlisteCalculator.summary(sport: "Torball", halfYear: .second, year: 2026, in: context)
        XCTAssertEqual(summary.trainingDates.count, 3)
        XCTAssertEqual(Set(summary.teams.map(\.id)), Set([team.id, otherTeam.id]))
    }

    /// The whole point of the refactor: two different teams training the
    /// same sport in the period contribute their attendees to one combined
    /// roster, deduped by person, not filtered down to a single team.
    func testSummaryCombinesRosterAcrossTeamsSharingASport() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let team = Team(name: "Torball Damen", sport: "Torball")
        let otherTeam = Team(name: "Torball Herren", sport: "Torball")
        context.insert(team)
        context.insert(otherTeam)

        let member1 = Member(firstName: "Anna", lastName: "Damen")
        context.insert(member1)
        let membership1 = TeamMembership(member: member1, team: team, role: "player")
        context.insert(membership1)

        let member2 = Member(firstName: "Bernd", lastName: "Herren")
        context.insert(member2)
        let membership2 = TeamMembership(member: member2, team: otherTeam, role: "player")
        context.insert(membership2)

        let training1 = makeTraining(context, team: team, day: 5)
        let training2 = makeTraining(context, team: otherTeam, day: 12)
        context.insert(Attendance(event: training1, membership: membership1, attended: true))
        context.insert(Attendance(event: training2, membership: membership2, attended: true))

        let summary = TrainingsfrequenzlisteCalculator.summary(sport: "Torball", halfYear: .second, year: 2026, in: context)
        XCTAssertEqual(summary.people.map(\.firstName).sorted(), ["Anna", "Bernd"])
        XCTAssertEqual(summary.trainingDates.count, 2)

        let day5 = Calendar.current.startOfDay(for: training1.startDate)
        let day12 = Calendar.current.startOfDay(for: training2.startDate)
        let anna = try XCTUnwrap(summary.people.first { $0.firstName == "Anna" })
        let bernd = try XCTUnwrap(summary.people.first { $0.firstName == "Bernd" })
        XCTAssertTrue(anna.attended(on: day5))
        XCTAssertFalse(anna.attended(on: day12))
        XCTAssertFalse(bernd.attended(on: day5))
        XCTAssertTrue(bernd.attended(on: day12))
    }

    func testSummarySortsPeopleByDisplayNameAndCapsAtMaxPersonRows() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let team = Team(name: "Torball 1", sport: "Torball")
        context.insert(team)
        for i in 0..<30 {
            let member = Member(firstName: "Person", lastName: String(format: "%02d", i))
            context.insert(member)
            context.insert(TeamMembership(member: member, team: team, role: "player"))
        }
        // A team only counts as "assigned" (and so contributes its roster)
        // once it actually has a training in the period — matching the
        // sport-scoped design, see testSummaryCombinesRosterAcrossTeamsSharingASport.
        _ = makeTraining(context, team: team, day: 5)

        let summary = TrainingsfrequenzlisteCalculator.summary(sport: team.sport, halfYear: .second, year: 2026, in: context)
        XCTAssertEqual(summary.people.count, TrainingsfrequenzlisteCalculator.maxPersonRows)
        XCTAssertEqual(summary.people.map(\.displayName), summary.people.map(\.displayName).sorted())
    }

    // MARK: - Export round-trip (structural integrity, not visual layout)

    func testExportProducesValidReadableZipWithExpectedLayout() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let team = Team(name: "Torball 1", sport: "Torball")
        context.insert(team)
        let member = Member(firstName: "Anna", lastName: "Sportlerin")
        context.insert(member)
        let membership = TeamMembership(member: member, team: team, role: "player")
        context.insert(membership)
        let training = makeTraining(context, team: team, day: 5)
        context.insert(Attendance(event: training, membership: membership, attended: true))

        let summary = TrainingsfrequenzlisteCalculator.summary(sport: team.sport, halfYear: .second, year: 2026, in: context)
        let url = try TrainingsfrequenzlisteExporter.export(summary: summary)
        defer { try? FileManager.default.removeItem(at: url) }

        let archive = try Archive(url: url, accessMode: .read)
        var extractedCount = 0
        for entry in archive {
            var data = Data()
            _ = try archive.extract(entry) { data.append($0) }
            XCTAssertFalse(data.isEmpty, "\(entry.path) extracted empty")
            extractedCount += 1
        }
        XCTAssertGreaterThan(extractedCount, 5)

        var sheetData = Data()
        _ = try archive.extract(try XCTUnwrap(archive["xl/worksheets/sheet1.xml"])) { sheetData.append($0) }
        let sheetXML = try XCTUnwrap(String(data: sheetData, encoding: .utf8))

        // Static template text (title, field labels, "Nr."/"Vorname"/
        // "Nachname" header, "ges. TL", the footnote) now lives in the
        // template's own xl/sharedStrings.xml, untouched by this exporter —
        // only the cells it actually patches become sheet1.xml inline
        // strings. See TrainingsfrequenzlisteExporter's doc comment.
        var sharedStringsData = Data()
        _ = try archive.extract(try XCTUnwrap(archive["xl/sharedStrings.xml"])) { sharedStringsData.append($0) }
        let sharedStringsXML = try XCTUnwrap(String(data: sharedStringsData, encoding: .utf8))

        XCTAssertTrue(sharedStringsXML.contains("T R A I N I N G S F R E Q U E N Z L I S T E"))
        XCTAssertTrue(sharedStringsXML.contains("Verein/LV:"))
        XCTAssertTrue(sharedStringsXML.contains("Sportart:"))
        XCTAssertTrue(sharedStringsXML.contains("Nr."))
        XCTAssertTrue(sharedStringsXML.contains("Vorname"))
        XCTAssertTrue(sharedStringsXML.contains("Nachname"))
        XCTAssertTrue(sharedStringsXML.contains("ges. TL"))
        XCTAssertTrue(sharedStringsXML.contains("bei anwesenden SportlerInnen"))

        // Dynamically patched values: written as sheet1.xml inline strings.
        XCTAssertTrue(sheetXML.contains("<t>Sektion Blindensport (GVSC)</t>"))
        XCTAssertTrue(sheetXML.contains("<t>Torball</t>"))
        XCTAssertTrue(sheetXML.contains("<t>Anna</t>"))
        XCTAssertTrue(sheetXML.contains("<t>Sportlerin</t>"))
        XCTAssertTrue(sheetXML.contains("<t>j</t>"))

        // The training date is a real Excel date serial (numFmtId 164 =
        // "d/m"), not text — see TrainingsfrequenzlisteExporter.excelSerialDate.
        let expectedSerial = TrainingsfrequenzlisteExporter.excelSerialDate(training.startDate)
        XCTAssertTrue(sheetXML.contains("<c r=\"D6\""))
        XCTAssertTrue(sheetXML.contains("<v>\(expectedSerial)</v>"))

        // No per-member total column beyond the original's own field set.
        XCTAssertFalse(sheetXML.contains("Gesamt"))
    }

    /// Covers the "Trainingszeiten:" header fields (H4/L4), added alongside
    /// the real-template patch in TrainingsfrequenzlisteExporter — sourced
    /// from whichever period training is chronologically earliest
    /// (`representativeTraining`, TrainingsfrequenzlisteCalculator.swift), not
    /// hand-entered. Regression coverage for the user-reported bug that these
    /// fields were missing from the export: asserts both times actually
    /// reach the patched sheet XML, not just that `summary` carries them
    /// (the earlier tests only checked the Verein/Sportart/name/date cells,
    /// never these two).
    func testExportPatchesTimesFromRepresentativeTraining() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let team = Team(name: "Torball 1", sport: "Torball")
        context.insert(team)

        var startComponents = DateComponents()
        startComponents.year = 2026; startComponents.month = 7; startComponents.day = 5
        startComponents.hour = 17; startComponents.minute = 30
        let startDate = Calendar.current.date(from: startComponents)!
        let training = Training(title: "Training", sport: "Torball", location: "Sporthalle Puntigam",
                                 startDate: startDate, durationMinutes: 180, teams: [team])
        context.insert(training)

        let summary = TrainingsfrequenzlisteCalculator.summary(sport: "Torball", halfYear: .second, year: 2026, in: context)
        XCTAssertEqual(summary.startTime, training.startDate)
        XCTAssertEqual(summary.endTime, training.endDate)

        let url = try TrainingsfrequenzlisteExporter.export(summary: summary)
        defer { try? FileManager.default.removeItem(at: url) }
        let archive = try Archive(url: url, accessMode: .read)
        var sheetData = Data()
        _ = try archive.extract(try XCTUnwrap(archive["xl/worksheets/sheet1.xml"])) { sheetData.append($0) }
        let sheetXML = try XCTUnwrap(String(data: sheetData, encoding: .utf8))

        // H4/L4 = Uhrzeit von/bis, Excel time-of-day fractions (17:30 -> 0.729166…, 20:30 -> 0.854166…).
        let expectedStart = TrainingsfrequenzlisteExporter.excelTimeFraction(training.startDate)
        let expectedEnd = TrainingsfrequenzlisteExporter.excelTimeFraction(training.endDate)
        XCTAssertTrue(sheetXML.contains("<c r=\"H4\""))
        XCTAssertTrue(sheetXML.contains("<v>\(expectedStart)</v>"))
        XCTAssertTrue(sheetXML.contains("<c r=\"L4\""))
        XCTAssertTrue(sheetXML.contains("<v>\(expectedEnd)</v>"))
    }

    /// Sportstätte (Y3) is patched from the representative Training's
    /// `location` — same source as the Trainingszeiten fields (H4/L4), see
    /// testExportPatchesTimesFromRepresentativeTraining. This reverses an
    /// earlier (2026-08-07) explicit user request to leave Y3 as whatever the
    /// bundled reference template had filled in; the user has since asked for
    /// it to come from the trainings after all, per the 2026-08-18 session.
    func testExportPatchesLocationFromRepresentativeTraining() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let team = Team(name: "Torball 1", sport: "Torball")
        context.insert(team)
        let training = Training(title: "Training", sport: "Torball", location: "Sporthalle Puntigam",
                                 startDate: Calendar.current.date(from: DateComponents(year: 2026, month: 7, day: 5))!,
                                 teams: [team])
        context.insert(training)

        let summary = TrainingsfrequenzlisteCalculator.summary(sport: "Torball", halfYear: .second, year: 2026, in: context)
        XCTAssertEqual(summary.location, "Sporthalle Puntigam")

        let url = try TrainingsfrequenzlisteExporter.export(summary: summary)
        defer { try? FileManager.default.removeItem(at: url) }
        let archive = try Archive(url: url, accessMode: .read)
        var sheetData = Data()
        _ = try archive.extract(try XCTUnwrap(archive["xl/worksheets/sheet1.xml"])) { sheetData.append($0) }
        let sheetXML = try XCTUnwrap(String(data: sheetData, encoding: .utf8))

        // Y3 was rewritten to an inline string carrying the Training's
        // location, no longer the template's own shared string.
        XCTAssertTrue(sheetXML.contains("<t>Sporthalle Puntigam</t>"))
        XCTAssertFalse(sheetXML.contains("<c r=\"Y3\" s=\"39\" t=\"s\"><v>5</v></c>"))
    }

    /// No trainings in the period -> no representative Training -> Y3 gets
    /// cleared rather than left dangling with a stale/previous value, same
    /// pattern as H4/L4 when `startTime`/`endTime` are nil.
    func testExportClearsLocationWhenNoTrainingsInPeriod() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let team = Team(name: "Torball 1", sport: "Torball")
        context.insert(team)

        let summary = TrainingsfrequenzlisteCalculator.summary(sport: "Torball", halfYear: .second, year: 2026, in: context)
        XCTAssertNil(summary.location)

        let url = try TrainingsfrequenzlisteExporter.export(summary: summary)
        defer { try? FileManager.default.removeItem(at: url) }
        let archive = try Archive(url: url, accessMode: .read)
        var sheetData = Data()
        _ = try archive.extract(try XCTUnwrap(archive["xl/worksheets/sheet1.xml"])) { sheetData.append($0) }
        let sheetXML = try XCTUnwrap(String(data: sheetData, encoding: .utf8))
        XCTAssertFalse(sheetXML.contains("<c r=\"Y3\" s=\"39\" t=\"s\"><v>5</v></c>"))
    }

    /// Every other test in this file uses a Member-backed membership; this
    /// covers a User-backed one (a registered app account) too, since the two
    /// take different paths through `TrainingsfrequenzlistePerson.firstName`/
    /// `lastName`'s `membership.user?... ?? membership.member?...` fallback.
    func testExportIncludesNameForUserBackedAttendedMember() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let team = Team(name: "Torball 1", sport: "Torball")
        context.insert(team)
        let user = User(email: "franz@example.com", firstName: "Franz", lastName: "Kager")
        context.insert(user)
        let membership = TeamMembership(user: user, team: team, role: "player")
        context.insert(membership)
        let training = makeTraining(context, team: team, day: 5)
        context.insert(Attendance(event: training, membership: membership, attended: true))

        let summary = TrainingsfrequenzlisteCalculator.summary(sport: team.sport, halfYear: .second, year: 2026, in: context)
        let person = try XCTUnwrap(summary.people.first)
        XCTAssertEqual(person.firstName, "Franz")
        XCTAssertEqual(person.lastName, "Kager")

        let url = try TrainingsfrequenzlisteExporter.export(summary: summary)
        defer { try? FileManager.default.removeItem(at: url) }
        let archive = try Archive(url: url, accessMode: .read)
        var sheetData = Data()
        _ = try archive.extract(try XCTUnwrap(archive["xl/worksheets/sheet1.xml"])) { sheetData.append($0) }
        let sheetXML = try XCTUnwrap(String(data: sheetData, encoding: .utf8))
        XCTAssertTrue(sheetXML.contains("<t>Franz</t>"))
        XCTAssertTrue(sheetXML.contains("<t>Kager</t>"))
    }

    /// Multi-person, multi-date, mixed User/Member-backed roster with mixed
    /// attendance — closer to a real team than the single-person tests
    /// above. Asserts on actual name/attendance values, not just presence of
    /// header labels, which the original round-trip test above did not.
    func testExportWithMultiplePeopleKeepsNamesAlignedWithAttendance() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let team = Team(name: "Torball 1", sport: "Torball")
        context.insert(team)

        let user = User(email: "franz@example.com", firstName: "Franz", lastName: "Kager")
        context.insert(user)
        let userMembership = TeamMembership(user: user, team: team, role: "player")
        context.insert(userMembership)

        let member1 = Member(firstName: "Anna", lastName: "Sportlerin")
        context.insert(member1)
        let memberMembership1 = TeamMembership(member: member1, team: team, role: "player")
        context.insert(memberMembership1)

        let member2 = Member(firstName: "Bernd", lastName: "Helfer")
        context.insert(member2)
        let memberMembership2 = TeamMembership(member: member2, team: team, role: "coach")
        context.insert(memberMembership2)

        let training1 = makeTraining(context, team: team, day: 5)
        let training2 = makeTraining(context, team: team, day: 12)
        // Franz attends both, Anna attends only the first, Bernd never attends.
        context.insert(Attendance(event: training1, membership: userMembership, attended: true))
        context.insert(Attendance(event: training2, membership: userMembership, attended: true))
        context.insert(Attendance(event: training1, membership: memberMembership1, attended: true))

        let summary = TrainingsfrequenzlisteCalculator.summary(sport: team.sport, halfYear: .second, year: 2026, in: context)
        XCTAssertEqual(summary.people.map(\.firstName).sorted(), ["Anna", "Bernd", "Franz"])

        let day5 = Calendar.current.startOfDay(for: training1.startDate)
        let day12 = Calendar.current.startOfDay(for: training2.startDate)
        let anna = try XCTUnwrap(summary.people.first { $0.firstName == "Anna" })
        let bernd = try XCTUnwrap(summary.people.first { $0.firstName == "Bernd" })
        let franz = try XCTUnwrap(summary.people.first { $0.firstName == "Franz" })
        XCTAssertTrue(anna.attended(on: day5))
        XCTAssertFalse(anna.attended(on: day12))
        XCTAssertFalse(bernd.attended(on: day5))
        XCTAssertFalse(bernd.attended(on: day12))
        XCTAssertTrue(franz.attended(on: day5))
        XCTAssertTrue(franz.attended(on: day12))
    }

    func testExportWithNoTrainingsStillProducesValidFile() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let team = Team(name: "Torball 1", sport: "Torball")
        context.insert(team)

        let summary = TrainingsfrequenzlisteCalculator.summary(sport: team.sport, halfYear: .second, year: 2026, in: context)
        XCTAssertTrue(summary.trainingDates.isEmpty)

        let url = try TrainingsfrequenzlisteExporter.export(summary: summary)
        defer { try? FileManager.default.removeItem(at: url) }
        let archive = try Archive(url: url, accessMode: .read)
        XCTAssertNotNil(archive["xl/worksheets/sheet1.xml"])
    }
}
