import XCTest
import SwiftData
@testable import BlindensportGraz

/// The scenarios in Shared/ReportFixtures/trainingsfrequenzliste.json, which
/// the web UI's TrainingsfrequenzlisteFixtureTest.java reads too.
@MainActor
final class TrainingsfrequenzlisteFixtureTests: XCTestCase {
    private typealias S = ReportFixtureSupport

    private struct Fixture: Decodable {
        struct TrainingSpec: Decodable {
            let id: String; let title: String; let location: String; let month: Int; let day: Int; let hour: Int
            let teams: [String]; let status: String?; let sport: String?
        }
        struct Row: Decodable { let event: String; let membership: String; let attended: Bool }
        struct PersonRow: Decodable, Equatable { let last: String; let roleSuffix: String?; let attended: [String] }
        struct Expected: Decodable {
            let dates: [String]; let title: String; let location: String; let teams: [String]; let people: [PersonRow]
        }
        struct Scenario: Decodable {
            let name: String; let sport: String; let half: Int; let year: Int
            let trainings: [TrainingSpec]; let attendances: [Row]; let expected: Expected
        }
        let people: [S.PersonSpec]
        let teams: [S.TeamSpec]
        let memberships: [S.MembershipSpec]
        let scenarios: [Scenario]
    }

    func testScenarios() throws {
        let fixture = try S.load("trainingsfrequenzliste", as: Fixture.self)
        let iso = Date.ISO8601FormatStyle(timeZone: .current).year().month().day()
        for s in fixture.scenarios {
            let context = try S.context()
            let roster = S.roster(people: fixture.people, teams: fixture.teams, memberships: fixture.memberships, in: context)
            var trainings: [String: Training] = [:]
            for t in s.trainings {
                let training = Training(title: t.title, sport: t.sport ?? s.sport, location: t.location,
                                        startDate: try S.date(s.year, t.month, t.day, t.hour), durationMinutes: 120,
                                        status: t.status ?? "open", teams: t.teams.compactMap { roster.teams[$0] })
                context.insert(training)
                trainings[t.id] = training
            }
            for a in s.attendances {
                let training = try XCTUnwrap(trainings[a.event], s.name)
                let membership = try XCTUnwrap(roster.memberships[a.membership], s.name)
                context.insert(Attendance(event: training, membership: membership, attended: a.attended))
            }

            let summary = TrainingsfrequenzlisteCalculator.summary(sport: s.sport, halfYear: s.half == 1 ? .first : .second,
                                                                   year: s.year, in: context)

            XCTAssertEqual(summary.trainingDates, try s.expected.dates.map(S.day), s.name)
            XCTAssertEqual(summary.title, s.expected.title, s.name)
            XCTAssertEqual(summary.location, s.expected.location, s.name)
            XCTAssertEqual(summary.teams.map(\.name), s.expected.teams, s.name)
            let people = summary.people.map { person in
                Fixture.PersonRow(last: person.lastName, roleSuffix: person.roleSuffix,
                                  attended: summary.trainingDates.filter(person.attended(on:)).map { $0.formatted(iso) })
            }
            XCTAssertEqual(people, s.expected.people, s.name)
        }
    }
}
