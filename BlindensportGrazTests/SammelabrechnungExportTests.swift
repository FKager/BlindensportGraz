import XCTest
import SwiftData
import ZIPFoundation
@testable import BlindensportGraz

final class SammelabrechnungExportTests: XCTestCase {

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

    /// End-to-end: two coaches each with a PRAE-amounted Training attendance
    /// in the same month -> the zip should contain one KostZ file plus one
    /// PRAE-Formular + one PRAE-Darstellung per coach (4 files total), each
    /// individually a valid, readable .xlsx.
    func testExportForMonthBundlesKostZAndPraeFilesForEveryEligiblePerson() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let team = Team(name: "Torball 1", sport: "Torball")
        context.insert(team)

        let coach1 = Member(firstName: "Anna", lastName: "Trainer")
        context.insert(coach1)
        let membership1 = TeamMembership(member: coach1, team: team, role: .coach)
        context.insert(membership1)

        let coach2 = Member(firstName: "Bernd", lastName: "Helfer")
        context.insert(coach2)
        let membership2 = TeamMembership(member: coach2, team: team, role: .assistant)
        context.insert(membership2)

        let training = makeTraining(context, team: team, day: 5)
        context.insert(Attendance(event: training, membership: membership1, attended: true, praeAmount: 30))
        context.insert(Attendance(event: training, membership: membership2, attended: true, praeAmount: 20))

        let allMemberships = try context.fetch(FetchDescriptor<TeamMembership>())
        let kostZSummary = KostZCalculator.summary(month: 7, year: 2026, allMemberships: allMemberships, in: context)
        XCTAssertEqual(kostZSummary.personAmounts.count, 2)

        let praeSummaries = kostZSummary.personAmounts.map {
            PraeCalculator.summary(for: $0.person, month: 7, year: 2026, in: context)
        }

        let url = try SammelabrechnungExporter.export(kostZ: kostZSummary, praeSummaries: praeSummaries)
        defer { try? FileManager.default.removeItem(at: url) }

        let archive = try Archive(url: url, accessMode: .read)
        var entryNames: [String] = []
        for entry in archive {
            var data = Data()
            _ = try archive.extract(entry) { data.append($0) }
            XCTAssertFalse(data.isEmpty, "\(entry.path) extracted empty")
            // Every bundled member must itself be a valid, readable .xlsx —
            // confirms we didn't just concatenate garbage, each entry really
            // is its own nested zip archive.
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".xlsx")
            try data.write(to: tempURL)
            defer { try? FileManager.default.removeItem(at: tempURL) }
            XCTAssertNoThrow(try Archive(url: tempURL, accessMode: .read))
            entryNames.append(entry.path)
        }

        XCTAssertEqual(entryNames.count, 5) // KostZ + 2x(PRAE + Darstellung)
        XCTAssertTrue(entryNames.contains("KostZ.xlsx"))
        XCTAssertTrue(entryNames.contains("PRAE_Trainer_Anna.xlsx"))
        XCTAssertTrue(entryNames.contains("PRAE-Darstellung_Trainer_Anna.xlsx"))
        XCTAssertTrue(entryNames.contains("PRAE_Helfer_Bernd.xlsx"))
        XCTAssertTrue(entryNames.contains("PRAE-Darstellung_Helfer_Bernd.xlsx"))
    }

    /// No eligible people at all -> the zip should still contain just the
    /// (empty-total) KostZ file, not crash or produce zero entries.
    func testExportForMonthWithNoEligiblePeopleStillProducesKostZOnly() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let team = Team(name: "Torball 1", sport: "Torball")
        context.insert(team)

        let allMemberships = try context.fetch(FetchDescriptor<TeamMembership>())
        let kostZSummary = KostZCalculator.summary(month: 7, year: 2026, allMemberships: allMemberships, in: context)
        XCTAssertTrue(kostZSummary.personAmounts.isEmpty)

        let url = try SammelabrechnungExporter.export(kostZ: kostZSummary, praeSummaries: [])
        defer { try? FileManager.default.removeItem(at: url) }

        let archive = try Archive(url: url, accessMode: .read)
        var entryNames: [String] = []
        for entry in archive { entryNames.append(entry.path) }
        XCTAssertEqual(entryNames, ["KostZ.xlsx"])
    }

    /// Tournament-scoped overload — same shape, different summary types.
    func testExportForTournamentBundlesKostZAndPraeFiles() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let team = Team(name: "Torball 1", sport: "Torball")
        context.insert(team)
        let coach = Member(firstName: "Anna", lastName: "Trainer")
        context.insert(coach)
        let membership = TeamMembership(member: coach, team: team, role: .coach)
        context.insert(membership)
        let tournament = Tournament(title: "Landesmeisterschaft", sport: "Torball", location: "Graz",
                                     startDate: .now, endDate: .now, teams: [team])
        context.insert(tournament)
        context.insert(Attendance(event: tournament, membership: membership, attended: true, praeAmount: 60))

        let allMemberships = try context.fetch(FetchDescriptor<TeamMembership>())
        let kostZSummary = KostZCalculator.summary(for: tournament, allMemberships: allMemberships)
        let praeSummaries = kostZSummary.personAmounts.map {
            PraeCalculator.summary(for: $0.person, tournament: tournament)
        }

        let url = try SammelabrechnungExporter.export(kostZ: kostZSummary, praeSummaries: praeSummaries)
        defer { try? FileManager.default.removeItem(at: url) }

        let archive = try Archive(url: url, accessMode: .read)
        var entryNames: [String] = []
        for entry in archive { entryNames.append(entry.path) }
        XCTAssertEqual(Set(entryNames), Set(["KostZ.xlsx", "PRAE_Trainer_Anna.xlsx", "PRAE-Darstellung_Trainer_Anna.xlsx"]))
    }
}
