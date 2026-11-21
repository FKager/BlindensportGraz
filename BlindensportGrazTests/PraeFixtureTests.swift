import XCTest
import SwiftData
@testable import BlindensportGraz

/// The PRAE scenarios in Shared/ReportFixtures/prae.json, which the web UI's
/// PraeFixtureTest.java reads too: both calculators must give the same
/// forms, so the app and the web UI never print different amounts.
@MainActor
final class PraeFixtureTests: XCTestCase {
    private struct Fixture: Decodable {
        let month: [MonthScenario]
        let tournament: [TournamentScenario]
    }

    private struct MonthScenario: Decodable {
        struct TrainingSpec: Decodable {
            let id: String
            let title: String
            let day: Int
            let hour: Int
            let month: Int?
            let status: String?
        }
        struct AttendanceSpec: Decodable {
            let event: String
            let attended: Bool
            let amount: Double?
        }
        struct Expected: Decodable {
            let purpose: String
            let entries: [[Double]]
            let total: Double
            let personTotal: Double
            let exceedsMonthlyCap: Bool
            let daysExceedingDailyCap: [Int]
        }
        let name: String
        let month: Int
        let year: Int
        let trainings: [TrainingSpec]
        let attendances: [AttendanceSpec]
        let expected: [Expected]
    }

    private struct TournamentScenario: Decodable {
        struct Moment: Decodable { let year: Int; let month: Int; let day: Int; let hour: Int }
        let name: String
        let start: Moment
        let end: Moment
        let amount: Double
        let expected: [[Double]]
    }

    private func fixture() throws -> Fixture {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "prae", withExtension: "json"),
                                "prae.json missing from the test bundle (project.yml: Shared/ReportFixtures)")
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }

    /// Local time, like the app's own Calendar.current grouping.
    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int) throws -> Date {
        try XCTUnwrap(Calendar.current.date(from: DateComponents(year: year, month: month, day: day, hour: hour)))
    }

    /// A fresh store with one coach, Anna Trainer, on one team.
    private func makeCoach() throws -> (ModelContext, TeamMembership, PraeEligiblePerson) {
        let schema = Schema([
            User.self, SportEvent.self, Tournament.self, Training.self, Team.self,
            TeamMembership.self, EventParticipation.self, Member.self, EventImage.self, Attendance.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let context = ModelContext(try ModelContainer(for: schema, configurations: [config]))
        let team = Team(name: "Torball 1", sport: "Torball")
        context.insert(team)
        let coach = Member(firstName: "Anna", lastName: "Trainer")
        context.insert(coach)
        let membership = TeamMembership(member: coach, team: team, role: .coach)
        context.insert(membership)
        let person = try XCTUnwrap(PraeCalculator.eligiblePeople(
            from: try context.fetch(FetchDescriptor<TeamMembership>())).first)
        return (context, membership, person)
    }

    func testMonthFormsMatchTheSharedScenarios() throws {
        for scenario in try fixture().month {
            let (context, membership, person) = try makeCoach()
            var trainings: [String: Training] = [:]
            for spec in scenario.trainings {
                let training = Training(title: spec.title, sport: "Torball", location: "Graz",
                                        startDate: try date(scenario.year, spec.month ?? scenario.month, spec.day, spec.hour),
                                        status: spec.status ?? "open")
                context.insert(training)
                trainings[spec.id] = training
            }
            for spec in scenario.attendances {
                let training = try XCTUnwrap(trainings[spec.event], scenario.name)
                context.insert(Attendance(event: training, membership: membership, attended: spec.attended,
                                          praeAmount: spec.amount))
            }

            let summaries = PraeCalculator.summaries(for: person, month: scenario.month, year: scenario.year, in: context)

            XCTAssertEqual(summaries.count, scenario.expected.count, "number of forms: \(scenario.name)")
            for (summary, want) in zip(summaries, scenario.expected) {
                XCTAssertEqual(summary.trainingName, want.purpose, scenario.name)
                XCTAssertEqual(summary.entries.map { [Double($0.day), $0.amount] }, want.entries, scenario.name)
                XCTAssertEqual(summary.total, want.total, scenario.name)
                XCTAssertEqual(summary.personTotal, want.personTotal, scenario.name)
                XCTAssertEqual(summary.exceedsMonthlyCap, want.exceedsMonthlyCap, scenario.name)
                XCTAssertEqual(summary.daysExceedingDailyCap, want.daysExceedingDailyCap, scenario.name)
            }
        }
    }

    func testTournamentFormsMatchTheSharedScenarios() throws {
        for scenario in try fixture().tournament {
            let (context, membership, person) = try makeCoach()
            let s = scenario.start, e = scenario.end
            let tournament = Tournament(title: "Turnier", sport: "Torball", location: "Graz",
                                        startDate: try date(s.year, s.month, s.day, s.hour),
                                        endDate: try date(e.year, e.month, e.day, e.hour))
            context.insert(tournament)
            context.insert(Attendance(event: tournament, membership: membership, attended: true,
                                      praeAmount: scenario.amount))

            let summaries = PraeCalculator.summaries(for: person, tournament: tournament)

            XCTAssertEqual(summaries.flatMap(\.entries).map { [Double($0.day), $0.amount] }, scenario.expected,
                           scenario.name)
        }
    }
}
