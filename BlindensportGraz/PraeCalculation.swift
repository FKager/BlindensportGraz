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
    let membershipIDs: [UUID]
    // Carried through from the representative membership so exporters can
    // fill in name/address without a second lookup — only Member has an
    // address (User doesn't), so a person backed only by a registered
    // account exports with a blank Wohnanschrift on the PRAE form.
    let member: Member?

    static func == (lhs: PraeEligiblePerson, rhs: PraeEligiblePerson) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
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

    var total: Double { entries.reduce(0) { $0 + $1.amount } }
    var exceedsMonthlyCap: Bool { total > PraeCalculator.monthlyCap }
    var daysExceedingDailyCap: [Int] { entries.filter { $0.amount > PraeCalculator.dailyCap }.map(\.day) }
}

/// Computes PRAE ("Pauschale Reiseaufwandsentschädigung") deployment days
/// and amounts for one helper/coach from this app's existing Attendance
/// records — see Attendance.praeAmount. Legal caps per Sport Austria's
/// official "Aufzeichnung über Einsätze..." form (Stand: 10/2023): max
/// €120 per Einsatztag (deployment day), max €720 per calendar month.
/// These are flagged, not enforced — the admin can still exceed them
/// (e.g. genuinely paying above the tax-free threshold makes the excess
/// taxable, which is a legitimate choice, not necessarily a data-entry bug).
enum PraeCalculator {
    static let dailyCap = 120.0
    static let monthlyCap = 720.0

    /// Dedupes coach/assistant TeamMemberships (across every team, app-wide)
    /// down to one entry per underlying person, sorted by display name.
    static func eligiblePeople(from allMemberships: [TeamMembership]) -> [PraeEligiblePerson] {
        var byKey: [UUID: (name: String, ids: [UUID], member: Member?)] = [:]
        for membership in allMemberships where ["coach", "assistant"].contains(membership.role) {
            let key = membership.user?.id ?? membership.member?.id ?? membership.id
            if var existing = byKey[key] {
                existing.ids.append(membership.id)
                byKey[key] = existing
            } else {
                byKey[key] = (membership.displayName, [membership.id], membership.member)
            }
        }
        return byKey.map { key, value in
            PraeEligiblePerson(id: key, displayName: value.name, membershipIDs: value.ids, member: value.member)
        }.sorted { $0.displayName < $1.displayName }
    }

    /// Fetches every attended, PRAE-amount-set Attendance across the given
    /// person's memberships, filters to the requested calendar month, and
    /// groups by day — summing amounts if the person had more than one
    /// qualifying session on the same day (rare, but a real edge case:
    /// PRAE's own form only allows one amount per calendar day per person).
    static func summary(for person: PraeEligiblePerson, month: Int, year: Int, in context: ModelContext) -> PraeMonthSummary {
        let membershipIDs = Set(person.membershipIDs)
        // Fetches everything and filters in plain Swift rather than a
        // #Predicate closure — this app has no existing precedent for
        // relationship-path traversal (attendance.membership.id) or
        // Array.contains inside a #Predicate, and an Attendance table is
        // small enough (one club) that a client-side filter costs nothing.
        let allAttendances = (try? context.fetch(FetchDescriptor<Attendance>())) ?? []
        let attendances = allAttendances.filter {
            $0.attended && $0.praeAmount != nil && membershipIDs.contains($0.membership.id)
        }

        let calendar = Calendar.current
        var byDay: [Int: (amount: Double, purposes: [String])] = [:]
        for attendance in attendances {
            let components = calendar.dateComponents([.day, .month, .year], from: attendance.event.startDate)
            guard components.month == month, components.year == year, let day = components.day,
                  let amount = attendance.praeAmount else { continue }
            var entry = byDay[day] ?? (0, [])
            entry.amount += amount
            if !entry.purposes.contains(attendance.event.title) {
                entry.purposes.append(attendance.event.title)
            }
            byDay[day] = entry
        }

        let entries = byDay.keys.sorted().map { day -> PraeDayEntry in
            let value = byDay[day]!
            return PraeDayEntry(day: day, amount: value.amount, purpose: value.purposes.joined(separator: ", "))
        }
        return PraeMonthSummary(person: person, month: month, year: year, entries: entries)
    }
}
