import SwiftUI
import SwiftData

/// Admin-only screen (see TrainingsListView's "Berichte" toolbar menu,
/// alongside PRAE-Berechnung/KostZ-Berechnung — folded in there per user
/// request, previously its own standalone toolbar button) that exports one
/// training sport's attendance register — Sport Austria's
/// Trainingsfrequenzliste is filed per federal reporting period (1. Halbjahr
/// Jänner–Juni, 2. Halbjahr Juli–Dezember); the chosen month ends the list
/// early, from the half year's start (Jänner or Juli) to that month's end —
/// the same list as the month's Sammelabrechnung. Unlike
/// KostZCalculationView (club-wide, no picker), the Trainingsfrequenzliste is
/// inherently per-sport — the original form has one "Verein/LV" + "Sportart"
/// line, i.e. one homogenous group per sheet — so this adds a Sportart picker
/// on top of the Monat/Jahr picker. Scoped by `Training.sport`, not by a
/// hand-picked team (a sport like "Torball" can be trained by several teams
/// at once, e.g. Damen + Herren) — the roster itself still comes from
/// whichever teams are actually assigned to trainings of that sport,
/// unchanged from before. Deliberately reachable only from the Trainings tab
/// (not AccountView, where nothing report-related lives anymore, or
/// TournamentsListView, which has no notion of "sport" attendance) since it's
/// specifically about training attendance, unlike PRAE/KostZ which cover all
/// deployment types. Self-contained NavigationStack + dismiss button since
/// it's sheet-presented, matching KostZCalculationView/PraeCalculationView.
struct TrainingsfrequenzlisteView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    // No query-level `sort:` — `startDate` is inherited from SportEvent and
    // SwiftData traps on an inherited-property sort key path in Release builds
    // (bug-352). Only used for a Set of sport names here, so order is moot.
    @Query private var trainings: [Training]

    @State private var selectedSport: String?
    @State private var month = Calendar.current.component(.month, from: .now)
    @State private var year = Calendar.current.component(.year, from: .now)
    @State private var exportURL: URL?
    @State private var exportError: String?

    // Distinct Training.sport values across every training ever created —
    // "the list belongs to the type of training", not to a hand-picked team.
    private var availableSports: [String] {
        Array(Set(trainings.map(\.sport))).sorted()
    }

    private var sport: String? {
        availableSports.contains(selectedSport ?? "") ? selectedSport : availableSports.first
    }

    private var summary: TrainingsfrequenzlisteSummary? {
        guard let sport else { return nil }
        return TrainingsfrequenzlisteCalculator.seasonSummary(sport: sport, throughMonth: month, year: year, in: modelContext)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(heading: "Sportart & Zeitraum") {
                    if availableSports.isEmpty {
                        Text("Noch kein Training angelegt.")
                            .foregroundStyle(Theme.Palette.secondary)
                    } else {
                        Picker("Sportart", selection: $selectedSport) {
                            ForEach(availableSports, id: \.self) { sport in
                                Text(sport).tag(Optional(sport))
                            }
                        }
                        Picker("Monat", selection: $month) {
                            ForEach(1...12, id: \.self) { month in
                                Text(Self.monthName(month)).tag(month)
                            }
                        }
                        // Says right on focus which months the list covers
                        // (audit.md Accessibility Finding 9).
                        .accessibilityHint("Die Liste reicht vom Beginn des Halbjahres, Jänner oder Juli, bis zum Ende des gewählten Monats.")
                        NumberPicker("Jahr", value: $year, values: Array(2020...2100))
                        LabeledContent("Zeitraum", value: Self.period(throughMonth: month, year: year))
                    }
                }

                if let summary {
                    Section(heading: "Trainingstage") {
                        if summary.trainingDates.isEmpty {
                            Text("Keine Trainings in diesem Zeitraum für diese Sportart.")
                                .foregroundStyle(Theme.Palette.secondary)
                        } else {
                            LabeledContent("Anzahl Trainingstage", value: "\(summary.trainingDates.count)")
                            LabeledContent("Anzahl Mitglieder", value: "\(summary.people.count)")
                            if !summary.teams.isEmpty {
                                LabeledContent("Zugeordnete Teams", value: summary.teams.map(\.name).joined(separator: ", "))
                            }
                        }
                    }

                    Section(heading: "Export") {
                        Text("Bildet die Original-Trainingsfrequenzliste (Nr./Vorname/Nachname/Verein je Zeile, ein Trainingstag je Spalte, „j“/„n“ je Zelle, Zeilensumme „ges. TL“) mit den erfassten Anwesenheiten nach — ohne zusätzliche Spalten gegenüber dem Original.")
                            .font(.caption)
                            .foregroundStyle(Theme.Palette.secondary)
                        // ShareLink, not a Button-triggered sheet — see KostZCalculationView's
                        // doc comment for why (nested-sheet VoiceOver freeze, cerebrum.md 2026-07-18).
                        if let exportURL {
                            ShareLink(item: exportURL) {
                                Label("Trainingsfrequenzliste exportieren", systemImage: "doc.fill")
                            }
                        } else {
                            Label("Trainingsfrequenzliste wird vorbereitet …", systemImage: "doc.fill")
                                .foregroundStyle(Theme.Palette.secondary)
                        }
                        if let exportURL {
                            ReportPrintButton(title: "Trainingsfrequenzliste drucken", jobName: "Trainingsfrequenzliste") {
                                [exportURL]
                            }
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
            .alert("Export fehlgeschlagen", isPresented: Binding(isPresent: $exportError)) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(exportError ?? "")
            }
            .task(id: "\(sport ?? "")-\(month)-\(year)") {
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

    /// "März".
    static func monthName(_ month: Int) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "de_AT")
        return calendar.standaloneMonthSymbols[month - 1]
    }

    /// "Jänner bis März 2026", or "Juli 2026" for a half year's first month.
    static func period(throughMonth month: Int, year: Int) -> String {
        let first = month <= 6 ? 1 : 7
        let to = "\(monthName(month)) \(String(year))"
        return first == month ? to : "\(monthName(first)) bis \(to)"
    }
}
