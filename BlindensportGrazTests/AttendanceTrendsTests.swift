import XCTest
import SwiftData
@testable import BlindensportGraz

final class AttendanceTrendsTests: XCTestCase {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            User.self, SportEvent.self, Tournament.self, Training.self, Team.self,
            TeamMembership.self, EventParticipation.self, Member.self,
            EventImage.self, Attendance.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func makeTraining(_ context: ModelContext, day: Int, month: Int, year: Int = 2026) -> Training {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 18
        let date = Calendar.current.date(from: components)!
        let training = Training(title: "Training", sport: "Torball", location: "Graz", startDate: date)
        context.insert(training)
        return training
    }

    // MARK: - monthlyRates

    func testMonthlyRatesComputesAttendedOverTotalPerMonth() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let team = Team(name: "Torball 1", sport: "Torball")
        context.insert(team)
        let person = Member(firstName: "Anna", lastName: "Spielerin")
        context.insert(person)
        let membership = TeamMembership(member: person, team: team, role: .player)
        context.insert(membership)

        // July: 2 attended, 1 not — expected rate 2/3.
        let julyA = makeTraining(context, day: 1, month: 7)
        let julyB = makeTraining(context, day: 8, month: 7)
        let julyC = makeTraining(context, day: 15, month: 7)
        context.insert(Attendance(event: julyA, membership: membership, attended: true))
        context.insert(Attendance(event: julyB, membership: membership, attended: true))
        context.insert(Attendance(event: julyC, membership: membership, attended: false))

        // August: 1 attended, 1 total — expected rate 1/1.
        let augA = makeTraining(context, day: 5, month: 8)
        context.insert(Attendance(event: augA, membership: membership, attended: true))

        let records = try context.fetch(FetchDescriptor<Attendance>())
        let points = AttendanceTrends.monthlyRates(records)

        XCTAssertEqual(points.count, 2)
        let july = try XCTUnwrap(points.first { Calendar.current.component(.month, from: $0.period) == 7 })
        XCTAssertEqual(july.attendedCount, 2)
        XCTAssertEqual(july.totalCount, 3)
        XCTAssertEqual(july.rate, 2.0 / 3.0, accuracy: 0.0001)

        let august = try XCTUnwrap(points.first { Calendar.current.component(.month, from: $0.period) == 8 })
        XCTAssertEqual(august.attendedCount, 1)
        XCTAssertEqual(august.totalCount, 1)
        XCTAssertEqual(august.rate, 1.0, accuracy: 0.0001)

        // Sorted chronologically.
        XCTAssertLessThan(july.period, august.period)
    }

    func testMonthlyRatesReturnsEmptyForNoRecords() {
        XCTAssertTrue(AttendanceTrends.monthlyRates([]).isEmpty)
    }

    // MARK: - records(forTeamID:) / records(forMembershipID:)

    func testRecordsForTeamIDOnlyIncludesThatTeamsMemberships() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let teamA = Team(name: "Team A", sport: "Torball")
        let teamB = Team(name: "Team B", sport: "Torball")
        [teamA, teamB].forEach(context.insert)

        let personA = Member(firstName: "Anna", lastName: "A")
        let personB = Member(firstName: "Bea", lastName: "B")
        [personA, personB].forEach(context.insert)

        let membershipA = TeamMembership(member: personA, team: teamA, role: .player)
        let membershipB = TeamMembership(member: personB, team: teamB, role: .player)
        [membershipA, membershipB].forEach(context.insert)

        let training = makeTraining(context, day: 1, month: 7)
        let attendanceA = Attendance(event: training, membership: membershipA, attended: true)
        let attendanceB = Attendance(event: training, membership: membershipB, attended: true)
        [attendanceA, attendanceB].forEach(context.insert)

        let all = try context.fetch(FetchDescriptor<Attendance>())
        let teamAOnly = AttendanceTrends.records(all, forTeamID: teamA.id)

        XCTAssertEqual(teamAOnly.count, 1)
        XCTAssertEqual(teamAOnly.first?.membership.id, membershipA.id)
    }

    func testRecordsForMembershipIDOnlyIncludesThatPerson() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let team = Team(name: "Team", sport: "Torball")
        context.insert(team)

        let personA = Member(firstName: "Anna", lastName: "A")
        let personB = Member(firstName: "Bea", lastName: "B")
        [personA, personB].forEach(context.insert)

        let membershipA = TeamMembership(member: personA, team: team, role: .player)
        let membershipB = TeamMembership(member: personB, team: team, role: .player)
        [membershipA, membershipB].forEach(context.insert)

        let training = makeTraining(context, day: 1, month: 7)
        context.insert(Attendance(event: training, membership: membershipA, attended: true))
        context.insert(Attendance(event: training, membership: membershipB, attended: false))

        let all = try context.fetch(FetchDescriptor<Attendance>())
        let personAOnly = AttendanceTrends.records(all, forMembershipID: membershipA.id)

        XCTAssertEqual(personAOnly.count, 1)
        XCTAssertEqual(personAOnly.first?.attended, true)
    }
}
