import SwiftUI

/// Admin-only member list for a SportEvent, Tournament, or Training, derived
/// from the membership of whichever team(s) the item is scoped to.
struct MemberListView: View {
    let itemName: String
    let teams: [Team]
    // Only set for Training/Tournament, which track per-member attendance —
    // nil for SportEvent, which has no such concept, so no export button shows.
    var exportContext: TeilnehmerlisteContext? = nil

    @State private var exportedFileURL: URL?
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
