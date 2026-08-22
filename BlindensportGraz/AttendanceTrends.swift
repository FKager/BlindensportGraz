import Foundation

/// One bucket in an attendance-rate trend — audit.md Enhancement #6.
/// `Identifiable`/`Equatable` for direct use as `Charts` mark data.
struct AttendanceRatePoint: Identifiable, Equatable {
    var id: Date { period }
    let period: Date
    let attendedCount: Int
    let totalCount: Int

    var rate: Double {
        totalCount == 0 ? 0 : Double(attendedCount) / Double(totalCount)
    }
}

/// Pure aggregation over `Attendance` records — no UI/Charts dependency, so
/// this is unit-testable independent of chart rendering (phase-15 spec).
/// `AttendanceTrendsView` is the only caller; it does the SwiftData fetch
/// and hands this plain `[Attendance]` arrays.
enum AttendanceTrends {
    /// Buckets `records` by calendar month (keyed off each record's
    /// `event.startDate`) and computes attended/total per month. Records
    /// are pre-filtered by the caller (by team and/or person) — this
    /// function only aggregates whatever it's given. Empty input yields an
    /// empty result (the "no data yet" case the UI renders explicitly,
    /// rather than a zero-rate/broken chart).
    static func monthlyRates(_ records: [Attendance], calendar: Calendar = .current) -> [AttendanceRatePoint] {
        guard !records.isEmpty else { return [] }
        let grouped = Dictionary(grouping: records) { record -> Date in
            calendar.dateInterval(of: .month, for: record.event.startDate)?.start ?? record.event.startDate
        }
        return grouped.map { month, recs in
            AttendanceRatePoint(period: month, attendedCount: recs.filter(\.attended).count, totalCount: recs.count)
        }.sorted { $0.period < $1.period }
    }

    /// Attendance records for one team, across all its members' events.
    static func records(_ all: [Attendance], forTeamID teamID: UUID) -> [Attendance] {
        all.filter { $0.membership.team.id == teamID }
    }

    /// Attendance records for one person's roster entry (`TeamMembership`,
    /// not `User`/`Member` directly — matches how `Attendance` links to
    /// membership, see that model's doc comment).
    static func records(_ all: [Attendance], forMembershipID membershipID: UUID) -> [Attendance] {
        all.filter { $0.membership.id == membershipID }
    }
}
