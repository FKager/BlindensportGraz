import SwiftUI
import SwiftData

/// Admin-only screen (see TournamentDetailView's toolbar) that bundles a
/// single tournament's PRAE/KostZ/TeilnehmerInnenliste paperwork into one
/// .zip — the per-tournament counterpart to SammelabrechnungView's
/// per-month one. No month/year picker: the tournament supplies its own
/// period, same as KostZTournamentCalculationView/
/// PraeTournamentCalculationView. "Enthaltene Teile" toggles for
/// KostZ/TeilnehmerInnenliste Sportler/TeilnehmerInnenliste Helfer, PLUS one
/// PRAE (Formular + Darstellung) toggle **per eligible helper** — not a
/// single all-or-nothing PRAE switch — since a treasurer may only need some
/// helpers' PRAE paperwork in a given bundle (user request: "the selection
/// ... should include the selection for pre/darstellung of every helper. So
/// it should be possible to select only a part of that"). Everything is
/// pre-selected by default, per the earlier request this extends.
struct SammelabrechnungTournamentView: View {
    let tournament: Tournament
    @Environment(\.dismiss) private var dismiss
    // Intentionally unfiltered — see SammelabrechnungView's identical
    // @Query comment above.
    @Query private var allMemberships: [TeamMembership]

    @State private var includeKostZ = true
    @State private var includeTeilnehmerSportler = true
    @State private var includeTeilnehmerHelfer = true
    // Which PraeEligiblePerson.id's PRAE (Formular + Darstellung) to
    // include — seeded to "everyone" once kostZSummary.personAmounts is
    // known (see the .onAppear below), since it can't be computed inline as
    // this @State property's default (personAmounts depends on the
    // allMemberships @Query, not available yet at view init).
    @State private var selectedPraePersonIDs: Set<UUID> = []
    @State private var hasSeededPraeSelection = false

    @State private var exportURL: URL?
    @State private var exportError: String?

    private var kostZSummary: KostZTournamentSummary {
        KostZCalculator.summary(for: tournament, allMemberships: allMemberships)
    }

    private var praeSummaries: [PraeTournamentSummary] {
        kostZSummary.personAmounts
            .filter { selectedPraePersonIDs.contains($0.person.id) }
            .map { PraeCalculator.summary(for: $0.person, tournament: tournament) }
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
        includeKostZ || !praeSummaries.isEmpty || includeTeilnehmerSportler || includeTeilnehmerHelfer
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
    // underlying data does (kostZSummary.total, same trigger as before).
    // selectedPraePersonIDs is sorted before joining so the id is stable
    // regardless of Set iteration order.
    private var exportTaskID: String {
        let praeIDs = selectedPraePersonIDs.map(\.uuidString).sorted().joined(separator: ",")
        return "\(includeKostZ)-\(praeIDs)-\(includeTeilnehmerSportler)-\(includeTeilnehmerHelfer)-\(kostZSummary.total)"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Enthaltene Teile") {
                    Toggle("KostZ-Formular", isOn: $includeKostZ)
                    Toggle("TeilnehmerInnenliste Sportler", isOn: $includeTeilnehmerSportler)
                    Toggle("TeilnehmerInnenliste Helfer", isOn: $includeTeilnehmerHelfer)
                }

                Section("PRAE (Formular + Darstellung)") {
                    if kostZSummary.personAmounts.isEmpty {
                        Text("Keine Trainer:innen/Helfer:innen mit hinterlegtem PRAE-Betrag bei diesem Turnier.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(kostZSummary.personAmounts) { entry in
                            Toggle(entry.person.displayName, isOn: praeBinding(for: entry.person.id))
                        }
                    }
                }

                Section("Export") {
                    Text("Bündelt die ausgewählten Teile — KostZ-Formular, PRAE-Formular/Darstellung der ausgewählten Trainer:innen/Helfer:innen sowie die TeilnehmerInnenliste(n) — als ZIP-Datei.")
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
            .onAppear {
                // Pre-select every eligible helper's PRAE the first time
                // this sheet appears — runs synchronously before the
                // .task below, so the very first export already reflects
                // "all pre-selected" instead of momentarily exporting with
                // none selected.
                guard !hasSeededPraeSelection else { return }
                selectedPraePersonIDs = Set(kostZSummary.personAmounts.map(\.person.id))
                hasSeededPraeSelection = true
            }
            .task(id: exportTaskID) {
                exportURL = nil
                guard hasSelectedParts else { return }
                do {
                    exportURL = try SammelabrechnungExporter.export(
                        kostZ: includeKostZ ? kostZSummary : nil,
                        praeSummaries: praeSummaries,
                        teilnehmerlisteSportler: includeTeilnehmerSportler ? teilnehmerlisteSportlerContext : nil,
                        teilnehmerlisteHelfer: includeTeilnehmerHelfer ? teilnehmerlisteHelferContext : nil)
                } catch {
                    exportError = error.localizedDescription
                }
            }
        }
    }
}
