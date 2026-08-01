import XCTest
import SwiftData
import ZIPFoundation
@testable import BlindensportGraz

final class KostZCalculationTests: XCTestCase {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            User.self, SportEvent.self, Tournament.self, Training.self, Team.self,
            TeamMembership.self, EventParticipation.self, Member.self,
            EventImage.self, Attendance.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func makeTraining(_ context: ModelContext, title: String, day: Int, month: Int = 7, year: Int = 2026) -> Training {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 18
        let date = Calendar.current.date(from: components)!
        let training = Training(title: title, sport: "Torball", location: "Graz", startDate: date)
        context.insert(training)
        return training
    }

    // MARK: - summary

    func testSummaryAggregatesAcrossMultiplePeopleAndEvents() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let team = Team(name: "Torball 1", sport: "Torball")
        context.insert(team)

        let coach = Member(firstName: "Anna", lastName: "Trainer")
        let helper = Member(firstName: "Bernd", lastName: "Helfer")
        context.insert(coach)
        context.insert(helper)
        let coachMembership = TeamMembership(member: coach, team: team, role: "coach")
        let helperMembership = TeamMembership(member: helper, team: team, role: "assistant")
        context.insert(coachMembership)
        context.insert(helperMembership)

        let training1 = makeTraining(context, title: "Montagstraining", day: 5)
        let training2 = makeTraining(context, title: "Turnier Graz", day: 12)
        context.insert(Attendance(event: training1, membership: coachMembership, attended: true, praeAmount: 40))
        context.insert(Attendance(event: training2, membership: coachMembership, attended: true, praeAmount: 60))
        context.insert(Attendance(event: training1, membership: helperMembership, attended: true, praeAmount: 20))

        let allMemberships = try context.fetch(FetchDescriptor<TeamMembership>())
        let summary = KostZCalculator.summary(month: 7, year: 2026, allMemberships: allMemberships, in: context)

        XCTAssertEqual(summary.personAmounts.count, 2)
        XCTAssertEqual(summary.personCount, 2)
        XCTAssertEqual(summary.total, 120)
        XCTAssertEqual(summary.personAmounts.first { $0.person.displayName == "Anna Trainer" }?.amount, 100)
        XCTAssertEqual(summary.personAmounts.first { $0.person.displayName == "Bernd Helfer" }?.amount, 20)
    }

    func testSummaryFiltersToRequestedMonth() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let team = Team(name: "Torball 1", sport: "Torball")
        context.insert(team)
        let coach = Member(firstName: "Anna", lastName: "Trainer")
        context.insert(coach)
        let membership = TeamMembership(member: coach, team: team, role: "coach")
        context.insert(membership)

        let julyTraining = makeTraining(context, title: "Juli-Training", day: 5, month: 7)
        let augustTraining = makeTraining(context, title: "August-Training", day: 5, month: 8)
        context.insert(Attendance(event: julyTraining, membership: membership, attended: true, praeAmount: 40))
        context.insert(Attendance(event: augustTraining, membership: membership, attended: true, praeAmount: 50))

        let allMemberships = try context.fetch(FetchDescriptor<TeamMembership>())
        let summary = KostZCalculator.summary(month: 7, year: 2026, allMemberships: allMemberships, in: context)

        XCTAssertEqual(summary.total, 40)
    }

    func testSummaryIgnoresNonAttendedAndMissingAmount() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let team = Team(name: "Torball 1", sport: "Torball")
        context.insert(team)
        let coach = Member(firstName: "Anna", lastName: "Trainer")
        context.insert(coach)
        let membership = TeamMembership(member: coach, team: team, role: "coach")
        context.insert(membership)

        let notAttended = makeTraining(context, title: "Abgesagt", day: 3)
        let noAmount = makeTraining(context, title: "Ohne Betrag", day: 4)
        context.insert(Attendance(event: notAttended, membership: membership, attended: false, praeAmount: 40))
        context.insert(Attendance(event: noAmount, membership: membership, attended: true, praeAmount: nil))

        let allMemberships = try context.fetch(FetchDescriptor<TeamMembership>())
        let summary = KostZCalculator.summary(month: 7, year: 2026, allMemberships: allMemberships, in: context)

        XCTAssertTrue(summary.personAmounts.isEmpty)
        XCTAssertEqual(summary.total, 0)
    }

    func testSummaryExcludesNonCoachAssistantRoles() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let team = Team(name: "Torball 1", sport: "Torball")
        context.insert(team)
        let player = Member(firstName: "Carla", lastName: "Spielerin")
        context.insert(player)
        let membership = TeamMembership(member: player, team: team, role: "player")
        context.insert(membership)

        let training = makeTraining(context, title: "Training", day: 5)
        context.insert(Attendance(event: training, membership: membership, attended: true, praeAmount: 40))

        let allMemberships = try context.fetch(FetchDescriptor<TeamMembership>())
        let summary = KostZCalculator.summary(month: 7, year: 2026, allMemberships: allMemberships, in: context)

        XCTAssertTrue(summary.personAmounts.isEmpty)
    }

    func testMonthBoundsComputesCorrectDayCount() {
        let bounds = KostZCalculator.monthBounds(month: 7, year: 2026)
        XCTAssertEqual(bounds.dayCount, 31)
        let febBounds = KostZCalculator.monthBounds(month: 2, year: 2026)
        XCTAssertEqual(febBounds.dayCount, 28)
    }

    // MARK: - Export round-trip (structural integrity, not visual layout)

    func testExportProducesValidReadableZipWithExpectedValues() throws {
        let team = Team(name: "Torball 1", sport: "Torball")
        let coach = Member(firstName: "Anna", lastName: "Trainer")
        let membership = TeamMembership(member: coach, team: team, role: "coach")
        let person = PraeEligiblePerson(id: coach.id, displayName: "Anna Trainer", membershipIDs: [membership.id], member: coach)
        let summary = KostZMonthSummary(
            month: 7, year: 2026,
            personAmounts: [KostZPersonAmount(person: person, amount: 150)]
        )

        let url = try KostZExporter.export(summary: summary)
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

        XCTAssertTrue(sheetXML.contains("Trainer:innen- und Helfer:innenhonorare Juli 2026"))
        XCTAssertTrue(sheetXML.contains("01.07.2026"))
        XCTAssertTrue(sheetXML.contains("31.07.2026"))
        XCTAssertTrue(sheetXML.contains("<c r=\"I5\"><v>31.0</v></c>") || sheetXML.contains("<c r=\"I5\"><v>31</v></c>") || sheetXML.contains(">31<"))
        XCTAssertTrue(sheetXML.contains("<c r=\"E7\""))
        XCTAssertTrue(sheetXML.contains("<c r=\"I15\""))
        XCTAssertTrue(sheetXML.contains("150"))
        // The SUM formula total row must survive untouched — it recalculates on open.
        XCTAssertTrue(sheetXML.contains("SUM(I10:I25)"))
        // An untouched category label (this app has no data for it) must still be present.
        XCTAssertTrue(sheetXML.contains("<c r=\"F10\""))
    }

    func testExportZeroTotalLeavesAmountCellBlank() throws {
        let summary = KostZMonthSummary(month: 7, year: 2026, personAmounts: [])

        let url = try KostZExporter.export(summary: summary)
        defer { try? FileManager.default.removeItem(at: url) }

        let archive = try Archive(url: url, accessMode: .read)
        var sheetData = Data()
        _ = try archive.extract(try XCTUnwrap(archive["xl/worksheets/sheet1.xml"])) { sheetData.append($0) }
        let sheetXML = try XCTUnwrap(String(data: sheetData, encoding: .utf8))

        // I15 should remain a self-closing blank cell (no <v>) when total is 0.
        XCTAssertTrue(sheetXML.contains("<c r=\"I15\""))
        XCTAssertFalse(sheetXML.contains("<c r=\"I15\"") && sheetXML.range(of: "<c r=\"I15\"[^>]*><v>", options: .regularExpression) != nil)
    }
}
