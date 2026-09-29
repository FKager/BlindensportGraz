import SwiftUI
import SwiftData

/// Admin-only screen (see TournamentDetailView's toolbar) that picks one of
/// the helpers/coaches actually deployed at this tournament and shows their
/// PRAE deployment days for just this event — the per-tournament
/// counterpart to PraeCalculationView's per-month one, mirroring
/// KostZTournamentCalculationView's relationship to KostZCalculationView.
/// No month/year picker: the tournament supplies its own period.
struct PraeTournamentCalculationView: View {
    let tournament: Tournament
    @Environment(\.dismiss) private var dismiss
    @Query private var allMemberships: [TeamMembership]

    @State private var selectedPersonID: UUID?
    @State private var mainFormURL: URL?
    @State private var darstellungURL: URL?
    @State private var exportError: String?

    // Only people with an actual (attended, PRAE-amounted) Attendance at
    // THIS tournament — no point offering every club-wide coach/helper in
    // the picker when only a handful were deployed at this one event.
    private var eligiblePeople: [PraeEligiblePerson] {
        let deployedMembershipIDs = Set(tournament.attendances
            .filter { $0.attended && $0.praeAmount != nil }
            .map { $0.membership.id })
        return PraeCalculator.eligiblePeople(from: allMemberships)
            .filter { person in person.membershipIDs.contains { deployedMembershipIDs.contains($0) } }
    }

    private var selectedPerson: PraeEligiblePerson? {
        eligiblePeople.first { $0.id == selectedPersonID }
    }

    private var summary: PraeTournamentSummary? {
        guard let person = selectedPerson else { return nil }
        return PraeCalculator.summary(for: person, tournament: tournament)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Helfer:in / Trainer:in") {
                    if eligiblePeople.isEmpty {
                        Text("Keine Trainer:innen/Helfer:innen mit hinterlegtem PRAE-Betrag bei diesem Turnier.")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Person", selection: $selectedPersonID) {
                            Text("Bitte wählen").tag(UUID?.none)
                            ForEach(eligiblePeople) { person in
                                Text(person.displayName).tag(Optional(person.id))
                            }
                        }
                    }
                }

                if let summary {
                    Section("Einsatztage") {
                        if summary.entries.isEmpty {
                            Text("Keine Einsatztage mit hinterlegtem PRAE-Betrag bei diesem Turnier.")
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
            .navigationTitle("PRAE: \(tournament.title)")
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
                guard let summary else { return }
                do {
                    mainFormURL = try PraeExporter.exportMainForm(summary: summary)
                } catch {
                    exportError = error.localizedDescription
                }
            }
            .task(id: selectedPersonID) {
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
}
