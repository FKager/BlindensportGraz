import XCTest
import SwiftData
import ZIPFoundation
@testable import BlindensportGraz

final class PraeCalculationTests: XCTestCase {

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

    // MARK: - eligiblePeople

    func testEligiblePeopleIncludesOnlyCoachAndAssistantRoles() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let team = Team(name: "Torball 1", sport: "Torball")
        context.insert(team)

        let coach = Member(firstName: "Anna", lastName: "Trainer")
        let helper = Member(firstName: "Bernd", lastName: "Helfer")
        let player = Member(firstName: "Carla", lastName: "Spielerin")
        [coach, helper, player].forEach(context.insert)

        context.insert(TeamMembership(member: coach, team: team, role: "coach"))
        context.insert(TeamMembership(member: helper, team: team, role: "assistant"))
        context.insert(TeamMembership(member: player, team: team, role: "player"))

        let allMemberships = try context.fetch(FetchDescriptor<TeamMembership>())
        let eligible = PraeCalculator.eligiblePeople(from: allMemberships)

        XCTAssertEqual(eligible.map(\.displayName).sorted(), ["Anna Trainer", "Bernd Helfer"])
    }

    func testEligiblePeopleDedupesSamePersonAcrossTeams() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let teamA = Team(name: "Torball 1", sport: "Torball")
        let teamB = Team(name: "Torball 2", sport: "Torball")
        context.insert(teamA)
        context.insert(teamB)

        let coach = Member(firstName: "Anna", lastName: "Trainer")
        context.insert(coach)
        context.insert(TeamMembership(member: coach, team: teamA, role: "coach"))
        context.insert(TeamMembership(member: coach, team: teamB, role: "coach"))

        let allMemberships = try context.fetch(FetchDescriptor<TeamMembership>())
        let eligible = PraeCalculator.eligiblePeople(from: allMemberships)

        XCTAssertEqual(eligible.count, 1)
        XCTAssertEqual(eligible.first?.membershipIDs.count, 2)
    }

    // MARK: - summary

    func testSummaryGroupsByDayAndFiltersToMonth() throws {
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

        let julyAttendance = Attendance(event: julyTraining, membership: membership, attended: true, praeAmount: 40)
        let augustAttendance = Attendance(event: augustTraining, membership: membership, attended: true, praeAmount: 50)
        context.insert(julyAttendance)
        context.insert(augustAttendance)

        let allMemberships = try context.fetch(FetchDescriptor<TeamMembership>())
        let person = PraeCalculator.eligiblePeople(from: allMemberships).first!
        let summary = PraeCalculator.summary(for: person, month: 7, year: 2026, in: context)

        XCTAssertEqual(summary.entries.count, 1)
        XCTAssertEqual(summary.entries.first?.day, 5)
        XCTAssertEqual(summary.entries.first?.amount, 40)
        XCTAssertEqual(summary.total, 40)
    }

    func testSummarySumsMultipleSessionsOnSameDay() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let team = Team(name: "Torball 1", sport: "Torball")
        context.insert(team)
        let coach = Member(firstName: "Anna", lastName: "Trainer")
        context.insert(coach)
        let membership = TeamMembership(member: coach, team: team, role: "coach")
        context.insert(membership)

        let morning = makeTraining(context, title: "Vormittag", day: 10)
        let evening = makeTraining(context, title: "Abend", day: 10)
        context.insert(Attendance(event: morning, membership: membership, attended: true, praeAmount: 30))
        context.insert(Attendance(event: evening, membership: membership, attended: true, praeAmount: 100))

        let person = PraeCalculator.eligiblePeople(from: try context.fetch(FetchDescriptor<TeamMembership>())).first!
        let summary = PraeCalculator.summary(for: person, month: 7, year: 2026, in: context)

        XCTAssertEqual(summary.entries.count, 1)
        XCTAssertEqual(summary.entries.first?.amount, 130)
        XCTAssertTrue(summary.daysExceedingDailyCap.contains(10)) // 130 > 120 daily cap
    }

    func testSummaryFlagsMonthlyCapExceeded() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let team = Team(name: "Torball 1", sport: "Torball")
        context.insert(team)
        let coach = Member(firstName: "Anna", lastName: "Trainer")
        context.insert(coach)
        let membership = TeamMembership(member: coach, team: team, role: "coach")
        context.insert(membership)

        for day in [1, 5, 10, 15, 20, 25] {
            let training = makeTraining(context, title: "Training \(day)", day: day)
            context.insert(Attendance(event: training, membership: membership, attended: true, praeAmount: 120))
        }

        let person = PraeCalculator.eligiblePeople(from: try context.fetch(FetchDescriptor<TeamMembership>())).first!
        let summary = PraeCalculator.summary(for: person, month: 7, year: 2026, in: context)

        XCTAssertEqual(summary.total, 720)
        XCTAssertFalse(summary.exceedsMonthlyCap) // exactly at the cap, not over

        // One more day pushes it over.
        let extra = makeTraining(context, title: "Extra", day: 28)
        context.insert(Attendance(event: extra, membership: membership, attended: true, praeAmount: 10))
        let summary2 = PraeCalculator.summary(for: person, month: 7, year: 2026, in: context)
        XCTAssertTrue(summary2.exceedsMonthlyCap)
    }

    func testSummaryIgnoresAttendanceWithoutPraeAmount() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let team = Team(name: "Torball 1", sport: "Torball")
        context.insert(team)
        let coach = Member(firstName: "Anna", lastName: "Trainer")
        context.insert(coach)
        let membership = TeamMembership(member: coach, team: team, role: "coach")
        context.insert(membership)

        let training = makeTraining(context, title: "Ohne Betrag", day: 3)
        context.insert(Attendance(event: training, membership: membership, attended: true, praeAmount: nil))

        let person = PraeCalculator.eligiblePeople(from: try context.fetch(FetchDescriptor<TeamMembership>())).first!
        let summary = PraeCalculator.summary(for: person, month: 7, year: 2026, in: context)

        XCTAssertTrue(summary.entries.isEmpty)
    }

    func testSummaryExcludesTournamentAttendances() throws {
        // Tournaments file their own PRAE (see summary(for:tournament:))
        // instead — the monthly summary must only ever count Trainings, or
        // a tournament's deployment days would be double-counted.
        let container = try makeContainer()
        let context = ModelContext(container)
        let team = Team(name: "Torball 1", sport: "Torball")
        context.insert(team)
        let coach = Member(firstName: "Anna", lastName: "Trainer")
        context.insert(coach)
        let membership = TeamMembership(member: coach, team: team, role: "coach")
        context.insert(membership)

        let training = makeTraining(context, title: "Montagstraining", day: 5)
        let tournament = makeTournament(context, title: "Landesmeisterschaft", day: 12)
        context.insert(Attendance(event: training, membership: membership, attended: true, praeAmount: 40))
        context.insert(Attendance(event: tournament, membership: membership, attended: true, praeAmount: 60))

        let person = PraeCalculator.eligiblePeople(from: try context.fetch(FetchDescriptor<TeamMembership>())).first!
        let summary = PraeCalculator.summary(for: person, month: 7, year: 2026, in: context)

        XCTAssertEqual(summary.total, 40)
        XCTAssertEqual(summary.entries.count, 1)
    }

    // MARK: - summary(for:tournament:)

    func testTournamentSummaryGroupsByDayForJustThatTournament() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let team = Team(name: "Torball 1", sport: "Torball")
        context.insert(team)
        let coach = Member(firstName: "Anna", lastName: "Trainer")
        context.insert(coach)
        let membership = TeamMembership(member: coach, team: team, role: "coach")
        context.insert(membership)

        let tournament = makeTournament(context, title: "Landesmeisterschaft", day: 12)
        let otherTournament = makeTournament(context, title: "Anderes Turnier", day: 20)
        let training = makeTraining(context, title: "Montagstraining", day: 5)
        context.insert(Attendance(event: tournament, membership: membership, attended: true, praeAmount: 60))
        context.insert(Attendance(event: otherTournament, membership: membership, attended: true, praeAmount: 999))
        context.insert(Attendance(event: training, membership: membership, attended: true, praeAmount: 999))

        let person = PraeCalculator.eligiblePeople(from: try context.fetch(FetchDescriptor<TeamMembership>())).first!
        let summary = PraeCalculator.summary(for: person, tournament: tournament)

        XCTAssertEqual(summary.entries.count, 1)
        XCTAssertEqual(summary.entries.first?.day, 12)
        XCTAssertEqual(summary.total, 60)
    }

    func testTournamentSummaryIgnoresAttendanceWithoutPraeAmount() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let team = Team(name: "Torball 1", sport: "Torball")
        context.insert(team)
        let coach = Member(firstName: "Anna", lastName: "Trainer")
        context.insert(coach)
        let membership = TeamMembership(member: coach, team: team, role: "coach")
        context.insert(membership)

        let tournament = makeTournament(context, title: "Landesmeisterschaft", day: 12)
        context.insert(Attendance(event: tournament, membership: membership, attended: true, praeAmount: nil))

        let person = PraeCalculator.eligiblePeople(from: try context.fetch(FetchDescriptor<TeamMembership>())).first!
        let summary = PraeCalculator.summary(for: person, tournament: tournament)

        XCTAssertTrue(summary.entries.isEmpty)
    }

    // MARK: - Export round-trips (structural integrity, not visual layout)

    func testExportDarstellungProducesValidReadableZip() throws {
        let team = Team(name: "Torball 1", sport: "Torball")
        let coach = Member(firstName: "Anna", lastName: "Trainer")
        let membership = TeamMembership(member: coach, team: team, role: "coach")
        let person = PraeEligiblePerson(id: coach.id, displayName: "Anna Trainer", membershipIDs: [membership.id], member: coach)
        let summary = PraeMonthSummary(
            person: person, month: 7, year: 2026,
            entries: [
                PraeDayEntry(day: 5, amount: 40, purpose: "Torball-Training"),
                PraeDayEntry(day: 12, amount: 60, purpose: "Turnier & Wörthersee-Cup")
            ]
        )

        let url = try PraeExporter.exportDarstellung(summary: summary)
        defer { try? FileManager.default.removeItem(at: url) }

        let archive = try Archive(url: url, accessMode: .read)
        var extractedPaths: Set<String> = []
        for entry in archive {
            var data = Data()
            _ = try archive.extract(entry) { data.append($0) }
            extractedPaths.insert(entry.path)
            XCTAssertFalse(data.isEmpty, "\(entry.path) extracted empty")
        }
        XCTAssertTrue(extractedPaths.contains("xl/worksheets/sheet1.xml"))
        XCTAssertTrue(extractedPaths.contains("xl/workbook.xml"))
        XCTAssertTrue(extractedPaths.contains("[Content_Types].xml"))

        var sheetData = Data()
        _ = try archive.extract(try XCTUnwrap(archive["xl/worksheets/sheet1.xml"])) { sheetData.append($0) }
        let sheetXML = try XCTUnwrap(String(data: sheetData, encoding: .utf8))
        XCTAssertTrue(sheetXML.contains("Anna Trainer"))
        XCTAssertTrue(sheetXML.contains("Torball-Training"))
        // "&" in a purpose must come back XML-escaped, not raw (would corrupt the XML).
        XCTAssertTrue(sheetXML.contains("Wörthersee-Cup"))
        XCTAssertTrue(sheetXML.contains("&amp;"))
        XCTAssertFalse(sheetXML.contains("Turnier & Wörthersee")) // raw unescaped "&" must not appear
    }

    func testExportDarstellungForTournamentUsesTournamentTitleAsPeriod() throws {
        let team = Team(name: "Torball 1", sport: "Torball")
        let coach = Member(firstName: "Anna", lastName: "Trainer")
        let membership = TeamMembership(member: coach, team: team, role: "coach")
        let person = PraeEligiblePerson(id: coach.id, displayName: "Anna Trainer", membershipIDs: [membership.id], member: coach)
        let tournament = Tournament(title: "Landesmeisterschaft", sport: "Torball", location: "Graz",
                                     startDate: .now, endDate: .now)
        let summary = PraeTournamentSummary(
            person: person, tournament: tournament,
            entries: [PraeDayEntry(day: 12, amount: 60, purpose: "Landesmeisterschaft")]
        )

        let url = try PraeExporter.exportDarstellung(summary: summary)
        defer { try? FileManager.default.removeItem(at: url) }

        let archive = try Archive(url: url, accessMode: .read)
        var sheetData = Data()
        _ = try archive.extract(try XCTUnwrap(archive["xl/worksheets/sheet1.xml"])) { sheetData.append($0) }
        let sheetXML = try XCTUnwrap(String(data: sheetData, encoding: .utf8))

        XCTAssertTrue(sheetXML.contains("Anna Trainer"))
        XCTAssertTrue(sheetXML.contains("Turnier:"))
        XCTAssertTrue(sheetXML.contains("Landesmeisterschaft"))
        XCTAssertTrue(sheetXML.contains("60"))
    }

    func testExportMainFormPatchesNameAndAddressOnly() throws {
        let team = Team(name: "Torball 1", sport: "Torball")
        let coach = Member(firstName: "Anna", lastName: "Trainer", street: "Hauptstraße 1", zip: "8010", city: "Graz")
        let membership = TeamMembership(member: coach, team: team, role: "coach")
        let person = PraeEligiblePerson(id: coach.id, displayName: "Trainer Anna", membershipIDs: [membership.id], member: coach)

        let url = try PraeExporter.exportMainForm(person: person)
        defer { try? FileManager.default.removeItem(at: url) }

        let archive = try Archive(url: url, accessMode: .read)
        var sheetData = Data()
        _ = try archive.extract(try XCTUnwrap(archive["xl/worksheets/sheet1.xml"])) { sheetData.append($0) }
        let sheetXML = try XCTUnwrap(String(data: sheetData, encoding: .utf8))

        XCTAssertTrue(sheetXML.contains("Trainer Anna"))
        XCTAssertTrue(sheetXML.contains("Hauptstraße 1, 8010 Graz"))

        // Every other entry from the template must still be present/readable —
        // confirms the patch didn't corrupt the archive or drop unrelated parts.
        var extractedCount = 0
        for entry in archive {
            var data = Data()
            _ = try archive.extract(entry) { data.append($0) }
            extractedCount += 1
        }
        XCTAssertGreaterThan(extractedCount, 5)
    }
}
