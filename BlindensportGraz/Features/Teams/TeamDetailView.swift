import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct TeamDetailView: View {
    @Bindable var team: Team
    let currentUser: User?
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\User.lastName), SortDescriptor(\User.firstName)]) private var users: [User]
    @Query(sort: [SortDescriptor(\Member.lastName), SortDescriptor(\Member.firstName)]) private var members: [Member]
    @State private var showAddMember = false

    var availableUsers: [User] {
        let memberIDs = Set(team.memberships.compactMap { $0.user?.id })
        return users.filter { !memberIDs.contains($0.id) }
    }

    var availableMembers: [Member] {
        let memberIDs = Set(team.memberships.compactMap { $0.member?.id })
        return members.filter { !memberIDs.contains($0.id) }
    }

    var canManageTeams: Bool {
        guard let user = currentUser else { return false }
        return user.role == .admin || user.role == .coach
    }

    var body: some View {
        Form {
            Section("Team") {
                TextField("Name", text: $team.name)
                TextField("Sportart", text: $team.sport)
                TextField("Beschreibung", text: $team.descriptionText, axis: .vertical)
                    .lineLimit(2...5)
            }

            Section("Mitglieder (\(team.memberships.count))") {
                if team.memberships.isEmpty {
                    Text("Keine Mitglieder")
                        .foregroundStyle(.secondary)
                } else {
                    let sortedMemberships = team.memberships.sortedByLastName()
                    ForEach(sortedMemberships) { m in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(m.displayName)
                                Text(m.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if canManageTeams {
                                Menu {
                                    Picker("Rolle", selection: roleBinding(for: m)) {
                                        Text("Spieler:in").tag("player")
                                        Text("Trainer:in").tag("coach")
                                        Text("Assistent:in").tag("assistant")
                                    }
                                } label: {
                                    roleCapsule(m.role.rawValue)
                                }
                                .accessibilityLabel("Rolle: \(roleLabel(m.role.rawValue))")
                                .accessibilityHint("Doppeltippen, um die Rolle zu ändern")
                            } else {
                                roleCapsule(m.role.rawValue)
                            }
                        }
                    }
                    // Indexes into sortedMemberships, NOT team.memberships — a
                    // ForEach over a re-sorted copy needs onDelete's offsets
                    // resolved against that same sorted array, or swiping row
                    // N would delete whoever happens to sit at raw index N in
                    // the unsorted relationship instead of the person actually
                    // shown at that row.
                    .onDelete { offsets in
                        for index in offsets {
                            TeamMembershipService.delete(sortedMemberships[index], modelContext: modelContext)
                        }
                    }
                }

                Button {
                    showAddMember = true
                } label: {
                    Label("Mitglied hinzufügen", systemImage: "person.badge.plus")
                }
                .disabled((availableUsers.isEmpty && availableMembers.isEmpty) || !canManageTeams)
            }
        }
        .navigationTitle(team.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAddMember) {
            AddTeamMemberView(team: team, availableUsers: availableUsers, availableMembers: availableMembers)
        }
    }

    /// Two-way binding straight onto the `TeamMembership.role` stored
    /// property (a `@Model` reference, so mutating it in place is safe even
    /// though `m` here is a `let` from `ForEach`) — the `Picker`'s selection
    /// writes through this on every change, persists, and re-pushes so the
    /// role edit syncs the same way every other membership write does.
    private func roleBinding(for membership: TeamMembership) -> Binding<String> {
        Binding(
            get: { membership.role.rawValue },
            set: { newRoleRaw in
                let newRole = MembershipRole.normalize(newRoleRaw)
                guard newRole != membership.role else { return }
                membership.role = newRole
                TeamMembershipService.save(membership, modelContext: modelContext)
            }
        )
    }

    private func roleLabel(_ role: String) -> String {
        switch role {
        case "coach": return "Trainer:in"
        case "assistant": return "Assistent:in"
        default: return "Spieler:in"
        }
    }

    private func roleCapsule(_ role: String) -> some View {
        Text(role)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .badge(tint: .blue)
    }
}
