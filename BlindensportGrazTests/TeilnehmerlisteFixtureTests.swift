import XCTest
import SwiftData
@testable import BlindensportGraz

/// The TeilnehmerInnenliste scenarios in Shared/ReportFixtures/teilnehmerliste.json,
/// which the web UI's TeilnehmerlisteFixtureTest.java reads too.
@MainActor
final class TeilnehmerlisteFixtureTests: XCTestCase {
    private typealias S = ReportFixtureSupport

    private struct Fixture: Decodable {
        struct Moment: Decodable { let year: Int; let month: Int; let day: Int; let hour: Int }
        struct Row: Decodable { let id: String; let membership: String; let attended: Bool }
        struct Expected: Decodable { let days: Int; let sportler: [[String]]; let helfer: [[String]] }
        struct Scenario: Decodable {
            let name: String; let start: Moment; let end: Moment; let attendances: [Row]; let expected: Expected
        }
        let people: [S.PersonSpec]
        let teams: [S.TeamSpec]
        let memberships: [S.MembershipSpec]
        let scenarios: [Scenario]
    }

    func testScenarios() throws {
        let fixture = try S.load("teilnehmerliste", as: Fixture.self)
        for s in fixture.scenarios {
            let context = try S.context()
            let roster = S.roster(people: fixture.people, teams: fixture.teams, memberships: fixture.memberships, in: context)
            let tournament = Tournament(title: "Turnier", sport: "Torball", location: "Halle", city: "Graz",
                                        startDate: try S.date(s.start.year, s.start.month, s.start.day, s.start.hour),
                                        endDate: try S.date(s.end.year, s.end.month, s.end.day, s.end.hour),
                                        teams: Array(roster.teams.values))
            context.insert(tournament)
            for row in s.attendances {
                let membership = try XCTUnwrap(roster.memberships[row.membership], s.name)
                context.insert(Attendance(id: S.uuid(row.id), event: tournament, membership: membership,
                                          attended: row.attended))
            }

            func rows(_ memberships: [TeamMembership]) -> ([[String]], [Int]) {
                let entries = TeilnehmerlisteExporter.entries(from: TeilnehmerlisteContext(
                    betrifft: tournament.title, ort: tournament.cityWithCountry, startDate: tournament.startDate,
                    endDate: tournament.endDate, attendedMemberships: memberships))
                return (entries.map { [$0.name, $0.wohnort] }, entries.map(\.tage))
            }
            let sportler = rows(TeilnehmerlisteExporter.sportler(of: tournament))
            let helfer = rows(TeilnehmerlisteExporter.helfer(of: tournament))

            XCTAssertEqual(sportler.0, s.expected.sportler, s.name)
            XCTAssertEqual(helfer.0, s.expected.helfer, s.name)
            XCTAssertTrue((sportler.1 + helfer.1).allSatisfy { $0 == s.expected.days }, s.name)
        }
    }
}
