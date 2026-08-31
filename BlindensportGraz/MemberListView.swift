import SwiftUI

/// Admin-only member list for a SportEvent, Tournament, or Training, derived
/// from the membership of whichever team(s) the item is scoped to.
struct MemberListView: View {
    let itemName: String
    let teams: [Team]
    // Only set by TournamentDetailView. The TeilnehmerInnenliste export is
    // Sport-Austria tournament paperwork — SportEvent has no attendance
    // concept to source it from, and Training already has its own
    // equivalent (the Trainingsfrequenzliste, via TrainingsListView's
    // "Berichte" menu), so neither passes an exportContext and this view
    // stays roster-only for them.
    var exportContext: TeilnehmerlisteContext? = nil
    // Restricts the displayed/exported roster to memberships matching this
    // predicate — used by TournamentDetailView's "Teilnehmer Sportler" /
    // "Teilnehmer Helfer" Berichte entries to split one combined member list
    // into a role-based pair, each with its own Sport-Austria Excel export.
    // Events/Trainings don't pass one, so they keep showing everyone.
    var membershipFilter: (TeamMembership) -> Bool = { _ in true }
    // "Mitglieder" for the plain Events/Trainings roster; TournamentDetailView
    // overrides this to "Teilnehmer Sportler"/"Teilnehmer Helfer" for its
    // role-split Berichte entries.
    var kindLabel: String = "Mitglieder"

    @State private var exportedFileURL: URL?
    @State private var exportErrorMessage: String?

    private func filteredMemberships(for team: Team) -> [TeamMembership] {
        team.memberships.filter(membershipFilter).sortedByLastName()
    }

    private func identityKey(_ membership: TeamMembership) -> UUID {
        membership.user?.id ?? membership.member?.id ?? membership.id
    }

    // Per-team rosters, deduped by the underlying person across all teams
    // shown here — someone in two of these teams (e.g. a training assigned
    // to both) would otherwise be listed once per team. Mirrors
    // TrainingDetailView.allMemberships' identity key; kept per-team (rather
    // than flattened) so the existing "Section per team" layout is
    // unaffected — each person just stays in the first team section they
    // appear in.
    private var dedupedMembershipsByTeam: [(team: Team, memberships: [TeamMembership])] {
        var seenKeys = Set<UUID>()
        return teams.map { team in
            let deduped = filteredMemberships(for: team).filter { seenKeys.insert(identityKey($0)).inserted }
            return (team, deduped)
        }
    }

    private var exportText: String {
        dedupedMembershipsByTeam.map { team, memberships in
            let names = memberships.map(\.displayName)
            let noMembers = String(localized: "Keine Mitglieder")
            let lines = names.isEmpty ? noMembers : names.map { "- \($0)" }.joined(separator: "\n")
            return "\(team.name):\n\(lines)"
        }.joined(separator: "\n\n")
    }

    var body: some View {
        NavigationStack {
            List {
                if teams.isEmpty {
                    ContentUnavailableView("Kein Team zugeordnet",
                                           systemImage: "person.3",
                                           description: Text("Diesem Eintrag ist kein Team zugewiesen."))
                } else {
                    ForEach(dedupedMembershipsByTeam, id: \.team.id) { team, memberships in
                        Section(team.name) {
                            if memberships.isEmpty {
                                Text("Keine Mitglieder")
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(memberships) { membership in
                                    HStack {
                                        Text(membership.displayName)
                                        Spacer()
                                        Text(membership.role.rawValue)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
                if let exportContext, !exportContext.attendedMemberships.isEmpty {
                    Section {
                        // Deliberately ShareLink, not a Button that presents a
                        // hand-rolled UIActivityViewController sheet — the
                        // latter froze the app under VoiceOver every time,
                        // even after eliminating sheet-on-sheet nesting,
                        // while this exact ShareLink pattern (see the text
                        // export in the toolbar below) works reliably under
                        // VoiceOver. The file is generated eagerly in .task
                        // below (it's fast, well under a second) so it's
                        // ready by the time this renders.
                        if let exportedFileURL {
                            ShareLink(item: exportedFileURL) {
                                Label("TeilnehmerInnenliste exportieren (Sport Austria)", systemImage: "square.and.arrow.up.on.square")
                            }
                        } else {
                            Label("TeilnehmerInnenliste wird vorbereitet …", systemImage: "square.and.arrow.up.on.square")
                                .foregroundStyle(.secondary)
                        }
                        if exportContext.attendedMemberships.count > TeilnehmerlisteExporter.maxRows {
                            Text("Das Formular fasst nur \(TeilnehmerlisteExporter.maxRows) Personen — es werden nur die ersten \(TeilnehmerlisteExporter.maxRows) von \(exportContext.attendedMemberships.count) exportiert.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("\(kindLabel) – \(itemName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !teams.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        ShareLink(item: exportText)
                    }
                }
            }
            .alert("Export fehlgeschlagen", isPresented: Binding(
                get: { exportErrorMessage != nil },
                set: { if !$0 { exportErrorMessage = nil } }
            )) {
                Button("OK") { exportErrorMessage = nil }
            } message: {
                Text(exportErrorMessage ?? "")
            }
            .task(id: exportContext?.attendedMemberships.map(\.id)) {
                guard let exportContext, exportedFileURL == nil else { return }
                do {
                    exportedFileURL = try TeilnehmerlisteExporter.export(context: exportContext)
                } catch {
                    exportErrorMessage = error.localizedDescription
                }
            }
        }
    }
}
