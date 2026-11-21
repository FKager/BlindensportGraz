import XCTest
import SwiftData
@testable import BlindensportGraz

/// The KostZ scenarios in Shared/ReportFixtures/kostz.json, which the web UI's
/// KostZFixtureTest.java reads too: both must give the same form.
@MainActor
final class KostZFixtureTests: XCTestCase {
    private typealias S = ReportFixtureSupport

    private struct Fixture: Decodable {
        struct Event: Decodable {
            let id: String; let title: String; let day: Int; let hour: Int?; let month: Int?; let status: String?
        }
        struct Row: Decodable { let event: String?; let membership: String; let attended: Bool; let amount: Double? }
        struct MonthExpected: Decodable {
            let betrifft: String; let dayCount: Int; let startDay: Int; let endDay: Int
            let people: [[Value]]; let total: Double
        }
        struct Month: Decodable {
            let name: String; let month: Int; let year: Int
            let trainings: [Event]; let tournaments: [Event]; let attendances: [Row]; let expected: MonthExpected
        }
        struct Moment: Decodable { let year: Int; let month: Int; let day: Int; let hour: Int }
        struct TournamentExpected: Decodable { let dayCount: Int; let people: [[Value]]; let total: Double }
        struct TournamentScenario: Decodable {
            let name: String; let start: Moment; let end: Moment; let attendances: [Row]; let expected: TournamentExpected
        }
        let people: [S.PersonSpec]
        let memberships: [S.MembershipSpec]
        let month: [Month]
        let tournament: [TournamentScenario]
    }

    /// A ["Albrecht", 50] pair.
    private enum Value: Decodable, Equatable {
        case text(String), number(Double)
        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let n = try? c.decode(Double.self) { self = .number(n) } else { self = .text(try c.decode(String.self)) }
        }
    }

    private func people(_ amounts: [KostZPersonAmount]) -> [[Value]] {
        amounts.map { [.text($0.person.lastName), .number($0.amount)] }
    }

    func testMonthScenarios() throws {
        let fixture = try S.load("kostz", as: Fixture.self)
        for s in fixture.month {
            let context = try S.context()
            let roster = S.roster(people: fixture.people, teams: [], memberships: fixture.memberships, in: context)
            var events: [String: SportEvent] = [:]
            for t in s.trainings {
                let training = Training(title: t.title, sport: "Torball", location: "Graz",
                                        startDate: try S.date(s.year, t.month ?? s.month, t.day, t.hour ?? 18),
                                        status: t.status ?? "open")
                context.insert(training)
                events[t.id] = training
            }
            for t in s.tournaments {
                let start = try S.date(s.year, s.month, t.day, 9)
                let tournament = Tournament(title: t.title, sport: "Torball", location: "Graz", startDate: start,
                                            endDate: start.addingTimeInterval(8 * 3600))
                context.insert(tournament)
                events[t.id] = tournament
            }
            for a in s.attendances {
                let event = try XCTUnwrap(events[a.event ?? ""], s.name)
                let membership = try XCTUnwrap(roster.memberships[a.membership], s.name)
                context.insert(Attendance(event: event, membership: membership, attended: a.attended, praeAmount: a.amount))
            }

            let summary = KostZCalculator.summary(month: s.month, year: s.year,
                                                  allMemberships: Array(roster.memberships.values), in: context)

            XCTAssertEqual(summary.trainingName, s.expected.betrifft, s.name)
            XCTAssertEqual(summary.trainingDates.count, s.expected.dayCount, s.name)
            XCTAssertEqual(summary.trainingDates.first.map { Calendar.current.component(.day, from: $0) }, s.expected.startDay, s.name)
            XCTAssertEqual(summary.trainingDates.last.map { Calendar.current.component(.day, from: $0) }, s.expected.endDay, s.name)
            XCTAssertEqual(people(summary.personAmounts), s.expected.people, s.name)
            XCTAssertEqual(summary.total, s.expected.total, s.name)
        }
    }

    func testTournamentScenarios() throws {
        let fixture = try S.load("kostz", as: Fixture.self)
        for s in fixture.tournament {
            let context = try S.context()
            let roster = S.roster(people: fixture.people, teams: [], memberships: fixture.memberships, in: context)
            let tournament = Tournament(title: "Turnier", sport: "Torball", location: "Graz",
                                        startDate: try S.date(s.start.year, s.start.month, s.start.day, s.start.hour),
                                        endDate: try S.date(s.end.year, s.end.month, s.end.day, s.end.hour))
            context.insert(tournament)
            for a in s.attendances {
                let membership = try XCTUnwrap(roster.memberships[a.membership], s.name)
                context.insert(Attendance(event: tournament, membership: membership, attended: a.attended, praeAmount: a.amount))
            }

            let summary = KostZCalculator.summary(for: tournament, allMemberships: Array(roster.memberships.values))

            XCTAssertEqual(tournament.dayCount, s.expected.dayCount, s.name)
            XCTAssertEqual(people(summary.personAmounts), s.expected.people, s.name)
            XCTAssertEqual(summary.total, s.expected.total, s.name)
        }
    }
}
