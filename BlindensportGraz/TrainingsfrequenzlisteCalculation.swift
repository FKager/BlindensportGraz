import Foundation
import SwiftData

/// One roster row of the Trainingsfrequenzliste: a team member plus their
/// "j"/"n" attendance for every training date in the requested month.
/// `attendedByDate` only ever holds `true` entries — a date missing from the
/// dictionary means "n" (not present), matching the real form's rule
/// ("bei anwesenden SportlerInnen 'j' sonst 'n' eintragen": every cell is
/// filled, absence just means "n") and this app's existing convention that
/// an `Attendance` row is only created once a checkbox is actually toggled
/// (see Models.swift's doc comment on `Attendance`).
struct TrainingsfrequenzlistePerson: Identifiable {
    var id: UUID { membership.id }
    let membership: TeamMembership
    let attendedByDate: [Date: Bool]

    var displayName: String { membership.displayName }
    func attended(on date: Date) -> Bool { attendedByDate[date] ?? false }

    // Vorname/Nachname as two separate columns, matching the original
    // template's layout (TeamMembership.displayName combines them into one
    // string for every other use site in the app, which doesn't fit here).
    var firstName: String { membership.user?.firstName ?? membership.member?.firstName ?? "" }
    var lastName: String { membership.user?.lastName ?? membership.member?.lastName ?? "" }
}

/// The two federal reporting periods Sport Austria's Trainingsfrequenzliste
/// is filed for — half-year, not calendar-month, matching the original
/// form's own "Zeitraum" field and its 33-date-column capacity (33 dates
/// fits a half-year's worth of training days, not a single month's).
enum HalfYear: Int, CaseIterable, Identifiable, Hashable {
    case first = 1  // Jänner–Juni
    case second = 2 // Juli–Dezember

    var id: Int { rawValue }
    var months: ClosedRange<Int> { self == .first ? 1...6 : 7...12 }
    var label: String { self == .first ? "1. Halbjahr (Jänner–Juni)" : "2. Halbjahr (Juli–Dezember)" }
}

/// One half-year's Trainingsfrequenzliste for one team — mirrors the
/// real ÖBSV "Trainingsfrequenzliste" paper form (reverse-engineered from
/// the official .xls, see TrainingsfrequenzlisteExporter's doc comment):
/// one row per roster member (capped at 23, the original template's row
/// count), one column per training date (capped at 33, the original's date-
/// column count), "j"/"n" attendance per cell, and a per-date total row
/// ("ges. TL").
struct TrainingsfrequenzlisteSummary {
    let team: Team
    let halfYear: HalfYear
    let year: Int
    let trainingDates: [Date] // sorted ascending, capped at maxDateColumns
    let people: [TrainingsfrequenzlistePerson] // sorted by displayName, capped at maxPersonRows

    func totalPresent(on date: Date) -> Int {
        people.reduce(0) { $0 + ($1.attended(on: date) ? 1 : 0) }
    }
}

/// Computes the data behind the Trainingsfrequenzliste export — see
/// TrainingsfrequenzlisteExporter for where this gets rendered into the
/// .xlsx file.
enum TrainingsfrequenzlisteCalculator {
    static let maxDateColumns = 33
    static let maxPersonRows = 23

    static func summary(team: Team, halfYear: HalfYear, year: Int, in context: ModelContext) -> TrainingsfrequenzlisteSummary {
        let calendar = Calendar.current

        // Fetch-all-then-filter-in-Swift, matching KostZCalculator/
        // PraeCalculator's established convention rather than a #Predicate
        // with relationship-path traversal (training.teams.contains(...)).
        let allTrainings = (try? context.fetch(FetchDescriptor<Training>())) ?? []
        let periodTrainings = allTrainings.filter { training in
            guard training.teams.contains(where: { $0.id == team.id }) else { return false }
            let components = calendar.dateComponents([.month, .year], from: training.startDate)
            guard let month = components.month else { return false }
            return halfYear.months.contains(month) && components.year == year
        }

        let trainingDates = Array(
            Set(periodTrainings.map { calendar.startOfDay(for: $0.startDate) })
                .sorted()
                .prefix(maxDateColumns)
        )
        let periodTrainingIDs = Set(periodTrainings.map(\.id))

        let allAttendances = (try? context.fetch(FetchDescriptor<Attendance>())) ?? []
        var attendedDatesByMembershipID: [UUID: [Date: Bool]] = [:]
        for attendance in allAttendances {
            guard attendance.attended, periodTrainingIDs.contains(attendance.event.id) else { continue }
            let day = calendar.startOfDay(for: attendance.event.startDate)
            guard trainingDates.contains(day) else { continue }
            attendedDatesByMembershipID[attendance.membership.id, default: [:]][day] = true
        }

        // Every roster member appears (an admin needs the full assigned
        // roster to file the report), regardless of whether they attended
        // anything in this period — only the per-date "j"/"n" cell reflects
        // actual attendance, via TrainingsfrequenzlistePerson.attended(on:).
        let people = team.memberships
            .sorted { $0.displayName < $1.displayName }
            .prefix(maxPersonRows)
            .map { membership in
                TrainingsfrequenzlistePerson(
                    membership: membership,
                    attendedByDate: attendedDatesByMembershipID[membership.id] ?? [:]
                )
            }

        return TrainingsfrequenzlisteSummary(team: team, halfYear: halfYear, year: year,
                                              trainingDates: trainingDates, people: Array(people))
    }
}
