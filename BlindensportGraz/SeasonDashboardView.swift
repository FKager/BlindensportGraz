import SwiftUI
import SwiftData
import Charts

/// Season (= one calendar year) recap — architecture-review.md §5 (P2):
/// trainings/tournaments that year, overall attendance rate, total PRAE
/// paid, a monthly attendance trend, and a per-team breakdown. Reachable
/// from `TrainingsListView`'s "Berichte" menu, admin-only (financial data).
///
/// Read-only/visual — the counterpart to `SammelabrechnungSeasonView`, which
/// EXPORTS the same period's paperwork as a zip; this just shows it at a
/// glance. Extends `AttendanceTrends`' aggregation (via `SeasonDashboard`)
/// rather than re-deriving it.
struct SeasonDashboardView: View {
    // Intentionally unfiltered, admin-only screen — same convention as
    // SammelabrechnungSeasonView's identically-shaped @Query set.
    @Query private var trainings: [Training]
    @Query private var tournaments: [Tournament]
    @Query private var teams: [Team]
    @Query private var allAttendances: [Attendance]

    @State private var year = Calendar.current.component(.year, from: .now)

    private var summary: SeasonDashboard.Summary {
        SeasonDashboard.summary(year: year, trainings: trainings, tournaments: tournaments, attendances: allAttendances)
    }

    private var teamRates: [SeasonDashboard.TeamRate] {
        SeasonDashboard.teamRates(year: year, teams: teams, attendances: allAttendances)
    }

    fileprivate var monthlyPoints: [AttendanceRatePoint] {
        let yearAttendances = allAttendances.filter {
            Calendar.current.component(.year, from: $0.event.startDate) == year
        }
        return AttendanceTrends.monthlyRates(yearAttendances)
    }

    private var praeValue: String {
        summary.totalPraeAmount > 0 ? "\(Int(summary.totalPraeAmount)) €" : "0 €"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Saison") {
                    Stepper("Jahr: \(String(year))", value: $year, in: 2020...2100)
                }

                Section("Überblick") {
                    LabeledContent("Trainings", value: "\(summary.trainingsCount)")
                    LabeledContent("Turniere", value: "\(summary.tournamentsCount)")
                    LabeledContent("Anwesenheitsquote",
                                   value: summary.totalRecords == 0 ? "–" : "\(Int((summary.attendanceRate * 100).rounded()))%")
                    LabeledContent("PRAE gesamt", value: praeValue)
                }

                Section("Anwesenheitsquote pro Monat") {
                    if monthlyPoints.isEmpty {
                        Text("Für \(String(year)) liegen noch keine Anwesenheitsdaten vor.")
                            .foregroundStyle(.secondary)
                    } else {
                        Chart(monthlyPoints) { point in
                            BarMark(
                                x: .value("Monat", point.period, unit: .month),
                                y: .value("Quote", point.rate)
                            )
                            .foregroundStyle(.blue)
                            .accessibilityLabel(monthLabel(point.period))
                            .accessibilityValue("\(Int((point.rate * 100).rounded())) Prozent, \(point.attendedCount) von \(point.totalCount) anwesend")
                        }
                        .chartYScale(domain: 0...1)
                        .chartYAxis {
                            AxisMarks(values: [0, 0.25, 0.5, 0.75, 1.0]) { value in
                                AxisGridLine()
                                AxisValueLabel {
                                    if let rate = value.as(Double.self) {
                                        Text("\(Int(rate * 100))%")
                                    }
                                }
                            }
                        }
                        .frame(height: 200)
                        // See AttendanceTrendsView's identical comment — this
                        // app's primary usage mode is VoiceOver, so a chart
                        // no one using it can read isn't acceptable here.
                        .accessibilityChartDescriptor(self)
                        .accessibilityLabel("Anwesenheitsquote pro Monat, Saison \(String(year))")
                    }
                }

                if !teamRates.isEmpty {
                    Section("Anwesenheit pro Team") {
                        ForEach(teamRates) { entry in
                            HStack {
                                Text(entry.team.name)
                                Spacer()
                                Text("\(Int((entry.rate * 100).rounded()))%")
                                    .foregroundStyle(.secondary)
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("\(entry.team.name): \(Int((entry.rate * 100).rounded())) Prozent, \(entry.attendedCount) von \(entry.totalCount) anwesend")
                        }
                    }
                }
            }
            .navigationTitle("Saison-Übersicht")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func monthLabel(_ date: Date) -> String {
        date.formatted(.dateTime.month(.wide).year())
    }
}

extension SeasonDashboardView: AXChartDescriptorRepresentable {
    func makeChartDescriptor() -> AXChartDescriptor {
        let points = monthlyPoints
        let xAxis = AXNumericDataAxisDescriptor(
            title: "Monat",
            range: 0...Double(max(points.count - 1, 0)),
            gridlinePositions: []
        ) { index in
            guard points.indices.contains(Int(index)) else { return "" }
            return monthLabel(points[Int(index)].period)
        }
        let yAxis = AXNumericDataAxisDescriptor(
            title: "Anwesenheitsquote",
            range: 0...1,
            gridlinePositions: [0, 0.25, 0.5, 0.75, 1.0]
        ) { rate in "\(Int((rate * 100).rounded())) Prozent" }

        let series = AXDataSeriesDescriptor(
            name: "Anwesenheitsquote pro Monat, Saison \(String(year))",
            isContinuous: false,
            dataPoints: points.enumerated().map { index, point in
                AXDataPoint(x: Double(index), y: point.rate,
                            additionalValues: [], label: monthLabel(point.period))
            }
        )

        return AXChartDescriptor(
            title: "Anwesenheitsquote pro Monat, Saison \(String(year))",
            summary: nil,
            xAxis: xAxis,
            yAxis: yAxis,
            additionalAxes: [],
            series: [series]
        )
    }
}
