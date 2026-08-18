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

    /// German role suffix printed after the surname in the export, e.g.
    /// "Hobisch (Übungsleiter)" — reverse-engineered from the club's newer
    /// reference file (data/Trainingsfrequenzliste_Torball_2026.xlsx), which
    /// appends "(Übungsleiter/-in)" for coaches and "(Helfer/-in)" for
    /// assistants but leaves plain "player" rows unsuffixed. Derived from
    /// `membership.role` + `Member.gender` (per the user's explicit choice
    /// over adding a dedicated free-text function field) — User-backed
    /// memberships have no gender field and default to the masculine form.
    /// Known gap: the reference file also used a third label, "(Trainer/-in)",
    /// for two specific people, which this app has no separate role for —
    /// those two would come out as "Übungsleiter(in)" here instead. Accepted
    /// tradeoff; revisit by adding a per-person function field if that
    /// distinction ever needs to be exact.
    var roleSuffix: String? {
        let isFemale = membership.member?.gender == "f"
        switch membership.role {
        case "coach": return isFemale ? "Übungsleiterin" : "Übungsleiter"
        case "assistant": return isFemale ? "Helferin" : "Helfer"
        default: return nil
        }
    }
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

/// One half-year's Trainingsfrequenzliste for one training sport (e.g.
/// "Torball", "Blindenfußball") — mirrors the club's real reference
/// "Trainingsfrequenzliste" template (see TrainingsfrequenzlisteExporter's
/// doc comment): one row per roster member (capped at 24, the template's
/// person-row count, rows 8–31), one column per training date (capped at
/// 25, the template's date-column count, D–AB), "j"/"n" attendance per
/// cell, and a per-date total row ("ges. TL").
///
/// Scoped by `Training.sport`, not by a hand-picked team — the original form
/// files one homogenous sheet per "Sportart", and a sport can be trained by
/// several teams (e.g. "Torball" has both a Damen and a Herren team). The
/// roster itself still comes from whichever teams were actually assigned to
/// this period's trainings (`teams`), same as before — only the *selection*
/// moved from team to sport, per user request.
struct TrainingsfrequenzlisteSummary {
    let sport: String
    let halfYear: HalfYear
    let year: Int
    let trainingDates: [Date] // sorted ascending, capped at maxDateColumns
    let people: [TrainingsfrequenzlistePerson] // sorted by displayName, capped at maxPersonRows
    let teams: [Team] // every team assigned to a training in this period, in first-seen order

    // "Sportart:"/"Trainingszeiten:"/"Sportstätte:" header fields — all taken
    // from whichever period training is chronologically earliest
    // (`representativeTraining`), since in practice a sport trains at one
    // recurring weekly slot/venue and the form only has room for a single
    // representative value, not one per training day. Nil when the period
    // has no trainings at all.
    //
    // Note: "Sportstätte:" (location) was deliberately left un-derived here
    // until 2026-08-18, per an earlier explicit user request that it keep
    // whatever venue the bundled template already had filled in — the user
    // has since reversed that decision and asked for it to come from the
    // trainings like startTime/endTime do. See TrainingsfrequenzlisteExporter's
    // doc comment for where this gets patched into Y3.
    //
    // "Sportart:" (title) similarly used to be just the `sport` parameter
    // itself (e.g. "Torball") until 2026-08-18, when the user asked for it to
    // show the representative Training's own `title` instead (e.g. the club's
    // real training entries carry a more specific name than the sport
    // category alone). `sport` is kept as-is for scoping/fallback — see
    // TrainingsfrequenzlisteExporter's P3 patch for the fallback rule.
    let startTime: Date?
    let endTime: Date?
    let location: String?
    let title: String?

    func totalPresent(on date: Date) -> Int {
        people.reduce(0) { $0 + ($1.attended(on: date) ? 1 : 0) }
    }
}

/// Computes the data behind the Trainingsfrequenzliste export — see
/// TrainingsfrequenzlisteExporter for where this gets rendered into the
/// .xlsx file.
enum TrainingsfrequenzlisteCalculator {
    static let maxDateColumns = 25
    static let maxPersonRows = 24

    static func summary(sport: String, halfYear: HalfYear, year: Int, in context: ModelContext) -> TrainingsfrequenzlisteSummary {
        let calendar = Calendar.current

        // Fetch-all-then-filter-in-Swift, matching KostZCalculator/
        // PraeCalculator's established convention rather than a #Predicate
        // with relationship-path traversal.
        let allTrainings = (try? context.fetch(FetchDescriptor<Training>())) ?? []
        let periodTrainings = allTrainings.filter { training in
            guard training.sport == sport else { return false }
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

        // Every team assigned to any of this period's trainings — the report
        // still belongs to the assigned teams and their attendees, just
        // unioned across however many teams train this sport in the period
        // (mirrors TrainingDetailView.allMemberships' team-union approach).
        var seenTeamIDs = Set<UUID>()
        var assignedTeams: [Team] = []
        for training in periodTrainings {
            for team in training.teams where seenTeamIDs.insert(team.id).inserted {
                assignedTeams.append(team)
            }
        }

        let allAttendances = (try? context.fetch(FetchDescriptor<Attendance>())) ?? []
        var attendedDatesByMembershipID: [UUID: [Date: Bool]] = [:]
        for attendance in allAttendances {
            guard attendance.attended, periodTrainingIDs.contains(attendance.event.id) else { continue }
            let day = calendar.startOfDay(for: attendance.event.startDate)
            guard trainingDates.contains(day) else { continue }
            attendedDatesByMembershipID[attendance.membership.id, default: [:]][day] = true
        }

        // Every roster member across all assigned teams appears (an admin
        // needs the full assigned roster to file the report), regardless of
        // whether they attended anything in this period — only the per-date
        // "j"/"n" cell reflects actual attendance, via
        // TrainingsfrequenzlistePerson.attended(on:). Deduped by the
        // underlying person, same as TrainingDetailView.allMemberships — the
        // same person could otherwise appear twice if they're in two teams
        // both assigned to trainings of this sport in this period.
        var seenPersonKeys = Set<UUID>()
        var memberships: [TeamMembership] = []
        for team in assignedTeams {
            for membership in team.memberships {
                let key = membership.user?.id ?? membership.member?.id ?? membership.id
                if seenPersonKeys.insert(key).inserted {
                    memberships.append(membership)
                }
            }
        }

        let people = memberships
            .sortedByLastName()
            .prefix(maxPersonRows)
            .map { membership in
                TrainingsfrequenzlistePerson(
                    membership: membership,
                    attendedByDate: attendedDatesByMembershipID[membership.id] ?? [:]
                )
            }

        let representativeTraining = periodTrainings.min { $0.startDate < $1.startDate }

        return TrainingsfrequenzlisteSummary(sport: sport, halfYear: halfYear, year: year,
                                              trainingDates: trainingDates, people: Array(people),
                                              teams: assignedTeams,
                                              startTime: representativeTraining?.startDate,
                                              endTime: representativeTraining?.endDate,
                                              location: representativeTraining?.location,
                                              title: representativeTraining?.title)
    }
}
