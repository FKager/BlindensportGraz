import SwiftUI
import SwiftData
import Charts

/// Attendance-rate trend chart (audit.md Enhancement #6) — `Attendance`
/// records exist and sync correctly but had no aggregate/trend view
/// anywhere. Reachable from `TrainingsListView`'s "Berichte" toolbar menu,
/// gated to admin/coach (see that view's `canManageEvents`).
struct AttendanceTrendsView: View {
    @Query(sort: \Team.name) private var teams: [Team]
    @Query private var allAttendances: [Attendance]

    private enum Scope: String, CaseIterable, Identifiable {
        case team = "Team"
        case person = "Person"
        var id: String { rawValue }
    }

    @State private var scope: Scope = .team
    @State private var selectedTeamID: UUID?
    @State private var selectedMembershipID: UUID?

    private var selectedTeam: Team? {
        teams.first { $0.id == selectedTeamID } ?? teams.first
    }

    private var peopleInSelectedTeam: [TeamMembership] {
        (selectedTeam?.memberships ?? []).sortedByLastName()
    }

    private var points: [AttendanceRatePoint] {
        switch scope {
        case .team:
            guard let teamID = selectedTeam?.id else { return [] }
            return AttendanceTrends.monthlyRates(AttendanceTrends.records(allAttendances, forTeamID: teamID))
        case .person:
            guard let membershipID = selectedMembershipID ?? peopleInSelectedTeam.first?.id else { return [] }
            return AttendanceTrends.monthlyRates(AttendanceTrends.records(allAttendances, forMembershipID: membershipID))
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Bereich") {
                    Picker("Bereich", selection: $scope) {
                        ForEach(Scope.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityHint("Wählt, ob der Trend pro Team oder pro Person angezeigt wird.")

                    if teams.isEmpty {
                        Text("Keine Teams vorhanden.")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Team", selection: Binding(
                            get: { selectedTeamID ?? teams.first?.id },
                            set: { selectedTeamID = $0 }
                        )) {
                            ForEach(teams) { team in
                                Text(team.name).tag(Optional(team.id))
                            }
                        }

                        if scope == .person {
                            if peopleInSelectedTeam.isEmpty {
                                Text("Keine Mitglieder in diesem Team.")
                                    .foregroundStyle(.secondary)
                            } else {
                                Picker("Person", selection: Binding(
                                    get: { selectedMembershipID ?? peopleInSelectedTeam.first?.id },
                                    set: { selectedMembershipID = $0 }
                                )) {
                                    ForEach(peopleInSelectedTeam) { membership in
                                        Text(membership.displayName).tag(Optional(membership.id))
                                    }
                                }
                            }
                        }
                    }
                }

                Section("Anwesenheitsquote") {
                    if points.isEmpty {
                        ContentUnavailableView("Noch keine Daten",
                                                systemImage: "chart.line.uptrend.xyaxis",
                                                description: Text("Für diese Auswahl liegen noch keine Anwesenheitsdaten vor."))
                    } else {
                        Chart(points) { point in
                            LineMark(
                                x: .value("Monat", point.period, unit: .month),
                                y: .value("Quote", point.rate)
                            )
                            .symbol(.circle)
                            PointMark(
                                x: .value("Monat", point.period, unit: .month),
                                y: .value("Quote", point.rate)
                            )
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
                        .frame(height: 220)
                        // Swift Charts marks are silent to VoiceOver unless
                        // given a descriptor — this app's primary usage mode
                        // is VoiceOver (see cerebrum.md's standing User
                        // Preferences entry), so a chart no one using
                        // VoiceOver can read isn't acceptable here.
                        .accessibilityChartDescriptor(self)
                        .accessibilityLabel("Anwesenheitsquote pro Monat")
                    }
                }
            }
            .navigationTitle("Anwesenheitstrends")
        }
    }

    private func monthLabel(_ date: Date) -> String {
        date.formatted(.dateTime.month(.wide).year())
    }
}

extension AttendanceTrendsView: AXChartDescriptorRepresentable {
    func makeChartDescriptor() -> AXChartDescriptor {
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
            name: "Anwesenheitsquote pro Monat",
            isContinuous: true,
            dataPoints: points.enumerated().map { index, point in
                AXDataPoint(x: Double(index), y: point.rate,
                            additionalValues: [], label: monthLabel(point.period))
            }
        )

        return AXChartDescriptor(
            title: "Anwesenheitsquote pro Monat",
            summary: nil,
            xAxis: xAxis,
            yAxis: yAxis,
            additionalAxes: [],
            series: [series]
        )
    }
}
