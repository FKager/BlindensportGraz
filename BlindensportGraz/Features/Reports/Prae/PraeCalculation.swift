import Foundation
import SwiftData

/// One club member/user who has at least one coach/assistant ("Helfer")
/// TeamMembership, deduped across teams by the underlying person the same
/// way `TrainingDetailView.allMemberships` dedupes attendee rows — a person
/// coaching two teams should appear once here, with PRAE calculated across
/// every team's Attendance records, not per-membership.
struct PraeEligiblePerson: Identifiable, Hashable {
    let id: UUID
    let displayName: String
    let lastName: String
    let firstName: String
    let membershipIDs: [UUID]
    // Carried through from the representative membership so exporters can
    // fill in name/address without a second lookup — only Member has an
    // address (User doesn't), so a person backed only by a registered
    // account exports with a blank Wohnanschrift on the PRAE form.
    let member: Member?

    // Explicit init (rather than relying on the synthesized memberwise one)
    // so lastName/firstName can default to "" — existing test fixtures that
    // only need displayName (export round-trip tests, not sort-order tests)
    // don't need updating; real callers (eligiblePeople below) always pass both.
    init(id: UUID, displayName: String, lastName: String = "", firstName: String = "",
         membershipIDs: [UUID], member: Member?) {
        self.id = id
        self.displayName = displayName
        self.lastName = lastName
        self.firstName = firstName
        self.membershipIDs = membershipIDs
        self.member = member
    }

    static func == (lhs: PraeEligiblePerson, rhs: PraeEligiblePerson) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    /// PRAE's own name-field convention (per Sport Austria form + user
    /// request 2026-08-18): "Nachname, Vorname" — the opposite order from
    /// `displayName`'s "Vorname Nachname" used everywhere else in the app.
    /// Falls back to `displayName` when either part is blank (e.g. test
    /// fixtures built via the displayName-only init) rather than emitting a
    /// bare trailing/leading comma.
    var praeFormName: String {
        let last = lastName.trimmingCharacters(in: .whitespaces)
        let first = firstName.trimmingCharacters(in: .whitespaces)
        guard !last.isEmpty, !first.isEmpty else { return displayName }
        return "\(last), \(first)"
    }
}

/// One calendar day's PRAE deployment for a person in a given month.
struct PraeDayEntry: Identifiable {
    var id: Int { day }
    let day: Int
    let amount: Double
    /// Titles of every training/tournament that contributed to this day,
    /// joined — becomes the "Verwendungszweck" column on the Darstellung
    /// export. Usually one, but a person could have two sessions same day.
    let purpose: String
}

struct PraeMonthSummary {
    let person: PraeEligiblePerson
    let month: Int
    let year: Int
    let entries: [PraeDayEntry] // sorted by day
    // The one training this form covers, its title as on the main PRAE
    // form's "Verwendungszweck:" (T11) field.
    let trainingName: String // defaulted so existing test fixtures that don't care about it still compile
    // The person's amount per day across ALL their trainings that month. The
    // legal caps apply to the person, not to one form, so they're checked
    // against these rather than `entries`. Empty means `entries` is all there is.
    let personDayTotals: [Int: Double]

    init(person: PraeEligiblePerson, month: Int, year: Int, entries: [PraeDayEntry], trainingName: String = "",
         personDayTotals: [Int: Double] = [:]) {
        self.person = person
        self.month = month
        self.year = year
        self.entries = entries
        self.trainingName = trainingName
        self.personDayTotals = personDayTotals
    }

    var total: Double { entries.reduce(0) { $0 + $1.amount } }
    /// The person's total across all their trainings that month.
    var personTotal: Double { personDayTotals.isEmpty ? total : personDayTotals.values.reduce(0, +) }
    var exceedsMonthlyCap: Bool { personTotal > PraeCalculator.monthlyCap }
    var daysExceedingDailyCap: [Int] {
        entries.filter { (personDayTotals[$0.day] ?? $0.amount) > PraeCalculator.dailyCap }.map(\.day)
    }
}

/// One tournament's PRAE deployment days for one helper/coach in one calendar
/// month, scoped to just that tournament's own Attendance.praeAmount records —
/// the per-tournament counterpart to PraeMonthSummary, same relationship as
/// KostZTournamentSummary/KostZMonthSummary in KostZCalculation.swift. The form
/// and its day grid cover one month, so a tournament that runs into the next
/// month has one of these per month.
struct PraeTournamentSummary {
    let person: PraeEligiblePerson
    let tournament: Tournament
    let entries: [PraeDayEntry] // sorted by day
    let month: Int
    let year: Int
    let spansSeveralMonths: Bool

    init(person: PraeEligiblePerson, tournament: Tournament, entries: [PraeDayEntry],
         month: Int? = nil, year: Int? = nil, spansSeveralMonths: Bool = false) {
        let start = Calendar.current.dateComponents([.month, .year], from: tournament.startDate)
        self.person = person
        self.tournament = tournament
        self.entries = entries
        self.month = month ?? start.month ?? 1
        self.year = year ?? start.year ?? 0
        self.spansSeveralMonths = spansSeveralMonths
    }

    var total: Double { entries.reduce(0) { $0 + $1.amount } }
    var exceedsMonthlyCap: Bool { total > PraeCalculator.monthlyCap }
    var daysExceedingDailyCap: [Int] { entries.filter { $0.amount > PraeCalculator.dailyCap }.map(\.day) }

    /// "August 2026".
    var monthLabel: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_AT")
        formatter.dateFormat = "LLLL yyyy"
        let date = Calendar.current.date(from: DateComponents(year: year, month: month, day: 1)) ?? tournament.startDate
        return formatter.string(from: date)
    }
}

/// Computes PRAE ("Pauschale Reiseaufwandsentschädigung") deployment days
/// and amounts for one helper/coach from this app's existing Attendance
/// records — see Attendance.praeAmount. Legal caps per Sport Austria's
/// official "Aufzeichnung über Einsätze..." form (Stand: 10/2023): max
/// €120 per Einsatztag (deployment day), max €720 per calendar month.
/// These are flagged, not enforced — the admin can still exceed them
/// (e.g. genuinely paying above the tax-free threshold makes the excess
/// taxable, which is a legitimate choice, not necessarily a data-entry bug).
///
/// PRAE is now filed from two different places with two different scopes
/// (same split as KostZ, same reason): a tournament's own PRAE (see
/// summary(for:tournament:)) is filed per event, so the monthly summary
/// below is restricted to Training attendances only — otherwise a
/// tournament's deployment days would be recorded on both the tournament's
/// own PRAE paperwork and again on that month's Training one.
enum PraeCalculator {
    static let dailyCap = 120.0
    static let monthlyCap = 720.0

    /// Dedupes coach/assistant TeamMemberships (across every team, app-wide)
    /// down to one entry per underlying person, sorted by lastName.
    static func eligiblePeople(from allMemberships: [TeamMembership]) -> [PraeEligiblePerson] {
        var byKey: [UUID: (name: String, lastName: String, firstName: String, ids: [UUID], member: Member?)] = [:]
        for membership in allMemberships where membership.role.isHelfer {
            let key = membership.user?.id ?? membership.member?.id ?? membership.id
            if var existing = byKey[key] {
                existing.ids.append(membership.id)
                byKey[key] = existing
            } else {
                byKey[key] = (membership.displayName, membership.lastName, membership.firstName, [membership.id], membership.member)
            }
        }
        return byKey.map { key, value in
            PraeEligiblePerson(id: key, displayName: value.name, lastName: value.lastName, firstName: value.firstName,
                                membershipIDs: value.ids, member: value.member)
        }.sorted { ($0.lastName, $0.firstName) < ($1.lastName, $1.firstName) }
    }

    /// One PRAE per training the person was deployed for in the given month:
    /// a person on more than one training files a separate form for each. A
    /// training is its name, as a weekly series shares one and the form's
    /// Verwendungszweck names it, so its sessions stay together on one form,
    /// and two sessions on the same day are summed, as the form only allows
    /// one amount per calendar day. Ordered by each training's first session,
    /// then name. A training whose amounts are all zero gets no form.
    /// `sport` limits the forms to that Sportart's trainings, as the month's
    /// KostZ does; nil covers every sport.
    static func summaries(for person: PraeEligiblePerson, month: Int, year: Int, sport: String? = nil,
                          in context: ModelContext) -> [PraeMonthSummary] {
        let membershipIDs = Set(person.membershipIDs)
        let calendar = Calendar.current
        // Fetches everything and filters in plain Swift rather than a
        // #Predicate closure — this app has no existing precedent for
        // relationship-path traversal (attendance.membership.id) or
        // Array.contains inside a #Predicate, and an Attendance table is
        // small enough (one club) that a client-side filter costs nothing.
        // Sorted because a fetch has no order of its own.
        let attendances = ((try? context.fetch(FetchDescriptor<Attendance>())) ?? [])
            .filter { $0.attended && $0.event.kind == "training" && membershipIDs.contains($0.membership.id)
                && (sport == nil || $0.event.sport == sport) }
            .sorted { ($0.event.startDate, $0.event.title) < ($1.event.startDate, $1.event.title) }

        var titles: [String] = []
        var amountsByTitle: [String: [Int: Double]] = [:]
        var personDayTotals: [Int: Double] = [:]
        for attendance in attendances {
            let components = calendar.dateComponents([.day, .month, .year], from: attendance.event.startDate)
            guard components.month == month, components.year == year, let day = components.day,
                  let amount = attendance.praeAmount else { continue }
            let title = attendance.event.title
            if amountsByTitle[title] == nil {
                titles.append(title)
            }
            amountsByTitle[title, default: [:]][day, default: 0] += amount
            personDayTotals[day, default: 0] += amount
        }

        return titles.compactMap { title in
            let amounts = amountsByTitle[title] ?? [:]
            let entries = amounts.keys.sorted().map { PraeDayEntry(day: $0, amount: amounts[$0] ?? 0, purpose: title) }
            let summary = PraeMonthSummary(person: person, month: month, year: year, entries: entries,
                                           trainingName: title, personDayTotals: personDayTotals)
            return summary.total > 0 ? summary : nil
        }
    }

    /// A single tournament's PRAE deployment days for one person, one summary
    /// per calendar month the tournament touches, in date order. Read straight
    /// from `tournament.attendances` — no ModelContext fetch needed, mirroring
    /// KostZCalculator.summary(for tournament:).
    ///
    /// `Attendance.praeAmount` is entered once for the whole tournament (see
    /// TournamentDetailView's Anwesenheit section, whose picker caps the
    /// total at `dailyCap * tournament.dayCount`), so a multi-day
    /// tournament's amount is split across every day the tournament spans
    /// (see `spreadEvenly`) rather than attributed entirely to the start
    /// date — matching the Sport Austria form's one-entry-per-deployment-day
    /// convention and keeping each day within `dailyCap` by construction.
    /// Only then are the days grouped by month, so the months add up to
    /// exactly the entered amount. A month whose days got nothing has no form.
    static func summaries(for person: PraeEligiblePerson, tournament: Tournament) -> [PraeTournamentSummary] {
        let membershipIDs = Set(person.membershipIDs)
        let attendances = tournament.attendances.filter {
            $0.attended && $0.praeAmount != nil && membershipIDs.contains($0.membership.id)
        }

        let calendar = Calendar.current
        let tournamentDays: [Date] = (0..<tournament.dayCount).compactMap {
            calendar.date(byAdding: .day, value: $0, to: calendar.startOfDay(for: tournament.startDate))
        }

        struct YearMonth: Hashable, Comparable {
            let year: Int
            let month: Int
            static func < (lhs: YearMonth, rhs: YearMonth) -> Bool { (lhs.year, lhs.month) < (rhs.year, rhs.month) }
        }

        var amountsByMonth: [YearMonth: [Int: Double]] = [:]
        for attendance in attendances {
            guard let amount = attendance.praeAmount, !tournamentDays.isEmpty else { continue }
            let perDayAmounts = spreadEvenly(amount, across: tournamentDays.count)
            for (date, dayAmount) in zip(tournamentDays, perDayAmounts) {
                let components = calendar.dateComponents([.day, .month, .year], from: date)
                guard let year = components.year, let month = components.month, let day = components.day else { continue }
                amountsByMonth[YearMonth(year: year, month: month), default: [:]][day, default: 0] += dayAmount
            }
        }

        let spansSeveralMonths = amountsByMonth.count > 1
        return amountsByMonth.keys.sorted().compactMap { key in
            let amounts = amountsByMonth[key] ?? [:]
            let entries = amounts.keys.sorted().map { PraeDayEntry(day: $0, amount: amounts[$0] ?? 0, purpose: tournament.title) }
            let summary = PraeTournamentSummary(person: person, tournament: tournament, entries: entries,
                                                month: key.month, year: key.year, spansSeveralMonths: spansSeveralMonths)
            return summary.total > 0 ? summary : nil
        }
    }

    /// Splits `amount` across `dayCount` days in whole euros — never a
    /// fractional/comma amount per day, since PRAE is a form field, not a
    /// bank transfer. When `amount` doesn't divide evenly, every day gets
    /// the rounded-down share except the middle day, which absorbs the
    /// whole remainder, so the days still sum to exactly `amount` (e.g. €100
    /// over 3 days → €33/€34/€33, not €33.33 each). "Middle" is `dayCount /
    /// 2` (0-indexed, integer division) — for an even day count that's the
    /// day right after the true center (e.g. day 2 of a 2-day tournament),
    /// there being no single middle day to pick.
    static func spreadEvenly(_ amount: Double, across dayCount: Int) -> [Double] {
        guard dayCount > 0 else { return [] }
        guard dayCount > 1 else { return [amount] }
        let lowerShare = (amount / Double(dayCount)).rounded(.down)
        let middleShare = amount - lowerShare * Double(dayCount - 1)
        let middleIndex = dayCount / 2
        return (0..<dayCount).map { $0 == middleIndex ? middleShare : lowerShare }
    }
}
