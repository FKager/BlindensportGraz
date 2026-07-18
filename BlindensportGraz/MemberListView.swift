import SwiftUI

/// Admin-only member list for a SportEvent, Tournament, or Training, derived
/// from the membership of whichever team(s) the item is scoped to.
struct MemberListView: View {
    let itemName: String
    let teams: [Team]
    // Only set for Training/Tournament, which track per-member attendance —
    // nil for SportEvent, which has no such concept, so no export button shows.
    var exportContext: TeilnehmerlisteContext? = nil
    // Called with the generated file once export succeeds; the caller is
    // responsible for presenting the share sheet itself, after this view has
    // been dismissed (see onExported below) — presenting a second .sheet
    // directly on top of this one froze the app under VoiceOver (nested
    // modal presentation + VoiceOver's synchronous accessibility-tree
    // recompute don't mix), even though it worked fine with VoiceOver off.
    var onExported: (URL) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @State private var exportErrorMessage: String?

    private var exportText: String {
        teams.map { team in
            let names = team.memberships.map(\.displayName).sorted()
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
                    ForEach(teams) { team in
                        Section(team.name) {
                            if team.memberships.isEmpty {
                                Text("Keine Mitglieder")
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(team.memberships.sorted { $0.displayName < $1.displayName }) { membership in
                                    HStack {
                                        Text(membership.displayName)
                                        Spacer()
                                        Text(membership.role)
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
                        Button {
                            exportTeilnehmerliste(exportContext)
                        } label: {
                            Label("TeilnehmerInnenliste exportieren (Sport Austria)", systemImage: "square.and.arrow.up.on.square")
                        }
                        if exportContext.attendedMemberships.count > TeilnehmerlisteExporter.maxRows {
                            Text("Das Formular fasst nur \(TeilnehmerlisteExporter.maxRows) Personen — es werden nur die ersten \(TeilnehmerlisteExporter.maxRows) von \(exportContext.attendedMemberships.count) exportiert.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Mitglieder – \(itemName)")
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
        }
    }

    private func exportTeilnehmerliste(_ context: TeilnehmerlisteContext) {
        do {
            let url = try TeilnehmerlisteExporter.export(context: context)
            dismiss()
            onExported(url)
        } catch {
            exportErrorMessage = error.localizedDescription
        }
    }
}
