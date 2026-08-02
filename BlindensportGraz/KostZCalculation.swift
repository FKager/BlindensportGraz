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
/// EVERY Training/Tournament — this is club-wide, not per-person, since the
/// Sport Austria "KostZ" form is a single funding-accounting document per
/// accounting period, unlike PRAE's per-recipient form.
struct KostZMonthSummary {
    let month: Int
    let year: Int
    let personAmounts: [KostZPersonAmount] // sorted by displayName; amount > 0 only

    var total: Double { personAmounts.reduce(0) { $0 + $1.amount } }
    var personCount: Int { personAmounts.count }
}

/// Computes the club-wide monthly total that feeds the KostZ
/// (Kostenzusammenstellung) form's "HONORARE / VERGÜTUNGEN" line — see
/// KostZExport.swift for where that value gets patched into the template.
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
