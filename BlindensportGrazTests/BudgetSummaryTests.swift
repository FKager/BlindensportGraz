import XCTest
import SwiftData
@testable import BlindensportGraz

/// Coverage for `BudgetSummary`: pure aggregation, no CloudKit involved.
@MainActor
final class BudgetSummaryTests: XCTestCase {

    private func date(_ year: Int, _ month: Int, _ day: Int = 1) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Vienna")!
        return cal.date(from: DateComponents(year: year, month: month, day: day, hour: 18))!
    }

    func testSummarySumsEachCategoryForTheSelectedYearOnly() {
        let subsidy2026 = BudgetEntry(category: .fixedSubsidy, amount: 5000, date: date(2026, 1))
        let donation2026 = BudgetEntry(category: .donation, amount: 200, date: date(2026, 5))
        let donation2025 = BudgetEntry(category: .donation, amount: 999, date: date(2025, 5))

        let summary = BudgetSummary.summary(year: 2026, entries: [subsidy2026, donation2026, donation2025], attendances: [])

        XCTAssertEqual(summary.fixedSubsidyTotal, 5000)
        XCTAssertEqual(summary.donationTotal, 200, "the 2025 donation must not leak into 2026's total")
        XCTAssertEqual(summary.totalIncome, 5200)
    }

    func testSummaryCombinesLoggedEventCostsWithPraeIntoOneEventCostTotal() throws {
        let config = ModelConfiguration(schema: AppModelSchema.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let context = ModelContext(try ModelContainer(for: AppModelSchema.schema, configurations: [config]))
        let team = Team(name: "A", sport: "Torball")
        context.insert(team)
        let member = Member(firstName: "Sam", lastName: "Mahler")
        context.insert(member)
        let membership = TeamMembership(member: member, team: team)
        context.insert(membership)
        let training = Training(title: "T", sport: "Torball", location: "Graz", startDate: date(2026, 3), teams: [team])
        context.insert(training)
        let attendance = Attendance(event: training, membership: membership, attended: true, praeAmount: 40)
        context.insert(attendance)
        try context.save()

        let refereeFee = BudgetEntry(category: .eventCost, amount: 60, date: date(2026, 3))

        let summary = BudgetSummary.summary(year: 2026, entries: [refereeFee], attendances: [attendance])

        XCTAssertEqual(summary.praeTotal, 40)
        XCTAssertEqual(summary.loggedEventCostTotal, 60)
        XCTAssertEqual(summary.totalEventCost, 100, "PRAE and logged event costs must combine into one total")
    }

    func testSummaryComputesNetBalanceAsIncomeMinusExpense() {
        let income = BudgetEntry(category: .donation, amount: 300, date: date(2026, 2))
        let expense = BudgetEntry(category: .otherExpense, amount: 80, date: date(2026, 2))

        let summary = BudgetSummary.summary(year: 2026, entries: [income, expense], attendances: [])

        XCTAssertEqual(summary.totalIncome, 300)
        XCTAssertEqual(summary.totalExpense, 80)
        XCTAssertEqual(summary.netBalance, 220)
    }

    func testSummaryHandlesAYearWithNoDataAtAll() {
        let summary = BudgetSummary.summary(year: 2030, entries: [], attendances: [])
        XCTAssertEqual(summary.totalIncome, 0)
        XCTAssertEqual(summary.totalExpense, 0)
        XCTAssertEqual(summary.netBalance, 0)
    }

    func testUnrecognizedCategoryIsCountedAsExpenseNotSilentlyDropped() {
        let legacy = BudgetEntry(category: BudgetCategory.normalize("legacyGrant"), amount: 150, date: date(2026, 4))

        let summary = BudgetSummary.summary(year: 2026, entries: [legacy], attendances: [])

        XCTAssertEqual(summary.totalIncome, 0, "an unrecognized category must never be counted as income")
        XCTAssertEqual(summary.totalLoggedExpense, 150, "an unrecognized category must still be counted, not silently dropped")
    }
}
