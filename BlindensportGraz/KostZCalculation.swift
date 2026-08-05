import Foundation
import SwiftData

/// One eligible person's summed amount for the requested month — see
/// KostZMonthSummary. Reuses PraeEligiblePerson (same coach/assistant
/// dedup-by-person logic as PraeCalculation.swift) rather than inventing a
/// second person model.
struct KostZPersonAmount: Identifiable {
    var id: UUID { person.id }
    let person: PraeEligiblePerson
    let amount: Double
}

/// One calendar month's total Trainer:innen-/Helfer:innen honoraria across
/// EVERY Training (NOT Tournaments — see KostZCalculator.summary(month:...)'s
/// doc comment) — this is club-wide across trainings, not per-person, since
/// the Sport Austria "KostZ" form is a single funding-accounting document per
/// accounting period, unlike PRAE's per-recipient form.
struct KostZMonthSummary {
    let month: Int
    let year: Int
    let personAmounts: [KostZPersonAmount] // sorted by displayName; amount > 0 only

    var total: Double { personAmounts.reduce(0) { $0 + $1.amount } }
    var personCount: Int { personAmounts.count }
}

/// One tournament's total Trainer:innen-/Helfer:innen honoraria, scoped to
/// just that tournament's own Attendance.praeAmount records — see
/// KostZCalculator.summary(for tournament:...).
struct KostZTournamentSummary {
    let tournament: Tournament
    let personAmounts: [KostZPersonAmount] // sorted by displayName; amount > 0 only

    var total: Double { personAmounts.reduce(0) { $0 + $1.amount } }
    var personCount: Int { personAmounts.count }
}

/// Computes the totals that feed the KostZ (Kostenzusammenstellung) form's
/// "HONORARE / VERGÜTUNGEN" line — see KostZExport.swift for where that
/// value gets patched into the template. KostZ is now created from two
/// different places with two different scopes (moved out of a single
/// club-wide-per-month screen): a tournament's own KostZ (see
/// summary(for tournament:)) is filed per event, using that tournament's own
/// PRAE deployments as its cost basis, so the monthly form below is
/// restricted to Training attendances only — otherwise a tournament's
/// honoraria would be counted twice, once on its own KostZ and again on the
/// month it falls in.
enum KostZCalculator {
    static func summary(month: Int, year: Int, allMemberships: [TeamMembership], in context: ModelContext) -> KostZMonthSummary {
        let eligible = PraeCalculator.eligiblePeople(from: allMemberships)
        var personByMembershipID: [UUID: PraeEligiblePerson] = [:]
        for person in eligible {
            for membershipID in person.membershipIDs {
                personByMembershipID[membershipID] = person
            }
        }

        // Fetch-all-then-filter-in-Swift, matching PraeCalculator.summary's
        // established convention (see its doc comment) rather than a
        // #Predicate with relationship-path traversal.
        let allAttendances = (try? context.fetch(FetchDescriptor<Attendance>())) ?? []
        let calendar = Calendar.current

        var amountByPersonID: [UUID: Double] = [:]
        for attendance in allAttendances {
            guard attendance.attended, let amount = attendance.praeAmount,
                  attendance.event.kind == "training",
                  let person = personByMembershipID[attendance.membership.id] else { continue }
            let components = calendar.dateComponents([.month, .year], from: attendance.event.startDate)
            guard components.month == month, components.year == year else { continue }
            amountByPersonID[person.id, default: 0] += amount
        }

        let personAmounts = eligible.compactMap { person -> KostZPersonAmount? in
            guard let amount = amountByPersonID[person.id], amount > 0 else { return nil }
            return KostZPersonAmount(person: person, amount: amount)
        }.sorted { ($0.person.lastName, $0.person.firstName) < ($1.person.lastName, $1.person.firstName) }

        return KostZMonthSummary(month: month, year: year, personAmounts: personAmounts)
    }

    /// A single tournament's HONORARE total, read straight from its own
    /// `tournament.attendances` (no month/year filtering, no cross-context
    /// fetch needed — unlike the monthly summary above, everything relevant
    /// is already reachable through the tournament itself).
    static func summary(for tournament: Tournament, allMemberships: [TeamMembership]) -> KostZTournamentSummary {
        let eligible = PraeCalculator.eligiblePeople(from: allMemberships)
        var personByMembershipID: [UUID: PraeEligiblePerson] = [:]
        for person in eligible {
            for membershipID in person.membershipIDs {
                personByMembershipID[membershipID] = person
            }
        }

        var amountByPersonID: [UUID: Double] = [:]
        for attendance in tournament.attendances {
            guard attendance.attended, let amount = attendance.praeAmount,
                  let person = personByMembershipID[attendance.membership.id] else { continue }
            amountByPersonID[person.id, default: 0] += amount
        }

        let personAmounts = eligible.compactMap { person -> KostZPersonAmount? in
            guard let amount = amountByPersonID[person.id], amount > 0 else { return nil }
            return KostZPersonAmount(person: person, amount: amount)
        }.sorted { ($0.person.lastName, $0.person.firstName) < ($1.person.lastName, $1.person.firstName) }

        return KostZTournamentSummary(tournament: tournament, personAmounts: personAmounts)
    }

    /// First day, last day, and total day count of the requested calendar
    /// month — used to fill KostZ's "ZEITRAUM: am ... bis ... = N TAGE"
    /// fields, matching TeilnehmerlisteExporter's day-count semantics.
    static func monthBounds(month: Int, year: Int) -> (start: Date, end: Date, dayCount: Int) {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1
        let calendar = Calendar.current
        let start = calendar.date(from: components) ?? .now
        let dayCount = calendar.range(of: .day, in: .month, for: start)?.count ?? 30
        let end = calendar.date(byAdding: .day, value: dayCount - 1, to: start) ?? start
        return (start, end, dayCount)
    }
}
