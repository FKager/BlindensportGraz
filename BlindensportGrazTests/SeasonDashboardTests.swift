import XCTest
import SwiftData
@testable import BlindensportGraz

/// Coverage for `SeasonDashboard` (architecture-review.md §5 P2): pure
/// aggregation, no CloudKit/Charts involved.
@MainActor
final class SeasonDashboardTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(schema: AppModelSchema.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return ModelContext(try ModelContainer(for: AppModelSchema.schema, configurations: [config]))
    }

    private func date(_ year: Int, _ month: Int, _ day: Int = 1) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Vienna")!
        return cal.date(from: DateComponents(year: year, month: month, day: day, hour: 18))!
    }

    // MARK: - summary

    func testSummaryCountsOnlyTheSelectedYearAndSumsPrae() throws {
        let context = try makeContext()
        let team = Team(name: "A", sport: "Torball")
        context.insert(team)
        let member = Member(firstName: "Sam", lastName: "Mahler")
        context.insert(member)
        let membership = TeamMembership(member: member, team: team)
        context.insert(membership)

        let trainingIn2026 = Training(title: "T1", sport: "Torball", location: "Graz", startDate: date(2026, 3), teams: [team])
        let trainingIn2025 = Training(title: "T0", sport: "Torball", location: "Graz", startDate: date(2025, 3), teams: [team])
        let tournamentIn2026 = Tournament(title: "Cup", sport: "Torball", location: "Wien",
                                          startDate: date(2026, 6), endDate: date(2026, 6, 2), teams: [team])
        [trainingIn2026, trainingIn2025, tournamentIn2026].forEach(context.insert)

        let present2026 = Attendance(event: trainingIn2026, membership: membership, attended: true, praeAmount: 30)
        let absent2026 = Attendance(event: tournamentIn2026, membership: membership, attended: false)
        let present2025 = Attendance(event: trainingIn2025, membership: membership, attended: true, praeAmount: 100)
        [present2026, absent2026, present2025].forEach(context.insert)
        try context.save()

        let summary = SeasonDashboard.summary(year: 2026, trainings: [trainingIn2026, trainingIn2025],
                                              tournaments: [tournamentIn2026],
                                              attendances: [present2026, absent2026, present2025])

        XCTAssertEqual(summary.trainingsCount, 1, "only the 2026 training counts")
        XCTAssertEqual(summary.tournamentsCount, 1)
        XCTAssertEqual(summary.totalRecords, 2, "only 2026 attendance records count")
        XCTAssertEqual(summary.attendedCount, 1)
        XCTAssertEqual(summary.attendanceRate, 0.5)
        XCTAssertEqual(summary.totalPraeAmount, 30, "the 2025 PRAE amount must not leak into 2026's total")
    }

    func testSummaryHandlesAYearWithNoDataAtAll() {
        let summary = SeasonDashboard.summary(year: 2030, trainings: [], tournaments: [], attendances: [])
        XCTAssertEqual(summary.trainingsCount, 0)
        XCTAssertEqual(summary.totalRecords, 0)
        XCTAssertEqual(summary.attendanceRate, 0, "0 of 0 must not divide by zero")
        XCTAssertEqual(summary.totalPraeAmount, 0)
    }

    // MARK: - teamRates

    func testTeamRatesOnlyIncludesTeamsWithRecordsThatYear() throws {
        let context = try makeContext()
        let active = Team(name: "Aktiv", sport: "Torball")
        let quiet = Team(name: "Still", sport: "Torball")
        [active, quiet].forEach(context.insert)
        let member = Member(firstName: "Sam", lastName: "Mahler")
        context.insert(member)
        let membership = TeamMembership(member: member, team: active)
        context.insert(membership)

        let training = Training(title: "T", sport: "Torball", location: "Graz", startDate: date(2026, 4), teams: [active])
        context.insert(training)
        let attended = Attendance(event: training, membership: membership, attended: true)
        let absent = Attendance(event: training, membership: membership, attended: false)
        [attended, absent].forEach(context.insert)
        try context.save()

        let rates = SeasonDashboard.teamRates(year: 2026, teams: [active, quiet], attendances: [attended, absent])

        XCTAssertEqual(rates.map(\.team.name), ["Aktiv"], "a team with zero records that year is omitted, not shown as 0%")
        XCTAssertEqual(rates.first?.attendedCount, 1)
        XCTAssertEqual(rates.first?.totalCount, 2)
        XCTAssertEqual(rates.first?.rate, 0.5)
    }
}
