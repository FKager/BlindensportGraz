import XCTest
import SwiftData
@testable import BlindensportGraz

/// Shared setup for the report scenarios in Shared/ReportFixtures/, which the
/// web UI's Java tests read too.
@MainActor
enum ReportFixtureSupport {
    struct PersonSpec: Decodable { let id: String; let first: String; let last: String; let gender: String; let city: String? }
    struct TeamSpec: Decodable { let id: String; let name: String; let sport: String }
    struct MembershipSpec: Decodable { let id: String; let team: String?; let person: String; let role: String }

    static func load<T: Decodable>(_ name: String, as type: T.Type, file: StaticString = #filePath,
                                   line: UInt = #line) throws -> T {
        let url = try XCTUnwrap(Bundle(for: BundleToken.self).url(forResource: name, withExtension: "json"),
                                "\(name).json missing from the test bundle (project.yml: Shared/ReportFixtures)",
                                file: file, line: line)
        return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
    }

    static func context() throws -> ModelContext {
        let schema = Schema([
            User.self, SportEvent.self, Tournament.self, Training.self, Team.self,
            TeamMembership.self, EventParticipation.self, Member.self, EventImage.self, Attendance.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return ModelContext(try ModelContainer(for: schema, configurations: [config]))
    }

    /// Local time, like the app's own Calendar.current grouping.
    static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int) throws -> Date {
        try XCTUnwrap(Calendar.current.date(from: DateComponents(year: year, month: month, day: day, hour: hour)))
    }

    static func day(_ iso: String) throws -> Date {
        let parts = iso.split(separator: "-").compactMap { Int($0) }
        return Calendar.current.startOfDay(for: try date(parts[0], parts[1], parts[2], 12))
    }

    /// Members, teams and memberships of a fixture, keyed by the fixture's ids.
    static func roster(people: [PersonSpec], teams: [TeamSpec], memberships: [MembershipSpec],
                       in context: ModelContext) -> (teams: [String: Team], memberships: [String: TeamMembership]) {
        var members: [String: Member] = [:]
        for p in people {
            let member = Member(firstName: p.first, lastName: p.last, city: p.city ?? "", gender: p.gender)
            context.insert(member)
            members[p.id] = member
        }
        var teamByID: [String: Team] = [:]
        for t in teams {
            let team = Team(name: t.name, sport: t.sport)
            context.insert(team)
            teamByID[t.id] = team
        }
        let fallbackTeam = Team(name: "Team", sport: "Torball")
        context.insert(fallbackTeam)
        var membershipByID: [String: TeamMembership] = [:]
        for m in memberships {
            let membership = TeamMembership(member: members[m.person], team: m.team.flatMap { teamByID[$0] } ?? fallbackTeam,
                                            role: MembershipRole(rawValue: m.role) ?? .player)
            context.insert(membership)
            membershipByID[m.id] = membership
        }
        return (teamByID, membershipByID)
    }

    /// A fixture's short attendance id ("a1") as a UUID that sorts the same way.
    static func uuid(_ short: String) -> UUID {
        let hex = short.unicodeScalars.map { String(format: "%02x", $0.value) }.joined()
        let padded = String(repeating: "0", count: max(0, 32 - hex.count)) + hex
        let s = Array(padded.suffix(32))
        return UUID(uuidString: "\(String(s[0..<8]))-\(String(s[8..<12]))-\(String(s[12..<16]))-\(String(s[16..<20]))-\(String(s[20..<32]))")!
    }

    private final class BundleToken {}
}
