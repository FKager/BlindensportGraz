import Foundation

/// Year-scoped club finance summary — pure aggregation over `BudgetEntry` +
/// `Attendance`, no SwiftData/SwiftUI dependency, same style as
/// `SeasonDashboard.swift` (unit-testable independent of any view; the view
/// does the fetch and hands this plain arrays).
enum BudgetSummary {
    struct Summary: Equatable {
        let year: Int
        let fixedSubsidyTotal: Double
        let donationTotal: Double
        // BudgetEntry.eventCost entries only — NOT Attendance.praeAmount.
        let loggedEventCostTotal: Double
        // Attendance.praeAmount summed for the year — same one-line formula
        // SeasonDashboard.Summary.totalPraeAmount already uses. Recomputed
        // here rather than depending on SeasonDashboard.Summary itself,
        // since only this one number is needed, not trainings/tournaments
        // counts or attendance rates.
        let praeTotal: Double
        let otherExpenseTotal: Double
        // Sums EVERY entry where category.isIncome — so a stray `.other(...)`
        // entry (unrecognized category) is still counted, on the expense
        // side per BudgetCategory.isIncome's fail-safe default, rather than
        // vanishing from both totals.
        let totalIncome: Double
        let totalLoggedExpense: Double

        var totalEventCost: Double { loggedEventCostTotal + praeTotal }
        var totalExpense: Double { totalLoggedExpense + praeTotal }
        var netBalance: Double { totalIncome - totalExpense }
    }

    static func summary(year: Int, entries: [BudgetEntry], attendances: [Attendance],
                        calendar: Calendar = .current) -> Summary {
        let yearEntries = entries.filter { isIn(year, $0.date, calendar) }
        let yearAttendances = attendances.filter { isIn(year, $0.event.startDate, calendar) }

        func total(_ category: BudgetCategory) -> Double {
            yearEntries.filter { $0.category == category }.map(\.amount).reduce(0, +)
        }

        return Summary(
            year: year,
            fixedSubsidyTotal: total(.fixedSubsidy),
            donationTotal: total(.donation),
            loggedEventCostTotal: total(.eventCost),
            praeTotal: yearAttendances.compactMap(\.praeAmount).reduce(0, +),
            otherExpenseTotal: total(.otherExpense),
            totalIncome: yearEntries.filter { $0.category.isIncome }.map(\.amount).reduce(0, +),
            totalLoggedExpense: yearEntries.filter { !$0.category.isIncome }.map(\.amount).reduce(0, +)
        )
    }

    private static func isIn(_ year: Int, _ date: Date, _ calendar: Calendar) -> Bool {
        calendar.component(.year, from: date) == year
    }
}
