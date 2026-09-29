import Foundation
import SwiftData

@Model
@available(iOS 26, *)
final class Training: SportEvent {
    var durationMinutes: Int = 90
    var focusArea: String = ""
    // "open", "held", "cancelled" — mirrors Tournament.status's shape (a
    // plain String, not an enum, so CloudKit round-trips it with no
    // encoding step). User request 2026-09-10: every training needs a
    // status of Offen/Durchgeführt/Abgesagt, with a quick "Abgesagt" swipe
    // action from TrainingsListView (see TrainingsListView.swift) — unlike
    // Tournament's status, "held" isn't set automatically by any date/time
    // logic, an admin/coach sets it explicitly (either via the swipe action
    // or the edit Picker in TrainingDetailView).
    var status: String = "open"

    init(id: UUID = UUID(),
         title: String,
         sport: String,
         location: String,
         street: String = "",
         zip: String = "",
         city: String = "",
         country: String = "",
         startDate: Date,
         durationMinutes: Int = 90,
         focusArea: String = "",
         status: String = "open",
         notes: String = "",
         createdBy: String = "",
         createdAt: Date = .now,
         teams: [Team] = []) {
        self.durationMinutes = durationMinutes
        self.focusArea = focusArea
        self.status = status
        let endDate = startDate.addingTimeInterval(TimeInterval(durationMinutes) * 60)
        super.init(id: id, title: title, sport: sport, location: location, street: street, zip: zip, city: city, country: country,
                   startDate: startDate, endDate: endDate, notes: notes, createdBy: createdBy, createdAt: createdAt, teams: teams)
        self.kind = "training"
    }

    /// Keeps the inherited, stored `endDate` in sync with startDate +
    /// durationMinutes. SwiftData model properties don't support
    /// didSet/property-observer sync, so this has to be called explicitly
    /// wherever startDate or durationMinutes changes — see
    /// TrainingDetailView's .onChange handlers.
    func recomputeEndDate() {
        endDate = startDate.addingTimeInterval(TimeInterval(durationMinutes) * 60)
    }
}

extension Training {
    static let openStatus = "open"
    static let heldStatus = "held"
    static let cancelledStatus = "cancelled"

    /// Localized label for `status` — the single source both TrainingRow's
    /// badge and TrainingDetailView's Picker/read-only row draw from, so
    /// they can't drift apart the way TournamentRow's raw-string badge and
    /// TournamentDetailView's separate `statusLabel` switch already have.
    var statusLabel: String {
        switch status {
        case Training.openStatus: return "Offen"
        case Training.heldStatus: return "Durchgeführt"
        case Training.cancelledStatus: return "Abgesagt"
        default: return status
        }
    }

    /// Weekly-recurring start dates for AddTrainingView's optional repeat
    /// range: one occurrence on `start`'s own weekday and time-of-day per
    /// week, from `start` through `end` inclusive. `end` is compared by
    /// calendar day only (AddTrainingView collects it via a date-only
    /// DatePicker, same as Tournament's — see cerebrum's 2026-08-18 Uhrzeit
    /// preference) so a same-day end date still includes that occurrence.
    /// `end == nil` (or before `start`) means "just the one training" —
    /// returns `[start]`, matching "when only a start date is specified,
    /// only one training for this day should be created." Uses
    /// `.weekOfYear` arithmetic, not repeated +7-day addition, so it stays
    /// on the same weekday and wall-clock time across a DST boundary — same
    /// reasoning as `TrainingFavorite.seriesStartDates`.
    static func weeklyRangeDates(from start: Date, through end: Date?, calendar: Calendar = .current) -> [Date] {
        guard let end, calendar.startOfDay(for: end) >= calendar.startOfDay(for: start) else { return [start] }
        var dates: [Date] = [start]
        var current = start
        while let next = calendar.date(byAdding: .weekOfYear, value: 1, to: current),
              calendar.startOfDay(for: next) <= calendar.startOfDay(for: end) {
            dates.append(next)
            current = next
        }
        return dates
    }
}
