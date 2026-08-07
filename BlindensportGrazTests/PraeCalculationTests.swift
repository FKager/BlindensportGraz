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

    func testExportMainFormPatchesPersonalDataFromMember() throws {
        let team = Team(name: "Torball 1", sport: "Torball")
        var birthComponents = DateComponents()
        birthComponents.year = 1990
        birthComponents.month = 3
        birthComponents.day = 21
        let birthDate = Calendar.current.date(from: birthComponents)!
        let coach = Member(firstName: "Anna", lastName: "Trainer", street: "Hauptstraße 1", zip: "8010", city: "Graz",
                            birthDate: birthDate, svnr: "1234210390", iban: "AT611904300234573201")
        let membership = TeamMembership(member: coach, team: team, role: "coach")
        let person = PraeEligiblePerson(id: coach.id, displayName: "Trainer Anna", membershipIDs: [membership.id], member: coach)
        let summary = PraeMonthSummary(person: person, month: 7, year: 2026, entries: [])

        let url = try PraeExporter.exportMainForm(summary: summary)
        defer { try? FileManager.default.removeItem(at: url) }

        let archive = try Archive(url: url, accessMode: .read)
        var sheetData = Data()
        _ = try archive.extract(try XCTUnwrap(archive["xl/worksheets/sheet1.xml"])) { sheetData.append($0) }
        let sheetXML = try XCTUnwrap(String(data: sheetData, encoding: .utf8))

        XCTAssertTrue(sheetXML.contains("Trainer Anna"))
        XCTAssertTrue(sheetXML.contains("Hauptstraße 1, 8010 Graz"))
        XCTAssertTrue(sheetXML.contains("1234210390")) // SVNR (D5)
        XCTAssertTrue(sheetXML.contains("21.03.1990")) // Geburtsdatum (L5)
        XCTAssertTrue(sheetXML.contains("AT611904300234573201")) // IBAN (D33)

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

    /// Regression coverage for the user-reported bug that PRAE amounts never
    /// reached the main form's day grid and "im Monat:"/"Jahr:" were never
    /// filled in. Covers three grid positions spanning all four grid rows
    /// (day 1 -> row 12's first slot, day 15 -> row 13's mid slot, day 31 ->
    /// row 15's lone slot) to catch an off-by-row or off-by-column mistake
    /// that a single day wouldn't. Cell refs (C12/O13/C15) match
    /// PraeExporter.dayGridAmountRef's doc comment, derived from the real
    /// template's own `<mergeCells>`.
    func testExportMainFormPatchesMonthYearAndDayGridAmounts() throws {
        let team = Team(name: "Torball 1", sport: "Torball")
        let coach = Member(firstName: "Anna", lastName: "Trainer")
        let membership = TeamMembership(member: coach, team: team, role: "coach")
        let person = PraeEligiblePerson(id: coach.id, displayName: "Anna Trainer", membershipIDs: [membership.id], member: coach)
        let summary = PraeMonthSummary(person: person, month: 7, year: 2026, entries: [
            PraeDayEntry(day: 1, amount: 30, purpose: "Training"),
            PraeDayEntry(day: 15, amount: 45, purpose: "Training"),
            PraeDayEntry(day: 31, amount: 60, purpose: "Training"),
        ])

        let url = try PraeExporter.exportMainForm(summary: summary)
        defer { try? FileManager.default.removeItem(at: url) }
        let archive = try Archive(url: url, accessMode: .read)
        var sheetData = Data()
        _ = try archive.extract(try XCTUnwrap(archive["xl/worksheets/sheet1.xml"])) { sheetData.append($0) }
        let sheetXML = try XCTUnwrap(String(data: sheetData, encoding: .utf8))

        // B11 ("im Monat:" value) / K11 ("Jahr:" value).
        XCTAssertTrue(sheetXML.contains("<t>Juli</t>"))
        XCTAssertTrue(sheetXML.contains("<t>2026</t>"))

        // Day 1 -> C12, day 15 -> O13, day 31 -> C15 (each the top-left cell
        // of its merged amount box).
        XCTAssertTrue(sheetXML.contains("<c r=\"C12\""))
        XCTAssertTrue(sheetXML.contains("<v>30.0</v>"))
        XCTAssertTrue(sheetXML.contains("<c r=\"O13\""))
        XCTAssertTrue(sheetXML.contains("<v>45.0</v>"))
        XCTAssertTrue(sheetXML.contains("<c r=\"C15\""))
        XCTAssertTrue(sheetXML.contains("<v>60.0</v>"))

        // L16 keeps its original SUM(day-grid) formula but its cached value
        // is refreshed to the real total (30+45+60=135); B18 gets the total
        // spelled out in German words.
        XCTAssertTrue(sheetXML.contains("<f>C12+C13+C14+C15+"))
        XCTAssertTrue(sheetXML.contains("<v>135.0</v>"))
        XCTAssertTrue(sheetXML.contains("<c r=\"B18\""))
        XCTAssertTrue(sheetXML.contains("<t>Einhundertfünfunddreißig Euro</t>"))
    }

    /// No deployment days at all -> total is 0 -> B18 stays blank (a pristine
    /// template's own state) rather than printing the slightly absurd "Null
    /// Euro" on an otherwise-empty form. L16 still gets its cached formula
    /// value refreshed to 0 (matches the pristine template's own cached 0,
    /// but confirms the patch path doesn't crash/skip on an empty grid).
    func testExportMainFormLeavesInWortenBlankWithNoEntries() throws {
        let team = Team(name: "Torball 1", sport: "Torball")
        let coach = Member(firstName: "Anna", lastName: "Trainer")
        let membership = TeamMembership(member: coach, team: team, role: "coach")
        let person = PraeEligiblePerson(id: coach.id, displayName: "Anna Trainer", membershipIDs: [membership.id], member: coach)
        let summary = PraeMonthSummary(person: person, month: 7, year: 2026, entries: [])

        let url = try PraeExporter.exportMainForm(summary: summary)
        defer { try? FileManager.default.removeItem(at: url) }
        let archive = try Archive(url: url, accessMode: .read)
        var sheetData = Data()
        _ = try archive.extract(try XCTUnwrap(archive["xl/worksheets/sheet1.xml"])) { sheetData.append($0) }
        let sheetXML = try XCTUnwrap(String(data: sheetData, encoding: .utf8))

        XCTAssertTrue(sheetXML.contains("<v>0.0</v>"))
        XCTAssertFalse(sheetXML.range(of: "<c r=\"B18\"[^>]*><is>", options: .regularExpression) != nil)
    }

    func testExportMainFormLeavesPersonalDataBlankWithoutMember() throws {
        // A person backed only by a User account (no roster entry) has
        // person.member == nil — must not crash, and the personal-data
        // cells must simply stay blank rather than e.g. printing "nil".
        let person = PraeEligiblePerson(id: UUID(), displayName: "Nur-App-Konto", membershipIDs: [], member: nil)
        let summary = PraeMonthSummary(person: person, month: 7, year: 2026, entries: [])

        let url = try PraeExporter.exportMainForm(summary: summary)
        defer { try? FileManager.default.removeItem(at: url) }

        let archive = try Archive(url: url, accessMode: .read)
        var sheetData = Data()
        _ = try archive.extract(try XCTUnwrap(archive["xl/worksheets/sheet1.xml"])) { sheetData.append($0) }
        let sheetXML = try XCTUnwrap(String(data: sheetData, encoding: .utf8))

        XCTAssertTrue(sheetXML.contains("Nur-App-Konto"))
        // L5 (Geburtsdatum) and D33 (IBAN) are conditionally skipped when
        // there's no data — must remain blank template cells (no <is>).
        XCTAssertFalse(sheetXML.range(of: "<c r=\"L5\"[^>]*><is>", options: .regularExpression) != nil)
        XCTAssertFalse(sheetXML.range(of: "<c r=\"D33\"[^>]*><is>", options: .regularExpression) != nil)
    }

    /// The real "Darstellung" template (see PraeExporter's doc comment) only
    /// has a Geburtsdatum field, not Wohnanschrift/SVNR/IBAN — those three
    /// were a from-scratch-only addition, dropped once a real template
    /// existed to check against (confirmed with the user 2026-08-06).
    func testExportDarstellungIncludesGeburtsdatumFromMember() throws {
        let team = Team(name: "Torball 1", sport: "Torball")
        var birthComponents = DateComponents()
        birthComponents.year = 1990
        birthComponents.month = 3
        birthComponents.day = 21
        let birthDate = Calendar.current.date(from: birthComponents)!
        let coach = Member(firstName: "Anna", lastName: "Trainer", street: "Hauptstraße 1", zip: "8010", city: "Graz",
                            birthDate: birthDate, svnr: "1234210390", iban: "AT611904300234573201")
        let membership = TeamMembership(member: coach, team: team, role: "coach")
        let person = PraeEligiblePerson(id: coach.id, displayName: "Anna Trainer", membershipIDs: [membership.id], member: coach)
        let summary = PraeMonthSummary(
            person: person, month: 7, year: 2026,
            entries: [PraeDayEntry(day: 5, amount: 40, purpose: "Torball-Training")]
        )

        let url = try PraeExporter.exportDarstellung(summary: summary)
        defer { try? FileManager.default.removeItem(at: url) }

        let archive = try Archive(url: url, accessMode: .read)
        var sheetData = Data()
        _ = try archive.extract(try XCTUnwrap(archive["xl/worksheets/sheet1.xml"])) { sheetData.append($0) }
        let sheetXML = try XCTUnwrap(String(data: sheetData, encoding: .utf8))

        XCTAssertTrue(sheetXML.contains("21.03.1990"))
        // Wohnanschrift/SVNR/IBAN have no cells in the real template at all
        // (not just conditionally blank) — must never appear.
        XCTAssertFalse(sheetXML.contains("Hauptstraße 1, 8010 Graz"))
        XCTAssertFalse(sheetXML.contains("1234210390"))
        XCTAssertFalse(sheetXML.contains("AT611904300234573201"))
        XCTAssertFalse(sheetXML.contains("Sozialversicherungsnummer:"))
        XCTAssertFalse(sheetXML.contains("IBAN:"))
        XCTAssertFalse(sheetXML.contains("Wohnanschrift:"))
    }

    /// Unlike the from-scratch version this replaced, "Geburtsdatum:" is a
    /// static label baked into the real template (row 4) — it stays printed
    /// even without a Member, only its value cell (C4) stays blank.
    func testExportDarstellungLeavesGeburtsdatumValueBlankWithoutMember() throws {
        let person = PraeEligiblePerson(id: UUID(), displayName: "Nur-App-Konto", membershipIDs: [], member: nil)
        let summary = PraeMonthSummary(
            person: person, month: 7, year: 2026,
            entries: [PraeDayEntry(day: 5, amount: 40, purpose: "Torball-Training")]
        )

        let url = try PraeExporter.exportDarstellung(summary: summary)
        defer { try? FileManager.default.removeItem(at: url) }

        let archive = try Archive(url: url, accessMode: .read)
        var sheetData = Data()
        _ = try archive.extract(try XCTUnwrap(archive["xl/worksheets/sheet1.xml"])) { sheetData.append($0) }
        let sheetXML = try XCTUnwrap(String(data: sheetData, encoding: .utf8))

        XCTAssertTrue(sheetXML.contains("Geburtsdatum:"))
        XCTAssertFalse(sheetXML.range(of: "<c r=\"C4\"[^>]*><is>", options: .regularExpression) != nil)
        XCTAssertFalse(sheetXML.contains("Sozialversicherungsnummer:"))
        XCTAssertFalse(sheetXML.contains("IBAN:"))
        XCTAssertFalse(sheetXML.contains("Wohnanschrift:"))
    }

    /// The real template only has 21 entry rows (rows 8–28) — a hard cap
    /// inherited from the original paper form, not one row per calendar day.
    func testExportDarstellungCapsEntriesAtMaxEntryRows() throws {
        let team = Team(name: "Torball 1", sport: "Torball")
        let coach = Member(firstName: "Anna", lastName: "Trainer")
        let membership = TeamMembership(member: coach, team: team, role: "coach")
        let person = PraeEligiblePerson(id: coach.id, displayName: "Anna Trainer", membershipIDs: [membership.id], member: coach)
        let entries = (1...25).map { PraeDayEntry(day: $0, amount: 20, purpose: "Training \($0)") }
        let summary = PraeMonthSummary(person: person, month: 7, year: 2026, entries: entries)

        let url = try PraeExporter.exportDarstellung(summary: summary)
        defer { try? FileManager.default.removeItem(at: url) }

        let archive = try Archive(url: url, accessMode: .read)
        var sheetData = Data()
        _ = try archive.extract(try XCTUnwrap(archive["xl/worksheets/sheet1.xml"])) { sheetData.append($0) }
        let sheetXML = try XCTUnwrap(String(data: sheetData, encoding: .utf8))

        XCTAssertTrue(sheetXML.contains("<t>Training 21</t>"))
        XCTAssertFalse(sheetXML.contains("<t>Training 22</t>"))
    }

    // MARK: - GermanNumberWords

    func testGermanNumberWordsSpellsOutBasicRanges() {
        XCTAssertEqual(GermanNumberWords.spellOut(0), "null")
        XCTAssertEqual(GermanNumberWords.spellOut(1), "eins")
        XCTAssertEqual(GermanNumberWords.spellOut(12), "zwölf")
        XCTAssertEqual(GermanNumberWords.spellOut(21), "einundzwanzig")
        XCTAssertEqual(GermanNumberWords.spellOut(30), "dreißig")
        XCTAssertEqual(GermanNumberWords.spellOut(100), "einhundert")
        XCTAssertEqual(GermanNumberWords.spellOut(120), "einhundertzwanzig")
        XCTAssertEqual(GermanNumberWords.spellOut(135), "einhundertfünfunddreißig")
        XCTAssertEqual(GermanNumberWords.spellOut(1000), "eintausend")
        XCTAssertEqual(GermanNumberWords.spellOut(2026), "zweitausendsechsundzwanzig")
    }

    func testGermanNumberWordsSpelledOutEuroAmountOmitsCentClauseForWholeEuros() {
        XCTAssertEqual(GermanNumberWords.spelledOutEuroAmount(120), "Einhundertzwanzig Euro")
        XCTAssertEqual(GermanNumberWords.spelledOutEuroAmount(45.5), "Fünfundvierzig Euro und fünfzig Cent")
        // Float noise (e.g. 45.1 + 0.4 in binary floating point) must round
        // to the nearest cent, not spell out a bogus fractional-cent word.
        XCTAssertEqual(GermanNumberWords.spelledOutEuroAmount(45.1 + 0.4), "Fünfundvierzig Euro und fünfzig Cent")
    }
}
