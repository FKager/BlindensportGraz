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

        let summary = TrainingsfrequenzlisteCalculator.summary(team: team, month: 7, year: 2026, in: context)

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

        let summary = TrainingsfrequenzlisteCalculator.summary(team: team, month: 7, year: 2026, in: context)
        let person = try XCTUnwrap(summary.people.first)
        XCTAssertFalse(person.attended(on: Calendar.current.startOfDay(for: training.startDate)))
    }

    func testSummaryFiltersToRequestedTeamMonthAndYear() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let team = Team(name: "Torball 1", sport: "Torball")
        let otherTeam = Team(name: "Torball 2", sport: "Torball")
        context.insert(team)
        context.insert(otherTeam)

        _ = makeTraining(context, team: team, day: 5, month: 7, year: 2026)
        _ = makeTraining(context, team: team, day: 5, month: 8, year: 2026) // wrong month
        _ = makeTraining(context, team: otherTeam, day: 6, month: 7, year: 2026) // wrong team

        let summary = TrainingsfrequenzlisteCalculator.summary(team: team, month: 7, year: 2026, in: context)
        XCTAssertEqual(summary.trainingDates.count, 1)
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

        let summary = TrainingsfrequenzlisteCalculator.summary(team: team, month: 7, year: 2026, in: context)
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

        let summary = TrainingsfrequenzlisteCalculator.summary(team: team, month: 7, year: 2026, in: context)
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

        XCTAssertTrue(sheetXML.contains("T R A I N I N G S F R E Q U E N Z L I S T E"))
        XCTAssertTrue(sheetXML.contains("Verein/LV:"))
        XCTAssertTrue(sheetXML.contains("Grazer VSC"))
        XCTAssertTrue(sheetXML.contains("Sportart:"))
        XCTAssertTrue(sheetXML.contains("Torball"))
        XCTAssertTrue(sheetXML.contains("Nr."))
        XCTAssertTrue(sheetXML.contains("Vorname"))
        XCTAssertTrue(sheetXML.contains("Nachname"))
        XCTAssertTrue(sheetXML.contains("05.07."))
        XCTAssertTrue(sheetXML.contains(">j<") || sheetXML.contains("<t>j</t>"))
        XCTAssertTrue(sheetXML.contains("ges. TL"))
        XCTAssertTrue(sheetXML.contains("bei anwesenden SportlerInnen"))
        // No per-member total column beyond the original's own field set.
        XCTAssertFalse(sheetXML.contains("Gesamt"))
    }

    func testExportWithNoTrainingsStillProducesValidFile() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let team = Team(name: "Torball 1", sport: "Torball")
        context.insert(team)

        let summary = TrainingsfrequenzlisteCalculator.summary(team: team, month: 7, year: 2026, in: context)
        XCTAssertTrue(summary.trainingDates.isEmpty)

        let url = try TrainingsfrequenzlisteExporter.export(summary: summary)
        defer { try? FileManager.default.removeItem(at: url) }
        let archive = try Archive(url: url, accessMode: .read)
        XCTAssertNotNil(archive["xl/worksheets/sheet1.xml"])
    }
}
