import SwiftUI
import SwiftData

/// Admin-only screen (see TrainingsListView's "Berichte" toolbar menu) that
/// bundles a whole calendar month's PRAE/KostZ paperwork into one .zip —
/// see SammelabrechnungExporter's doc comment for exactly what's included.
/// Same month/year picker as KostZCalculationView (this is the club-wide,
/// month-scoped counterpart, not per-person), and the same eager-export-via-
/// `.task`-then-`ShareLink` pattern as every other export screen in this app
/// (never a Button-triggered second sheet — see cerebrum.md's 2026-07-18
/// VoiceOver-freeze entries).
struct SammelabrechnungView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    // Intentionally unfiltered (audit.md SwiftData & CloudKit Finding 6):
    // `SammelabrechnungExporter` feeds `allMemberships` straight into
    // `KostZCalculator.summary`/`PraeCalculator.eligiblePeople`, which
    // filters to `role.isHelfer`. A `#Predicate` scoping to coach/assistant
    // was tried — see `KostZCalculationView`'s identical @Query comment
    // (BlindensportGraz/KostZViews.swift) for why it compiles but crashes
    // at runtime against `MembershipRole`, a custom `@Model`-stored enum.
    @Query private var allMemberships: [TeamMembership]

    @State private var month = Calendar.current.component(.month, from: .now)
    @State private var year = Calendar.current.component(.year, from: .now)
    @State private var exportURL: URL?
    @State private var exportError: String?

    private var kostZSummary: KostZMonthSummary {
        KostZCalculator.summary(month: month, year: year, allMemberships: allMemberships, in: modelContext)
    }

    // One PraeMonthSummary per person KostZ already resolved to a non-zero
    // honorarium — no separate eligibility computation, see
    // SammelabrechnungExporter's doc comment.
    private var praeSummaries: [PraeMonthSummary] {
        kostZSummary.personAmounts.map {
            PraeCalculator.summary(for: $0.person, month: month, year: year, in: modelContext)
        }
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

                Section("Enthaltene Unterlagen") {
                    LabeledContent("KostZ-Formular", value: "1 Datei")
                    if kostZSummary.personAmounts.isEmpty {
                        Text("Keine Trainer:innen/Helfer:innen mit hinterlegtem PRAE-Betrag in diesem Monat.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(kostZSummary.personAmounts) { entry in
                            LabeledContent(entry.person.displayName, value: "PRAE + Darstellung")
                        }
                    }
                }

                Section("Export") {
                    Text("Bündelt das KostZ-Formular sowie PRAE-Formular und Darstellung der Verwendungszwecke jeder/jedes Trainer:in/Helfer:in mit hinterlegtem Betrag in diesem Monat als ZIP-Datei.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let exportURL {
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
            .task(id: "\(month)-\(year)") {
                exportURL = nil
                do {
                    exportURL = try SammelabrechnungExporter.export(kostZ: kostZSummary, praeSummaries: praeSummaries)
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

/// Admin-only screen (see TournamentDetailView's toolbar) that bundles a
/// single tournament's PRAE/KostZ/TeilnehmerInnenliste paperwork into one
/// .zip — the per-tournament counterpart to SammelabrechnungView's
/// per-month one. No month/year picker: the tournament supplies its own
/// period, same as KostZTournamentCalculationView/
/// PraeTournamentCalculationView. Four independent "Enthaltene Teile"
/// toggles (KostZ, PRAE, TeilnehmerInnenliste Sportler, TeilnehmerInnenliste
/// Helfer) — all pre-selected by default, per user request — let the
/// treasurer leave out parts they don't need instead of always getting
/// everything.
struct SammelabrechnungTournamentView: View {
    let tournament: Tournament
    @Environment(\.dismiss) private var dismiss
    // Intentionally unfiltered — see SammelabrechnungView's identical
    // @Query comment above.
    @Query private var allMemberships: [TeamMembership]

    @State private var includeKostZ = true
    @State private var includePrae = true
    @State private var includeTeilnehmerSportler = true
    @State private var includeTeilnehmerHelfer = true

    @State private var exportURL: URL?
    @State private var exportError: String?

    private var kostZSummary: KostZTournamentSummary {
        KostZCalculator.summary(for: tournament, allMemberships: allMemberships)
    }

    private var praeSummaries: [PraeTournamentSummary] {
        kostZSummary.personAmounts.map {
            PraeCalculator.summary(for: $0.person, tournament: tournament)
        }
    }

    // Read straight from tournament.attendances (attended == true) rather
    // than deriving from tournament.teams/allMemberships — same source
    // PraeCalculator.summary(for:tournament:) reads from, and self-contained
    // without needing TournamentDetailView's own allMemberships/
    // attendedMemberships to be passed in. Deduped by underlying person,
    // same identity-key convention as TournamentDetailView.allMemberships/
    // PraeCalculator.eligiblePeople.
    private var attendedMemberships: [TeamMembership] {
        var seenKeys = Set<UUID>()
        var result: [TeamMembership] = []
        for attendance in tournament.attendances where attendance.attended {
            let membership = attendance.membership
            let key = membership.user?.id ?? membership.member?.id ?? membership.id
            if seenKeys.insert(key).inserted {
                result.append(membership)
            }
        }
        return result.sortedByLastName()
    }

    // Same Sportler/Helfer role split as TournamentDetailView's identically-
    // named private helpers (see that file's comments for why "== .player",
    // not "!isHelfer").
    private func isHelfer(_ membership: TeamMembership) -> Bool { membership.role.isHelfer }
    private func isSportler(_ membership: TeamMembership) -> Bool { membership.role == .player }

    private var teilnehmerlisteSportlerContext: TeilnehmerlisteContext {
        TeilnehmerlisteContext(betrifft: tournament.title, ort: tournament.locationWithCountry,
                                startDate: tournament.startDate, endDate: tournament.endDate,
                                attendedMemberships: attendedMemberships.filter(isSportler),
                                fileNamePrefix: "TN-Sportler")
    }

    private var teilnehmerlisteHelferContext: TeilnehmerlisteContext {
        TeilnehmerlisteContext(betrifft: tournament.title, ort: tournament.locationWithCountry,
                                startDate: tournament.startDate, endDate: tournament.endDate,
                                attendedMemberships: attendedMemberships.filter(isHelfer),
                                fileNamePrefix: "TN-Helfer")
    }

    private var hasSelectedParts: Bool {
        includeKostZ || includePrae || includeTeilnehmerSportler || includeTeilnehmerHelfer
    }

    // Re-runs the export whenever a toggle changes or the underlying data
    // does (kostZSummary.total, same trigger as before).
    private var exportTaskID: String {
        "\(includeKostZ)-\(includePrae)-\(includeTeilnehmerSportler)-\(includeTeilnehmerHelfer)-\(kostZSummary.total)"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Enthaltene Teile") {
                    Toggle("KostZ-Formular", isOn: $includeKostZ)
                    Toggle("PRAE (Formular + Darstellung)", isOn: $includePrae)
                    Toggle("TeilnehmerInnenliste Sportler", isOn: $includeTeilnehmerSportler)
                    Toggle("TeilnehmerInnenliste Helfer", isOn: $includeTeilnehmerHelfer)
                }

                if includePrae {
                    Section("Trainer:innen/Helfer:innen mit PRAE") {
                        if kostZSummary.personAmounts.isEmpty {
                            Text("Keine Trainer:innen/Helfer:innen mit hinterlegtem PRAE-Betrag bei diesem Turnier.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(kostZSummary.personAmounts) { entry in
                                LabeledContent(entry.person.displayName, value: "PRAE + Darstellung")
                            }
                        }
                    }
                }

                Section("Export") {
                    Text("Bündelt die ausgewählten Teile — KostZ-Formular, PRAE-Formular/Darstellung der eingesetzten Trainer:innen/Helfer:innen sowie die TeilnehmerInnenliste(n) — als ZIP-Datei.")
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
            .navigationTitle("Sammelabrechnung: \(tournament.title)")
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
            .task(id: exportTaskID) {
                exportURL = nil
                guard hasSelectedParts else { return }
                do {
                    exportURL = try SammelabrechnungExporter.export(
                        kostZ: includeKostZ ? kostZSummary : nil,
                        praeSummaries: includePrae ? praeSummaries : [],
                        teilnehmerlisteSportler: includeTeilnehmerSportler ? teilnehmerlisteSportlerContext : nil,
                        teilnehmerlisteHelfer: includeTeilnehmerHelfer ? teilnehmerlisteHelferContext : nil)
                } catch {
                    exportError = error.localizedDescription
                }
            }
        }
    }
}

/// Admin-only screen (see TrainingsListView's "Berichte" toolbar menu) that
/// bundles a WHOLE calendar year's paperwork — every month's and every
/// tournament's Sammelabrechnung, plus every training sport's two
/// Trainingsfrequenzliste half-years — into one .zip (audit.md Enhancement
/// #8, `SammelabrechnungExporter.exportSeason`'s doc comment). Same
/// eager-export-via-`.task`-then-`ShareLink` pattern as every other export
/// screen in this app.
struct SammelabrechnungSeasonView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    // Intentionally unfiltered — see SammelabrechnungView's identical
    // @Query comment above.
    @Query private var allMemberships: [TeamMembership]
    @Query(sort: \Tournament.startDate) private var tournaments: [Tournament]
    @Query(sort: \Training.startDate) private var trainings: [Training]

    @State private var year = Calendar.current.component(.year, from: .now)
    @State private var exportURL: URL?
    @State private var exportError: String?

    // Same "distinct sports across every training ever created" source as
    // TrainingsfrequenzlisteView's availableSports.
    private var sports: [String] {
        Array(Set(trainings.map(\.sport))).sorted()
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Zeitraum") {
                    Stepper("Jahr: \(String(year))", value: $year, in: 2020...2100)
                }

                Section("Export") {
                    Text("Bündelt alle Monats- und Turnier-Sammelabrechnungen sowie alle Trainingsfrequenzlisten dieses Jahres als eine ZIP-Datei.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let exportURL {
                        ShareLink(item: exportURL) {
                            Label("Saison-Sammelabrechnung exportieren", systemImage: "doc.zipper")
                        }
                    } else {
                        Label("Saison-Sammelabrechnung wird vorbereitet …", systemImage: "doc.zipper")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Saison-Sammelabrechnung")
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
            .task(id: year) {
                exportURL = nil
                do {
                    exportURL = try SammelabrechnungExporter.exportSeason(
                        year: year, allMemberships: allMemberships, tournaments: tournaments,
                        sports: sports, in: modelContext)
                } catch {
                    exportError = error.localizedDescription
                }
            }
        }
    }
}
