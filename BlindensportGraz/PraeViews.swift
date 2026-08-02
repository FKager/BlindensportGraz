import SwiftUI
import SwiftData

/// Admin-only screen (see TrainingsListView/TournamentsListView's "Berichte"
/// toolbar menu) that picks a helper/coach + calendar month and shows the
/// resulting PRAE deployment days computed from Attendance.praeAmount
/// entries — see PraeCalculation.swift for the underlying logic and
/// PraeExport.swift for the two export options. PRAE deployments happen at
/// both trainings and tournaments (coach/assistant Attendance.praeAmount is
/// entered in both TrainingDetailView and TournamentDetailView), so this is
/// reachable from either list, not just one — unlike Trainingsfrequenzliste,
/// which is training-specific. Self-contained NavigationStack + dismiss
/// button since it's sheet-presented, not tab-hosted (matches MembersListView).
struct PraeCalculationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var allMemberships: [TeamMembership]

    @State private var selectedPersonID: UUID?
    @State private var month = Calendar.current.component(.month, from: .now)
    @State private var year = Calendar.current.component(.year, from: .now)
    @State private var mainFormURL: URL?
    @State private var darstellungURL: URL?
    @State private var exportError: String?

    private var eligiblePeople: [PraeEligiblePerson] {
        PraeCalculator.eligiblePeople(from: allMemberships)
    }

    private var selectedPerson: PraeEligiblePerson? {
        eligiblePeople.first { $0.id == selectedPersonID }
    }

    private var summary: PraeMonthSummary? {
        guard let person = selectedPerson else { return nil }
        return PraeCalculator.summary(for: person, month: month, year: year, in: modelContext)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Helfer:in / Trainer:in") {
                    if eligiblePeople.isEmpty {
                        Text("Keine Teammitglieder mit Rolle „Trainer:in“ oder „Helfer:in“ gefunden.")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Person", selection: $selectedPersonID) {
                            Text("Bitte wählen").tag(UUID?.none)
                            ForEach(eligiblePeople) { person in
                                Text(person.displayName).tag(Optional(person.id))
                            }
                        }
                    }
                    Picker("Monat", selection: $month) {
                        ForEach(1...12, id: \.self) { m in
                            Text(monthName(m)).tag(m)
                        }
                    }
                    Stepper("Jahr: \(String(year))", value: $year, in: 2020...2100)
                }

                if let summary {
                    Section("Einsatztage") {
                        if summary.entries.isEmpty {
                            Text("Keine Einsatztage mit hinterlegtem PRAE-Betrag in diesem Monat.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(summary.entries) { entry in
                                HStack {
                                    Text("\(entry.day).")
                                        .frame(width: 32, alignment: .leading)
                                    Text(entry.purpose)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                    Spacer()
                                    Text(entry.amount, format: .currency(code: "EUR"))
                                        .foregroundStyle(entry.amount > PraeCalculator.dailyCap ? .red : .primary)
                                }
                            }
                            HStack {
                                Text("Gesamt").bold()
                                Spacer()
                                Text(summary.total, format: .currency(code: "EUR"))
                                    .bold()
                                    .foregroundStyle(summary.exceedsMonthlyCap ? .red : .primary)
                            }
                            if summary.exceedsMonthlyCap {
                                Label("Monatliche Höchstgrenze von € 720,- überschritten.", systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                            if !summary.daysExceedingDailyCap.isEmpty {
                                Label("Tageshöchstsatz von € 120,- überschritten an Tag(en): \(summary.daysExceedingDailyCap.map(String.init).joined(separator: ", ")).",
                                      systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }
                    }

                    Section("Export") {
                        Text("Das offizielle Hauptformular (Name/Adresse vorausgefüllt) muss weiterhin von Hand um Monat/Jahr, Tagesbeträge und die persönliche Unterschrift ergänzt werden — siehe Einsatztage oben.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        // ShareLink, not a Button-triggered sheet — this view
                        // is itself already sheet-presented from AccountView,
                        // and nesting a second sheet on top of a sheet is a
                        // known VoiceOver-freeze pattern in this app (see
                        // cerebrum.md's 2026-07-18 entries). Files are
                        // generated eagerly in .task below instead, matching
                        // MemberListView's proven-safe export pattern.
                        if let mainFormURL {
                            ShareLink(item: mainFormURL) {
                                Label("PRAE-Formular exportieren", systemImage: "doc.fill")
                            }
                        } else {
                            Label("PRAE-Formular wird vorbereitet …", systemImage: "doc.fill")
                                .foregroundStyle(.secondary)
                        }
                        if let darstellungURL {
                            ShareLink(item: darstellungURL) {
                                Label("Darstellung der Verwendungszwecke exportieren", systemImage: "tablecells.fill")
                            }
                        } else {
                            Label("Darstellung wird vorbereitet …", systemImage: "tablecells.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("PRAE-Berechnung")
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
            .task(id: selectedPersonID) {
                mainFormURL = nil
                guard let person = selectedPerson else { return }
                do {
                    mainFormURL = try PraeExporter.exportMainForm(person: person)
                } catch {
                    exportError = error.localizedDescription
                }
            }
            .task(id: "\(selectedPersonID?.uuidString ?? "")-\(month)-\(year)") {
                darstellungURL = nil
                guard let summary, !summary.entries.isEmpty else { return }
                do {
                    darstellungURL = try PraeExporter.exportDarstellung(summary: summary)
                } catch {
                    exportError = error.localizedDescription
                }
            }
        }
    }

    private func monthName(_ month: Int) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_AT")
        return formatter.monthSymbols[month - 1].capitalized
    }
}
