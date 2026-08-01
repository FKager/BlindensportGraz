import SwiftUI
import SwiftData

/// Admin-only screen (see AccountView's "KostZ-Berechnung" button) that
/// totals every coach/assistant Attendance.praeAmount across ALL
/// Trainings/Tournaments for a chosen calendar month and exports the Sport
/// Austria "KostZ" (Kostenzusammenstellung) cost-summary form with the
/// HONORARE/VERGÜTUNGEN line filled in. Unlike PraeCalculationView (one
/// person at a time), this is inherently club-wide — KostZ is a single
/// funding-accounting document per accounting period, not per recipient.
/// Self-contained NavigationStack + dismiss button since it's sheet-
/// presented, matching PraeCalculationView/MembersListView.
struct KostZCalculationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var allMemberships: [TeamMembership]

    @State private var month = Calendar.current.component(.month, from: .now)
    @State private var year = Calendar.current.component(.year, from: .now)
    @State private var exportURL: URL?
    @State private var exportError: String?

    private var summary: KostZMonthSummary {
        KostZCalculator.summary(month: month, year: year, allMemberships: allMemberships, in: modelContext)
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

                Section("Honorare Trainer:innen / Helfer:innen") {
                    if summary.personAmounts.isEmpty {
                        Text("Keine Einsätze mit hinterlegtem Betrag in diesem Monat.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(summary.personAmounts) { entry in
                            HStack {
                                Text(entry.person.displayName)
                                Spacer()
                                Text(entry.amount, format: .currency(code: "EUR"))
                            }
                        }
                        HStack {
                            Text("Gesamt").bold()
                            Spacer()
                            Text(summary.total, format: .currency(code: "EUR"))
                                .bold()
                        }
                        LabeledContent("Anzahl Personen", value: "\(summary.personCount)")
                    }
                }

                Section("Export") {
                    Text("Nur die Zeile „HONORARE / VERGÜTUNGEN“ sowie Zeitraum und Personenanzahl werden vorausgefüllt — alle übrigen Kostenarten, Beilagen-Nummern und der Ort müssen weiterhin von Hand ergänzt werden.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    // ShareLink, not a Button-triggered sheet — this view is
                    // itself already sheet-presented from AccountView, and
                    // nesting a second sheet on top of a sheet is a known
                    // VoiceOver-freeze pattern in this app (see
                    // cerebrum.md's 2026-07-18 entries). File is generated
                    // eagerly in .task below, matching PraeCalculationView.
                    if let exportURL {
                        ShareLink(item: exportURL) {
                            Label("KostZ-Formular exportieren", systemImage: "doc.fill")
                        }
                    } else {
                        Label("KostZ-Formular wird vorbereitet …", systemImage: "doc.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("KostZ-Berechnung")
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
            .task(id: "\(month)-\(year)") {
                exportURL = nil
                do {
                    exportURL = try KostZExporter.export(summary: summary)
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
