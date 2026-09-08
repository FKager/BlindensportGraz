import XCTest
import SwiftData
@testable import BlindensportGraz

/// Coverage for the shared roster/attendance helpers extracted while adding
/// AttendanceRollCallView (architecture-review.md §1.2 / §5):
/// `SportEvent.rosterAcrossTeams` and `AttendanceService.mark`. Neither
/// touches `CloudKitSync` — `mark` is deliberately the pure, save-free half
/// of `setAttended` for exactly this reason.
@MainActor
final class EventRosterTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            User.self, SportEvent.self, Tournament.self, Training.self, Team.self,
            TeamMembership.self, EventParticipation.self, Member.self,
            EventImage.self, Attendance.self, TrainingFavorite.self, RoleChangeLog.self,
            ExpenseReceipt.self, PendingPush.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return ModelContext(try ModelContainer(for: schema, configurations: [config]))
    }

    private func member(_ context: ModelContext, first: String, last: String) -> Member {
        let m = Member(firstName: first, lastName: last)
        context.insert(m)
        return m
    }

    // MARK: - rosterAcrossTeams

    func testRosterDedupesAPersonOnTwoAssignedTeamsAndSortsByLastName() throws {
        let context = try makeContext()

        let teamA = Team(name: "A", sport: "Torball")
        let teamB = Team(name: "B", sport: "Torball")
        context.insert(teamA); context.insert(teamB)

        let shared = member(context, first: "Sam", last: "Mahler")
        let onlyA = member(context, first: "Ada", last: "Zeller")
        let onlyB = member(context, first: "Ben", last: "Aigner")

        for (team, people) in [(teamA, [shared, onlyA]), (teamB, [shared, onlyB])] {
            for person in people {
                context.insert(TeamMembership(member: person, team: team))
            }
        }

        let training = Training(title: "T", sport: "Torball", location: "Graz",
                                startDate: .now, teams: [teamA, teamB])
        context.insert(training)
        try context.save()

        let roster = training.rosterAcrossTeams
        XCTAssertEqual(roster.count, 3, "the person on both teams must appear once")
        XCTAssertEqual(roster.map(\.lastName), ["Aigner", "Mahler", "Zeller"], "sorted by last name")
    }

    func testRosterIsEmptyWhenNoTeamsAssigned() throws {
        let context = try makeContext()
        let training = Training(title: "T", sport: "Torball", location: "Graz", startDate: .now)
        context.insert(training)
        try context.save()

        XCTAssertTrue(training.rosterAcrossTeams.isEmpty)
    }

    // MARK: - AttendanceService.mark

    func testMarkCreatesOneAttendanceRowThenUpdatesItInPlace() throws {
        let context = try makeContext()
        let team = Team(name: "A", sport: "Torball")
        context.insert(team)
        let membership = TeamMembership(member: member(context, first: "Sam", last: "Mahler"), team: team)
        context.insert(membership)
        let training = Training(title: "T", sport: "Torball", location: "Graz", startDate: .now, teams: [team])
        context.insert(training)
        try context.save()

        let created = AttendanceService.mark(true, for: membership, at: training, modelContext: context)
        XCTAssertTrue(created.attended)
        XCTAssertEqual(training.attendances.count, 1)

        let updated = AttendanceService.mark(false, for: membership, at: training, modelContext: context)
        XCTAssertFalse(updated.attended)
        XCTAssertEqual(updated.id, created.id, "same membership must reuse the same Attendance row")
        XCTAssertEqual(training.attendances.count, 1, "no duplicate row on a second mark")
    }
}
