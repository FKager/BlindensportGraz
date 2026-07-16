import SwiftUI
import SwiftData

struct TeamsListView: View {
    let currentUser: User?
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Team.name) private var teams: [Team]
    @State private var showAdd = false

    var canManageTeams: Bool {
        guard let user = currentUser else { return false }
        return user.role == "admin" || user.role == "coach"
    }

    var body: some View {
        List {
            if teams.isEmpty {
                ContentUnavailableView("Keine Teams",
                                       systemImage: "person.3",
                                       description: Text("Lege ein neues Team an."))
            } else {
                ForEach(teams) { team in
                    NavigationLink {
                        TeamDetailView(team: team, currentUser: currentUser)
                    } label: {
                        TeamRow(team: team)
                    }
                }
                .onDelete(perform: deleteTeams)
            }
        }
        .navigationTitle("Teams")
        .toolbar {
            if canManageTeams {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                }
            }
        }
        .sheet(isPresented: $showAdd) {
            AddTeamView()
        }
    }

    private func deleteTeams(at offsets: IndexSet) {
        if canManageTeams {
            for index in offsets {
                modelContext.delete(teams[index])
            }
        }
    }
}

struct TeamRow: View {
    let team: Team

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [.blue, .purple],
                                         startPoint: .topLeading,
                                         endPoint: .bottomTrailing))
                Text(team.name.prefix(1).uppercased())
                    .font(.title2)
                    .bold()
                    .foregroundStyle(.white)
            }
            .frame(width: 50, height: 50)

            VStack(alignment: .leading, spacing: 4) {
                Text(team.name)
                    .font(.headline)
                Text(team.sport)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("\(team.memberships.count) Mitglieder")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct TeamDetailView: View {
    @Bindable var team: Team
    let currentUser: User?
    @Environment(\.modelContext) private var modelContext
    @Query private var users: [User]
    @Query private var clubMembers: [ClubMember]
    @State private var showAddMember = false

    var availableUsers: [User] {
        let memberIDs = Set(team.memberships.compactMap { $0.user?.id })
        return users.filter { !memberIDs.contains($0.id) }
    }

    var availableClubMembers: [ClubMember] {
        let memberIDs = Set(team.memberships.compactMap { $0.clubMember?.id })
        return clubMembers.filter { !memberIDs.contains($0.id) }
    }

    var canManageTeams: Bool {
        guard let user = currentUser else { return false }
        return user.role == "admin" || user.role == "coach"
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
                    ForEach(team.memberships) { m in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(m.displayName)
                                Text(m.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(m.role)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(.blue.opacity(0.15), in: Capsule())
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            modelContext.delete(team.memberships[index])
                        }
                    }
                }

                Button {
                    showAddMember = true
                } label: {
                    Label("Mitglied hinzufügen", systemImage: "person.badge.plus")
                }
                .disabled((availableUsers.isEmpty && availableClubMembers.isEmpty) || !canManageTeams)
            }
        }
        .navigationTitle(team.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAddMember) {
            AddMemberView(team: team, availableUsers: availableUsers, availableClubMembers: availableClubMembers)
        }
    }
}

private enum MemberSelection: Hashable {
    case user(UUID)
    case clubMember(UUID)
}

struct AddMemberView: View {
    let team: Team
    let availableUsers: [User]
    let availableClubMembers: [ClubMember]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var selection: MemberSelection?
    @State private var role = "player"

    var body: some View {
        NavigationStack {
            Form {
                Section("Mitglied") {
                    Picker("Mitglied", selection: $selection) {
                        Text("Auswählen").tag(MemberSelection?.none)
                        if !availableUsers.isEmpty {
                            Section("Registrierte Benutzer") {
                                ForEach(availableUsers) { user in
                                    Text(user.displayName).tag(MemberSelection?.some(.user(user.id)))
                                }
                            }
                        }
                        if !availableClubMembers.isEmpty {
                            Section("Grazer VSC Mitglieder ohne Konto") {
                                ForEach(availableClubMembers) { member in
                                    Text(member.fullName).tag(MemberSelection?.some(.clubMember(member.id)))
                                }
                            }
                        }
                    }
                }
                Section("Rolle") {
                    Picker("Rolle", selection: $role) {
                        Text("Spieler:in").tag("player")
                        Text("Trainer:in").tag("coach")
                        Text("Assistent:in").tag("assistant")
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle("Mitglied hinzufügen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Hinzufügen") {
                        let membership: TeamMembership?
                        switch selection {
                        case .user(let id):
                            guard let user = availableUsers.first(where: { $0.id == id }) else { membership = nil; break }
                            membership = TeamMembership(user: user, team: team, role: role)
                        case .clubMember(let id):
                            guard let member = availableClubMembers.first(where: { $0.id == id }) else { membership = nil; break }
                            membership = TeamMembership(clubMember: member, team: team, role: role)
                        case nil:
                            membership = nil
                        }
                        if let membership {
                            modelContext.insert(membership)
                            try? modelContext.save()
                            CloudKitSync.shared.pushMembership(membership)
                        }
                        dismiss()
                    }
                    .disabled(selection == nil)
                }
            }
        }
    }
}

struct AddTeamView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var sport = "Torball"
    @State private var descriptionText = ""

    let sports = ["Torball", "Goalball", "Blindenfußball", "Showdown", "Judo", "Leichtathletik", "Schwimmen"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Team") {
                    TextField("Name", text: $name)
                    Picker("Sportart", selection: $sport) {
                        ForEach(sports, id: \.self) { Text($0) }
                    }
                    TextField("Beschreibung", text: $descriptionText, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("Neues Team")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") {
                        let team = Team(name: name, sport: sport, descriptionText: descriptionText)
                        modelContext.insert(team)
                        try? modelContext.save()
                        CloudKitSync.shared.pushTeam(team)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
