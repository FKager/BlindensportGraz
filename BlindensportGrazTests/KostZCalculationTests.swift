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

    private func makeTournament(_ context: ModelContext, title: String, day: Int, month: Int = 7, year: Int = 2026) -> Tournament {
        var startComponents = DateComponents()
        startComponents.year = year
        startComponents.month = month
        startComponents.day = day
        startComponents.hour = 9
        let start = Calendar.current.date(from: startComponents)!
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
        let tournament = Tournament(title: title, sport: "Torball", location: "Graz", startDate: start, endDate: end)
        context.insert(tournament)
        return tournament
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
        let coachMembership = TeamMembership(member: coach, team: team, role: .coach)
        let helperMembership = TeamMembership(member: helper, team: team, role: .assistant)
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
        let membership = TeamMembership(member: coach, team: team, role: .coach)
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
        let membership = TeamMembership(member: coach, team: team, role: .coach)
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
        let membership = TeamMembership(member: player, team: team, role: .player)
        context.insert(membership)

        let training = makeTraining(context, title: "Training", day: 5)
        context.insert(Attendance(event: training, membership: membership, attended: true, praeAmount: 40))

        let allMemberships = try context.fetch(FetchDescriptor<TeamMembership>())
        let summary = KostZCalculator.summary(month: 7, year: 2026, allMemberships: allMemberships, in: context)

        XCTAssertTrue(summary.personAmounts.isEmpty)
    }

    func testSummaryExcludesTournamentAttendances() throws {
        // Tournaments file their own KostZ (see summary(for tournament:))
        // instead — the monthly summary must only ever count Trainings, or
        // a tournament's honoraria would be double-counted.
        let container = try makeContainer()
        let context = ModelContext(container)
        let team = Team(name: "Torball 1", sport: "Torball")
        context.insert(team)
        let coach = Member(firstName: "Anna", lastName: "Trainer")
        context.insert(coach)
        let membership = TeamMembership(member: coach, team: team, role: .coach)
        context.insert(membership)

        let training = makeTraining(context, title: "Montagstraining", day: 5)
        let tournament = makeTournament(context, title: "Landesmeisterschaft", day: 12)
        context.insert(Attendance(event: training, membership: membership, attended: true, praeAmount: 40))
        context.insert(Attendance(event: tournament, membership: membership, attended: true, praeAmount: 60))

        let allMemberships = try context.fetch(FetchDescriptor<TeamMembership>())
        let summary = KostZCalculator.summary(month: 7, year: 2026, allMemberships: allMemberships, in: context)

        XCTAssertEqual(summary.total, 40)
    }

    // MARK: - summary(for tournament:)

    func testTournamentSummaryAggregatesOnlyThatTournamentsAttendances() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let team = Team(name: "Torball 1", sport: "Torball")
        context.insert(team)
        let coach = Member(firstName: "Anna", lastName: "Trainer")
        let helper = Member(firstName: "Bernd", lastName: "Helfer")
        context.insert(coach)
        context.insert(helper)
        let coachMembership = TeamMembership(member: coach, team: team, role: .coach)
        let helperMembership = TeamMembership(member: helper, team: team, role: .assistant)
        context.insert(coachMembership)
        context.insert(helperMembership)

        let tournament = makeTournament(context, title: "Landesmeisterschaft", day: 12)
        let otherTournament = makeTournament(context, title: "Anderes Turnier", day: 20)
        let training = makeTraining(context, title: "Montagstraining", day: 5)
        context.insert(Attendance(event: tournament, membership: coachMembership, attended: true, praeAmount: 60))
        context.insert(Attendance(event: tournament, membership: helperMembership, attended: true, praeAmount: 30))
        context.insert(Attendance(event: otherTournament, membership: coachMembership, attended: true, praeAmount: 999))
        context.insert(Attendance(event: training, membership: coachMembership, attended: true, praeAmount: 999))

        let allMemberships = try context.fetch(FetchDescriptor<TeamMembership>())
        let summary = KostZCalculator.summary(for: tournament, allMemberships: allMemberships)

        XCTAssertEqual(summary.personCount, 2)
        XCTAssertEqual(summary.total, 90)
    }

    func testTournamentSummaryIgnoresNonAttendedAndMissingAmount() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let team = Team(name: "Torball 1", sport: "Torball")
        context.insert(team)
        let coach = Member(firstName: "Anna", lastName: "Trainer")
        context.insert(coach)
        let membership = TeamMembership(member: coach, team: team, role: .coach)
        context.insert(membership)

        let tournament = makeTournament(context, title: "Landesmeisterschaft", day: 12)
        context.insert(Attendance(event: tournament, membership: membership, attended: false, praeAmount: 40))

        let allMemberships = try context.fetch(FetchDescriptor<TeamMembership>())
        let summary = KostZCalculator.summary(for: tournament, allMemberships: allMemberships)

        XCTAssertTrue(summary.personAmounts.isEmpty)
        XCTAssertEqual(summary.total, 0)
    }

    // MARK: - trainingDates

    func testTrainingDatesCoversEveryTrainingThatMonthRegardlessOfPraeAmount() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let team = Team(name: "Torball 1", sport: "Torball")
        context.insert(team)
        let coach = Member(firstName: "Anna", lastName: "Trainer")
        context.insert(coach)
        let membership = TeamMembership(member: coach, team: team, role: .coach)
        context.insert(membership)

        // Three trainings in July, one of them with no PRAE amount at all —
        // trainingDates must still include it (it's a count of trainings,
        // not a count of PRAE-amounted attendances).
        let t1 = makeTraining(context, title: "Training 1", day: 3)
        let t2 = makeTraining(context, title: "Training 2", day: 10, month: 7)
        let t3 = makeTraining(context, title: "Training 3", day: 24)
        _ = makeTraining(context, title: "August-Training", day: 2, month: 8) // different month, excluded
        context.insert(Attendance(event: t1, membership: membership, attended: true, praeAmount: 40))
        context.insert(Attendance(event: t3, membership: membership, attended: true, praeAmount: 40))
        // t2 deliberately has no Attendance at all.

        let allMemberships = try context.fetch(FetchDescriptor<TeamMembership>())
        let summary = KostZCalculator.summary(month: 7, year: 2026, allMemberships: allMemberships, in: context)

        XCTAssertEqual(summary.trainingDates.count, 3)
        XCTAssertEqual(summary.trainingDates.first, t1.startDate)
        XCTAssertEqual(summary.trainingDates.last, t3.startDate)
        _ = t2
    }

    func testMonthBoundsComputesCorrectDayCount() {
        let bounds = KostZCalculator.monthBounds(month: 7, year: 2026)
        XCTAssertEqual(bounds.dayCount, 31)
        let febBounds = KostZCalculator.monthBounds(month: 2, year: 2026)
        XCTAssertEqual(febBounds.dayCount, 28)
    }

    // MARK: - Export round-trip (structural integrity, not visual layout)

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        return Calendar.current.date(from: components)!
    }

    func testExportProducesValidReadableZipWithExpectedValues() throws {
        let team = Team(name: "Torball 1", sport: "Torball")
        let coach = Member(firstName: "Anna", lastName: "Trainer")
        let membership = TeamMembership(member: coach, team: team, role: .coach)
        let person = PraeEligiblePerson(id: coach.id, displayName: "Anna Trainer", membershipIDs: [membership.id], member: coach)
        // 4 trainings that month, on the 3rd/10th/17th/24th — ZEITRAUM/TAGE
        // must come from these, not the calendar month's 1st/31st/31 days.
        let summary = KostZMonthSummary(
            month: 7, year: 2026,
            personAmounts: [KostZPersonAmount(person: person, amount: 150)],
            trainingDates: [date(2026, 7, 3), date(2026, 7, 10), date(2026, 7, 17), date(2026, 7, 24)]
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
        XCTAssertTrue(sheetXML.contains("Graz")) // ORT (H3)
        XCTAssertTrue(sheetXML.contains("03.07.2026")) // first training, not the 1st
        XCTAssertTrue(sheetXML.contains("24.07.2026")) // last training, not the 31st
        XCTAssertFalse(sheetXML.contains("01.07.2026"))
        XCTAssertFalse(sheetXML.contains("31.07.2026"))
        XCTAssertTrue(sheetXML.contains("<c r=\"I5\"><v>4.0</v></c>") || sheetXML.contains("<c r=\"I5\"><v>4</v></c>") || sheetXML.contains(">4<"))
        XCTAssertTrue(sheetXML.contains("<c r=\"E7\""))
        XCTAssertTrue(sheetXML.contains("<c r=\"I15\""))
        XCTAssertTrue(sheetXML.contains("150"))
        // The SUM formula total row must survive untouched — it recalculates on open.
        XCTAssertTrue(sheetXML.contains("SUM(I10:I25)"))
        // An untouched category label (this app has no data for it) must still be present.
        XCTAssertTrue(sheetXML.contains("<c r=\"F10\""))
    }

    func testExportWithNoTrainingsThatMonthFallsBackToCalendarBounds() throws {
        // No training held at all in the requested month (e.g. summer
        // break) — ZEITRAUM falls back to the plain calendar month and
        // TAGE is 0, rather than crashing or leaving the fields blank.
        let summary = KostZMonthSummary(month: 7, year: 2026, personAmounts: [], trainingDates: [])

        let url = try KostZExporter.export(summary: summary)
        defer { try? FileManager.default.removeItem(at: url) }

        let archive = try Archive(url: url, accessMode: .read)
        var sheetData = Data()
        _ = try archive.extract(try XCTUnwrap(archive["xl/worksheets/sheet1.xml"])) { sheetData.append($0) }
        let sheetXML = try XCTUnwrap(String(data: sheetData, encoding: .utf8))

        XCTAssertTrue(sheetXML.contains("01.07.2026"))
        XCTAssertTrue(sheetXML.contains("31.07.2026"))
        XCTAssertTrue(sheetXML.contains("<c r=\"I5\"><v>0.0</v></c>") || sheetXML.contains("<c r=\"I5\"><v>0</v></c>") || sheetXML.contains(">0<"))
    }

    func testTournamentExportProducesValidReadableZipWithExpectedValues() throws {
        let team = Team(name: "Torball 1", sport: "Torball")
        let coach = Member(firstName: "Anna", lastName: "Trainer")
        let membership = TeamMembership(member: coach, team: team, role: .coach)
        let person = PraeEligiblePerson(id: coach.id, displayName: "Anna Trainer", membershipIDs: [membership.id], member: coach)
        var startComponents = DateComponents()
        startComponents.year = 2026
        startComponents.month = 7
        startComponents.day = 10
        let start = Calendar.current.date(from: startComponents)!
        let end = Calendar.current.date(byAdding: .day, value: 2, to: start)! // 3-day tournament
        // Deliberately a different city than the Training export's
        // hardcoded "Graz" (and a different venue name than city, to prove
        // ORT reads `city` specifically, not `location`).
        let tournament = Tournament(title: "Landesmeisterschaft", sport: "Torball", location: "Stadthalle",
                                     city: "Wien", startDate: start, endDate: end)
        let summary = KostZTournamentSummary(
            tournament: tournament,
            personAmounts: [KostZPersonAmount(person: person, amount: 90)]
        )

        let url = try KostZExporter.export(summary: summary)
        defer { try? FileManager.default.removeItem(at: url) }

        let archive = try Archive(url: url, accessMode: .read)
        var sheetData = Data()
        _ = try archive.extract(try XCTUnwrap(archive["xl/worksheets/sheet1.xml"])) { sheetData.append($0) }
        let sheetXML = try XCTUnwrap(String(data: sheetData, encoding: .utf8))

        XCTAssertTrue(sheetXML.contains("Trainer:innen- und Helfer:innenhonorare Landesmeisterschaft"))
        XCTAssertTrue(sheetXML.contains("Wien")) // ORT (H3), from tournament.city
        XCTAssertFalse(sheetXML.contains("Stadthalle")) // location is NOT what ORT reads
        XCTAssertTrue(sheetXML.contains("10.07.2026"))
        XCTAssertTrue(sheetXML.contains("12.07.2026"))
        XCTAssertTrue(sheetXML.contains("<c r=\"I5\"><v>3.0</v></c>") || sheetXML.contains("<c r=\"I5\"><v>3</v></c>") || sheetXML.contains(">3<"))
        XCTAssertTrue(sheetXML.contains("90"))
    }

    func testTournamentExportLeavesOrtBlankWhenCityIsEmpty() throws {
        let team = Team(name: "Torball 1", sport: "Torball")
        let coach = Member(firstName: "Anna", lastName: "Trainer")
        let membership = TeamMembership(member: coach, team: team, role: .coach)
        let person = PraeEligiblePerson(id: coach.id, displayName: "Anna Trainer", membershipIDs: [membership.id], member: coach)
        // location IS set here — must not leak into ORT as a fallback.
        let tournament = Tournament(title: "Landesmeisterschaft", sport: "Torball", location: "Stadthalle",
                                     startDate: .now, endDate: .now)
        let summary = KostZTournamentSummary(
            tournament: tournament,
            personAmounts: [KostZPersonAmount(person: person, amount: 90)]
        )

        let url = try KostZExporter.export(summary: summary)
        defer { try? FileManager.default.removeItem(at: url) }

        let archive = try Archive(url: url, accessMode: .read)
        var sheetData = Data()
        _ = try archive.extract(try XCTUnwrap(archive["xl/worksheets/sheet1.xml"])) { sheetData.append($0) }
        let sheetXML = try XCTUnwrap(String(data: sheetData, encoding: .utf8))

        // H3 should remain a blank cell (no inline string content) when the
        // tournament has no location set.
        XCTAssertFalse(sheetXML.range(of: "<c r=\"H3\"[^>]*><is>", options: .regularExpression) != nil)
    }

    func testExportZeroTotalLeavesAmountCellBlank() throws {
        let summary = KostZMonthSummary(month: 7, year: 2026, personAmounts: [], trainingDates: [date(2026, 7, 5)])

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
