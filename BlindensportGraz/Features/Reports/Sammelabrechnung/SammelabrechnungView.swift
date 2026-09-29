import SwiftUI
import SwiftData

/// Admin-only screen (see TrainingsListView's "Berichte" toolbar menu) that
/// bundles a whole calendar month's PRAE/KostZ paperwork into one .zip —
/// see SammelabrechnungExporter's doc comment for exactly what's included.
/// Same month/year picker as KostZCalculationView (this is the club-wide,
/// month-scoped counterpart, not per-person), and the same eager-export-via-
/// `.task`-then-`ShareLink` pattern as every other export screen in this app
/// (never a Button-triggered second sheet — see cerebrum.md's 2026-07-18
/// VoiceOver-freeze entries). A KostZ toggle plus one PRAE (Formular +
/// Darstellung) toggle per eligible helper — all pre-selected by default —
/// mirror SammelabrechnungTournamentView's identical "Enthaltene Teile"/
/// per-helper PRAE selection; there's no TeilnehmerInnenliste toggle here
/// since that's tournament-only paperwork (Trainings file the
/// Trainingsfrequenzliste separately instead, not part of this bundle).
struct SammelabrechnungView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    // Intentionally unfiltered (audit.md SwiftData & CloudKit Finding 6):
    // `SammelabrechnungExporter` feeds `allMemberships` straight into
    // `KostZCalculator.summary`/`PraeCalculator.eligiblePeople`, which
    // filters to `role.isHelfer`. A `#Predicate` scoping to coach/assistant
    // was tried — see `KostZCalculationView`'s identical @Query comment
    // (KostZCalculationView.swift) for why it compiles but crashes
    // at runtime against `MembershipRole`, a custom `@Model`-stored enum.
    @Query private var allMemberships: [TeamMembership]

    @State private var month = Calendar.current.component(.month, from: .now)
    @State private var year = Calendar.current.component(.year, from: .now)
    @State private var includeKostZ = true
    // Which PraeEligiblePerson.id's PRAE (Formular + Darstellung) to
    // include — seeded to "everyone" the first time personAmounts is known
    // for a given month/year (see .onChange/.onAppear below), same pattern
    // as SammelabrechnungTournamentView.selectedPraePersonIDs.
    @State private var selectedPraePersonIDs: Set<UUID> = []
    @State private var seededPraeSelectionKey: String?
    @State private var exportURL: URL?
    @State private var exportError: String?

    private var kostZSummary: KostZMonthSummary {
        KostZCalculator.summary(month: month, year: year, allMemberships: allMemberships, in: modelContext)
    }

    // Only the helpers selected in the per-helper PRAE list, each mapped to
    // a PraeMonthSummary — no separate eligibility computation beyond that
    // selection, see SammelabrechnungExporter's doc comment.
    private var praeSummaries: [PraeMonthSummary] {
        kostZSummary.personAmounts
            .filter { selectedPraePersonIDs.contains($0.person.id) }
            .map { PraeCalculator.summary(for: $0.person, month: month, year: year, in: modelContext) }
    }

    private var hasSelectedParts: Bool {
        includeKostZ || !praeSummaries.isEmpty
    }

    private func praeBinding(for personID: UUID) -> Binding<Bool> {
        Binding(
            get: { selectedPraePersonIDs.contains(personID) },
            set: { isOn in
                if isOn { selectedPraePersonIDs.insert(personID) } else { selectedPraePersonIDs.remove(personID) }
            }
        )
    }

    // Re-runs the export whenever a toggle/selection changes or the
    // underlying data does. selectedPraePersonIDs is sorted before joining
    // so the id is stable regardless of Set iteration order.
    private var exportTaskID: String {
        let praeIDs = selectedPraePersonIDs.map(\.uuidString).sorted().joined(separator: ",")
        return "\(month)-\(year)-\(includeKostZ)-\(praeIDs)"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Zeitraum") {
                    Picker("Monat", selection: $month) {
                        ForEach(1...12, id: \.self) { m in
                            Text(monthName(m)).tag(m)
                        }
                    }
                    Stepper("Jahr: \(String(year))", value: $year, in: 2020...2100)
                }

                Section("Enthaltene Teile") {
                    Toggle("KostZ-Formular", isOn: $includeKostZ)
                }

                Section("PRAE (Formular + Darstellung)") {
                    if kostZSummary.personAmounts.isEmpty {
                        Text("Keine Trainer:innen/Helfer:innen mit hinterlegtem PRAE-Betrag in diesem Monat.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(kostZSummary.personAmounts) { entry in
                            Toggle(entry.person.displayName, isOn: praeBinding(for: entry.person.id))
                        }
                    }
                }

                Section("Export") {
                    Text("Bündelt die ausgewählten Teile — KostZ-Formular sowie PRAE-Formular und Darstellung der ausgewählten Trainer:innen/Helfer:innen — als ZIP-Datei.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !hasSelectedParts {
                        Text("Bitte mindestens einen Teil auswählen.")
                            .foregroundStyle(.secondary)
                    } else if let exportURL {
                        ShareLink(item: exportURL) {
                            Label("Sammelabrechnung exportieren", systemImage: "doc.zipper")
                        }
                    } else {
                        Label("Sammelabrechnung wird vorbereitet …", systemImage: "doc.zipper")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Sammelabrechnung")
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
            .onAppear { seedPraeSelectionIfNeeded() }
            .onChange(of: "\(month)-\(year)") { seedPraeSelectionIfNeeded() }
            .task(id: exportTaskID) {
                exportURL = nil
                guard hasSelectedParts else { return }
                do {
                    exportURL = try SammelabrechnungExporter.export(
                        kostZ: includeKostZ ? kostZSummary : nil, praeSummaries: praeSummaries)
                } catch {
                    exportError = error.localizedDescription
                }
            }
        }
    }

    // Pre-selects every eligible helper's PRAE for the current month/year —
    // runs on first appearance and again whenever month/year changes to a
    // period not yet seeded (switching the picker reveals a different
    // personAmounts list, which should itself start fully selected, not
    // carry over whatever was picked for the previous month). Runs
    // synchronously before the .task above, so the very first export for a
    // given period already reflects "all pre-selected".
    private func seedPraeSelectionIfNeeded() {
        let key = "\(month)-\(year)"
        guard seededPraeSelectionKey != key else { return }
        selectedPraePersonIDs = Set(kostZSummary.personAmounts.map(\.person.id))
        seededPraeSelectionKey = key
    }

    private func monthName(_ month: Int) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_AT")
        return formatter.monthSymbols[month - 1].capitalized
    }
}
