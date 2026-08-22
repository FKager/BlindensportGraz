import XCTest
import SwiftData
import ZIPFoundation
@testable import BlindensportGraz

/// Season-rollup orchestration tests — reuses SammelabrechnungExportTests'
/// container/fixture patterns (phase-16 spec).
final class SammelabrechnungSeasonExportTests: XCTestCase {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            User.self, SportEvent.self, Tournament.self, Training.self, Team.self,
            TeamMembership.self, EventParticipation.self, Member.self,
            EventImage.self, Attendance.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func makeTraining(_ context: ModelContext, team: Team, day: Int, month: Int, year: Int = 2026) -> Training {
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

    /// One month with a PRAE-amounted attendance, one tournament with a
    /// PRAE-amounted attendance, both in 2026 -> the season zip should
    /// contain that month's + that tournament's KostZ/PRAE files, correctly
    /// prefixed and non-colliding, each individually a valid .xlsx. No
    /// training sport has any dates in this fixture, so no Trainingsfrequenzliste
    /// entries are expected.
    func testExportSeasonBundlesEveryMonthAndTournamentWithData() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let team = Team(name: "Torball 1", sport: "Torball")
        context.insert(team)

        let coach = Member(firstName: "Anna", lastName: "Trainer")
        context.insert(coach)
        let membership = TeamMembership(member: coach, team: team, role: .coach)
        context.insert(membership)

        let training = makeTraining(context, team: team, day: 5, month: 3)
        context.insert(Attendance(event: training, membership: membership, attended: true, praeAmount: 30))

        let tournament = Tournament(title: "Landesmeisterschaft", sport: "Torball", location: "Graz",
                                     startDate: Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 1))!,
                                     endDate: Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 2))!,
                                     teams: [team])
        context.insert(tournament)
        context.insert(Attendance(event: tournament, membership: membership, attended: true, praeAmount: 60))

        let allMemberships = try context.fetch(FetchDescriptor<TeamMembership>())
        let tournaments = try context.fetch(FetchDescriptor<Tournament>())

        let url = try SammelabrechnungExporter.exportSeason(
            year: 2026, allMemberships: allMemberships, tournaments: tournaments, sports: [], in: context)
        defer { try? FileManager.default.removeItem(at: url) }

        let archive = try Archive(url: url, accessMode: .read)
        var entryNames: [String] = []
        for entry in archive {
            var data = Data()
            _ = try archive.extract(entry) { data.append($0) }
            XCTAssertFalse(data.isEmpty, "\(entry.path) extracted empty")
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".xlsx")
            try data.write(to: tempURL)
            defer { try? FileManager.default.removeItem(at: tempURL) }
            XCTAssertNoThrow(try Archive(url: tempURL, accessMode: .read))
            entryNames.append(entry.path)
        }

        XCTAssertEqual(Set(entryNames), Set([
            "03-2026_KostZ.xlsx",
            "03-2026_PRAE_Trainer_Anna.xlsx",
            "03-2026_PRAE-Darstellung_Trainer_Anna.xlsx",
            "Turnier_Landesmeisterschaft_KostZ.xlsx",
            "Turnier_Landesmeisterschaft_PRAE_Trainer_Anna.xlsx",
            "Turnier_Landesmeisterschaft_PRAE-Darstellung_Trainer_Anna.xlsx",
        ]))
        // No other month produced files (no eligible people) — confirms
        // months with zero data are skipped, not padded in with empty
        // KostZ sheets.
        XCTAssertFalse(entryNames.contains { $0.hasPrefix("01-2026") || $0.hasPrefix("07-2026") })
    }

    /// A season with literally zero periods/data -> a valid, readable,
    /// zero-entry zip, not a crash.
    func testExportSeasonWithNoDataProducesEmptyValidBundle() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let url = try SammelabrechnungExporter.exportSeason(
            year: 2026, allMemberships: [], tournaments: [], sports: [], in: context)
        defer { try? FileManager.default.removeItem(at: url) }

        let archive = try Archive(url: url, accessMode: .read)
        var entryNames: [String] = []
        for entry in archive { entryNames.append(entry.path) }
        XCTAssertTrue(entryNames.isEmpty)
    }

    /// A training sport with dates in the requested year's first half ->
    /// exactly one Trainingsfrequenzliste entry for H1, none for H2.
    func testExportSeasonIncludesTrainingsfrequenzlisteForSportsWithData() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let team = Team(name: "Torball 1", sport: "Torball")
        context.insert(team)
        _ = makeTraining(context, team: team, day: 5, month: 3) // H1 2026

        let url = try SammelabrechnungExporter.exportSeason(
            year: 2026, allMemberships: [], tournaments: [], sports: ["Torball"], in: context)
        defer { try? FileManager.default.removeItem(at: url) }

        let archive = try Archive(url: url, accessMode: .read)
        var entryNames: [String] = []
        for entry in archive { entryNames.append(entry.path) }
        XCTAssertEqual(entryNames, ["Torball_H1-2026_Trainingsfrequenzliste.xlsx"])
    }
}
