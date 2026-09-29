import Foundation
import SwiftData

/// One club-finance ledger line for a given calendar year: the fixed annual
/// subsidy, a donation, a logged (non-PRAE) event/training/tournament cost,
/// or a general expense — see `BudgetCategory.swift`.
///
/// Deliberately does NOT duplicate `Attendance.praeAmount` (trainer/helper
/// compensation, already tracked per-attendance and reported via
/// KostZ/PRAE/Sammelabrechnung) — `BudgetSummary` combines that existing
/// total with `.eventCost` entries here into one honest event-cost figure,
/// so nothing has to be entered twice.
@Model
final class BudgetEntry {
    @Attribute(.unique) var id: UUID = UUID()
    var category: BudgetCategory = BudgetCategory.otherExpense
    // Always a positive magnitude — income vs. expense comes entirely from
    // `category.isIncome`, never from this value's sign.
    var amount: Double = 0
    // The date the transaction actually happened (may be backdated), NOT
    // when this record was created — see `createdAt` for that.
    var date: Date = Date.now
    var note: String = ""
    // Optional link to one Training/Tournament/Event — `SportEvent`, not
    // `Training`/`Tournament` specifically, so a plain Event (e.g. renting a
    // hall for a Weihnachtsfeier) can be linked too.
    var event: SportEvent?
    var createdBy: String = ""
    var createdAt: Date = Date.now

    init(id: UUID = UUID(),
         category: BudgetCategory,
         amount: Double,
         date: Date = .now,
         note: String = "",
         event: SportEvent? = nil,
         createdBy: String = "",
         createdAt: Date = .now) {
        self.id = id
        self.category = category
        self.amount = amount
        self.date = date
        self.note = note
        self.event = event
        self.createdBy = createdBy
        self.createdAt = createdAt
    }
}
