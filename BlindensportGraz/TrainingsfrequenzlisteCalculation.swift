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
    var firstName: String { membership.user?.firstName ?? membership.clubMember?.firstName ?? "" }
    var lastName: String { membership.user?.lastName ?? membership.clubMember?.lastName ?? "" }
}

/// One calendar month's Trainingsfrequenzliste for one team — mirrors the
/// real ÖBSV "Trainingsfrequenzliste" paper form (reverse-engineered from
/// the official .xls, see TrainingsfrequenzlisteExporter's doc comment):
/// one row per roster member (capped at 23, the original template's row
/// count), one column per training date (capped at 33, the original's date-
/// column count), "j"/"n" attendance per cell, and a per-date total row
/// ("ges. TL").
struct TrainingsfrequenzlisteSummary {
    let team: Team
    let month: Int
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

    static func summary(team: Team, month: Int, year: Int, in context: ModelContext) -> TrainingsfrequenzlisteSummary {
        let calendar = Calendar.current

        // Fetch-all-then-filter-in-Swift, matching KostZCalculator/
        // PraeCalculator's established convention rather than a #Predicate
        // with relationship-path traversal (training.teams.contains(...)).
        let allTrainings = (try? context.fetch(FetchDescriptor<Training>())) ?? []
        let monthTrainings = allTrainings.filter { training in
            guard training.teams.contains(where: { $0.id == team.id }) else { return false }
            let components = calendar.dateComponents([.month, .year], from: training.startDate)
            return components.month == month && components.year == year
        }

        let trainingDates = Array(
            Set(monthTrainings.map { calendar.startOfDay(for: $0.startDate) })
                .sorted()
                .prefix(maxDateColumns)
        )
        let monthTrainingIDs = Set(monthTrainings.map(\.id))

        let allAttendances = (try? context.fetch(FetchDescriptor<Attendance>())) ?? []
        var attendedDatesByMembershipID: [UUID: [Date: Bool]] = [:]
        for attendance in allAttendances {
            guard attendance.attended, monthTrainingIDs.contains(attendance.event.id) else { continue }
            let day = calendar.startOfDay(for: attendance.event.startDate)
            guard trainingDates.contains(day) else { continue }
            attendedDatesByMembershipID[attendance.membership.id, default: [:]][day] = true
        }

        let people = team.memberships
            .sorted { $0.displayName < $1.displayName }
            .prefix(maxPersonRows)
            .map { membership in
                TrainingsfrequenzlistePerson(
                    membership: membership,
                    attendedByDate: attendedDatesByMembershipID[membership.id] ?? [:]
                )
            }

        return TrainingsfrequenzlisteSummary(team: team, month: month, year: year,
                                              trainingDates: trainingDates, people: Array(people))
    }
}
