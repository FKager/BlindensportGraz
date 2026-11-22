import XCTest
import SwiftData
@testable import BlindensportGraz

/// The Teilnehmer sheet shows exactly the exported people, grouped by the team
/// they were present through: the tournament's teams first, then any other.
@MainActor
final class MemberListSectionsTests: XCTestCase {
    func testExportedPeopleAreGroupedByTheirTeam() throws {
        let context = try ReportFixtureSupport.context()
        let damen = Team(name: "Torball Damen", sport: "Torball")
        let herren = Team(name: "Torball Herren", sport: "Torball")
        let gast = Team(name: "Gastspieler", sport: "Torball")
        [damen, herren, gast].forEach(context.insert)
        func person(_ first: String, _ last: String, _ team: Team) -> TeamMembership {
            let member = Member(firstName: first, lastName: last)
            context.insert(member)
            let membership = TeamMembership(member: member, team: team, role: .player)
            context.insert(membership)
            return membership
        }
        let zoe = person("Zoe", "Zach", damen)
        let anna = person("Anna", "Berger", damen)
        let max = person("Max", "Gast", gast)

        let sections = MemberListView.sections(teams: [damen, herren], people: [zoe, max, anna])

        XCTAssertEqual(sections.map(\.team.name), ["Torball Damen", "Torball Herren", "Gastspieler"])
        XCTAssertEqual(sections.map { $0.memberships.map(\.lastName) }, [["Berger", "Zach"], [], ["Gast"]])
    }

    func testNobodyAndNoTeamsMeansNoSections() {
        XCTAssertTrue(MemberListView.sections(teams: [], people: []).isEmpty)
    }
}
