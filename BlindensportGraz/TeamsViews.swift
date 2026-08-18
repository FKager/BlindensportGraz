import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct TeamsListView: View {
    let currentUser: User?
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Team.name) private var teams: [Team]
    @State private var showAdd = false
    // Eager-generation + ShareLink/.fileImporter, not a custom
    // generate-on-tap-then-sheet flow — see MembersListView's identical
    // pattern and cerebrum.md's VoiceOver share-sheet-freeze history.
    @State private var exportURL: URL?
    @State private var showImporter = false
    @State private var importResultMessage: String?

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
        .refreshable {
            await CloudKitSync.shared.syncAll(modelContext: modelContext)
            await CloudKitSync.shared.ensureDefaultTeams(modelContext: modelContext)
        }
        .toolbar {
            if canManageTeams {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showImporter = true } label: { Image(systemName: "square.and.arrow.down") }
                        .accessibilityLabel("Teams importieren")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if let exportURL {
                        ShareLink(item: exportURL) { Image(systemName: "square.and.arrow.up") }
                            .accessibilityLabel("Teams exportieren")
                    }
                }
            }
        }
        .sheet(isPresented: $showAdd) {
            AddTeamView()
        }
        .task(id: teams.map(\.id)) {
            exportURL = try? TeamImportExport.exportFile(teams: teams)
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
            handleImport(result)
        }
        .alert("Import", isPresented: Binding(
            get: { importResultMessage != nil },
            set: { if !$0 { importResultMessage = nil } }
        )) {
            Button("OK") { importResultMessage = nil }
        } message: {
            Text(importResultMessage ?? "")
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let error):
            importResultMessage = "Import fehlgeschlagen: \(error.localizedDescription)"
        case .success(let url):
            let didAccess = url.startAccessingSecurityScopedResource()
            defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                let outcome = TeamImportExport.importTeams(from: data, modelContext: modelContext)
                importResultMessage = outcome.summary
            } catch {
                importResultMessage = "Datei konnte nicht gelesen werden: \(error.localizedDescription)"
            }
        }
    }

    private func deleteTeams(at offsets: IndexSet) {
        if canManageTeams {
            for index in offsets {
                let team = teams[index]
                CloudKitSync.shared.deleteTeam(team.id)
                modelContext.delete(team)
            }
            try? modelContext.save()
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
                                    roleCapsule(m.role)
                                }
                                .accessibilityLabel("Rolle: \(roleLabel(m.role))")
                                .accessibilityHint("Doppeltippen, um die Rolle zu ändern")
                            } else {
                                roleCapsule(m.role)
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
                            let membership = sortedMemberships[index]
                            CloudKitSync.shared.deleteMembership(membership.id)
                            modelContext.delete(membership)
                        }
                        try? modelContext.save()
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
            get: { membership.role },
            set: { newRole in
                guard newRole != membership.role else { return }
                membership.role = newRole
                try? modelContext.save()
                CloudKitSync.shared.pushMembership(membership)
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
            .background(.blue.opacity(0.15), in: Capsule())
    }
}

private enum MemberSelection: Hashable {
    case user(UUID)
    case member(UUID)
}

/// Assigns an existing `User` (registered app account) or roster `Member` to
/// a `Team` via a new `TeamMembership` — named distinctly from `Member`'s own
/// creation view (`AddMemberView` in MembersViews.swift) since this doesn't
/// create a `Member`, it links one that already exists.
struct AddTeamMemberView: View {
    let team: Team
    let availableUsers: [User]
    let availableMembers: [Member]
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
                        if !availableMembers.isEmpty {
                            Section("Mitglieder ohne Konto") {
                                ForEach(availableMembers) { member in
                                    Text(member.fullName).tag(MemberSelection?.some(.member(member.id)))
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
                        case .member(let id):
                            guard let member = availableMembers.first(where: { $0.id == id }) else { membership = nil; break }
                            membership = TeamMembership(member: member, team: team, role: role)
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
                        ForEach(sports, id: \.self) { s in
                            Label(s, systemImage: SportIcon.symbolName(for: s)).tag(s)
                        }
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
