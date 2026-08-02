import SwiftUI
import SwiftData

/// Admin-only screen (see TrainingsListView's calendar-badge toolbar button)
/// that exports one team's half-year training attendance register — Sport
/// Austria's Trainingsfrequenzliste is filed per federal reporting period
/// (1. Halbjahr Jänner–Juni, 2. Halbjahr Juli–Dezember), not per calendar
/// month. Unlike KostZCalculationView (club-wide, no team picker), the
/// Trainingsfrequenzliste is inherently per-team — the original form has one
/// "Verein/LV" + "Sportart" line, i.e. one homogenous group per sheet — so
/// this adds a Team picker on top of the Halbjahr/Jahr picker. Deliberately
/// reachable only from the Trainings tab (not AccountView, where PRAE/KostZ
/// still live) since it's specifically about training attendance, unlike
/// PRAE/KostZ which cover all deployment types. Self-contained NavigationStack
/// + dismiss button since it's sheet-presented, matching
/// KostZCalculationView/PraeCalculationView.
struct TrainingsfrequenzlisteView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Team.name) private var teams: [Team]

    @State private var selectedTeamID: UUID?
    @State private var halfYear: HalfYear = Calendar.current.component(.month, from: .now) <= 6 ? .first : .second
    @State private var year = Calendar.current.component(.year, from: .now)
    @State private var exportURL: URL?
    @State private var exportError: String?

    private var selectedTeam: Team? {
        teams.first { $0.id == selectedTeamID } ?? teams.first
    }

    private var summary: TrainingsfrequenzlisteSummary? {
        guard let team = selectedTeam else { return nil }
        return TrainingsfrequenzlisteCalculator.summary(team: team, halfYear: halfYear, year: year, in: modelContext)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Team & Zeitraum") {
                    if teams.isEmpty {
                        Text("Noch kein Team angelegt.")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Team", selection: $selectedTeamID) {
                            ForEach(teams) { team in
                                Text(team.name).tag(Optional(team.id))
                            }
                        }
                        Picker("Zeitraum", selection: $halfYear) {
                            ForEach(HalfYear.allCases) { half in
                                Text(half.label).tag(half)
                            }
                        }
                        Stepper("Jahr: \(String(year))", value: $year, in: 2020...2100)
                    }
                }

                if let summary {
                    Section("Trainingstage") {
                        if summary.trainingDates.isEmpty {
                            Text("Keine Trainings in diesem Zeitraum für dieses Team.")
                                .foregroundStyle(.secondary)
                        } else {
                            LabeledContent("Anzahl Trainingstage", value: "\(summary.trainingDates.count)")
                            LabeledContent("Anzahl Mitglieder", value: "\(summary.people.count)")
                        }
                    }

                    Section("Export") {
                        Text("Bildet die Original-Trainingsfrequenzliste (Nr./Vorname/Nachname/Verein je Zeile, ein Trainingstag je Spalte, „j“/„n“ je Zelle, Zeilensumme „ges. TL“) mit den erfassten Anwesenheiten nach — ohne zusätzliche Spalten gegenüber dem Original.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        // ShareLink, not a Button-triggered sheet — see KostZCalculationView's
                        // doc comment for why (nested-sheet VoiceOver freeze, cerebrum.md 2026-07-18).
                        if let exportURL {
                            ShareLink(item: exportURL) {
                                Label("Trainingsfrequenzliste exportieren", systemImage: "doc.fill")
                            }
                        } else {
                            Label("Trainingsfrequenzliste wird vorbereitet …", systemImage: "doc.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Trainingsfrequenzliste")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
            .alert("Export fehlgeschlagen", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(exportError ?? "")
            }
            .task(id: "\(selectedTeam?.id.uuidString ?? "")-\(halfYear.rawValue)-\(year)") {
                exportURL = nil
                guard let summary else { return }
                do {
                    exportURL = try TrainingsfrequenzlisteExporter.export(summary: summary)
                } catch {
                    exportError = error.localizedDescription
                }
            }
        }
    }
}
