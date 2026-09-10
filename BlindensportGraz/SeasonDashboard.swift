import Foundation

/// Aggregate season stats — architecture-review.md §5 (P2). "Season" here
/// means one calendar year, the same convention
/// `SammelabrechnungExporter.exportSeason` already established (every
/// month's + every tournament's paperwork for `year`); this is the visual,
/// read-only counterpart to that export screen, not a replacement for it.
///
/// Pure aggregation over `Training`/`Tournament`/`Attendance` — no UI/Charts
/// dependency, so it's unit-testable independent of chart rendering, same
/// split as `AttendanceTrends`. `SeasonDashboardView` is the only caller; it
/// does the SwiftData fetch and hands this plain arrays. Deliberately reuses
/// `AttendanceTrends.records(forTeamID:)`/`.monthlyRates` rather than
/// duplicating that filtering logic.
enum SeasonDashboard {
    struct Summary: Equatable {
        let year: Int
        let trainingsCount: Int
        let tournamentsCount: Int
        let attendedCount: Int
        let totalRecords: Int
        /// Sum of every `Attendance.praeAmount` for the season — the same
        /// per-record field the Training/Tournament detail views' own
        /// "Gesamtkosten" already total, just across the whole year instead
        /// of one event.
        let totalPraeAmount: Double

        var attendanceRate: Double {
            totalRecords == 0 ? 0 : Double(attendedCount) / Double(totalRecords)
        }
    }

    struct TeamRate: Identifiable {
        let team: Team
        let attendedCount: Int
        let totalCount: Int
        var id: UUID { team.id }
        var rate: Double {
            totalCount == 0 ? 0 : Double(attendedCount) / Double(totalCount)
        }
    }

    static func summary(year: Int, trainings: [Training], tournaments: [Tournament],
                        attendances: [Attendance], calendar: Calendar = .current) -> Summary {
        let yearAttendances = attendances.filter { isIn(year, $0.event.startDate, calendar) }
        return Summary(
            year: year,
            trainingsCount: trainings.filter { isIn(year, $0.startDate, calendar) }.count,
            tournamentsCount: tournaments.filter { isIn(year, $0.startDate, calendar) }.count,
            attendedCount: yearAttendances.filter(\.attended).count,
            totalRecords: yearAttendances.count,
            totalPraeAmount: yearAttendances.compactMap(\.praeAmount).reduce(0, +)
        )
    }

    /// One attendance rate per team for `year`, sorted by team name. A team
    /// with no attendance records at all that year is omitted rather than
    /// shown as a misleading 0%.
    static func teamRates(year: Int, teams: [Team], attendances: [Attendance],
                          calendar: Calendar = .current) -> [TeamRate] {
        teams.sorted { $0.name < $1.name }.compactMap { team in
            let records = AttendanceTrends.records(attendances, forTeamID: team.id)
                .filter { isIn(year, $0.event.startDate, calendar) }
            guard !records.isEmpty else { return nil }
            return TeamRate(team: team, attendedCount: records.filter(\.attended).count, totalCount: records.count)
        }
    }

    private static func isIn(_ year: Int, _ date: Date, _ calendar: Calendar) -> Bool {
        calendar.component(.year, from: date) == year
    }
}
