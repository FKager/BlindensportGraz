import SwiftUI

/// Admin-only member list for a SportEvent, Tournament, or Training, derived
/// from the membership of whichever team(s) the item is scoped to.
struct MemberListView: View {
    let itemName: String
    let teams: [Team]

    private var exportText: String {
        teams.map { team in
            let names = team.memberships.map(\.user.displayName).sorted()
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
                                ForEach(team.memberships.sorted { $0.user.displayName < $1.user.displayName }) { membership in
                                    HStack {
                                        Text(membership.user.displayName)
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
        }
    }
}
