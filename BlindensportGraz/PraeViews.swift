import SwiftUI
import SwiftData

/// Admin-only screen (see TrainingsListView's "Berichte" toolbar menu) that
/// picks a helper/coach + calendar month and shows the resulting PRAE
/// deployment days computed from Attendance.praeAmount entries — see
/// PraeCalculation.swift for the underlying logic and PraeExport.swift for
/// the two export options. PRAE now has the same split as KostZ (see
/// KostZViews.swift's doc comments): a tournament's own deployments are
/// filed per-event via PraeTournamentCalculationView below (reachable from
/// TournamentDetailView), so this month-wide screen only ever covers
/// Trainings — otherwise a tournament's deployment days would be recorded
/// twice. Self-contained NavigationStack + dismiss button since it's
/// sheet-presented, not tab-hosted (matches MembersListView).
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
            .task(id: "\(selectedPersonID?.uuidString ?? "")-\(month)-\(year)") {
                mainFormURL = nil
                guard let summary else { return }
                do {
                    mainFormURL = try PraeExporter.exportMainForm(summary: summary)
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
