import SwiftUI
import SwiftData

struct AccountView: View {
    let currentUser: User?
    let onLogout: () -> Void
    @Environment(\.modelContext) private var modelContext
    @Query private var allUsers: [User]
    @Query private var members: [Member]

    @State private var showEdit = false
    @State private var showMyMember = false

    var body: some View {
        Form {
            if let user = currentUser {
                Section {
                    HStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(LinearGradient(colors: [.blue, .purple],
                                                     startPoint: .topLeading,
                                                     endPoint: .bottomTrailing))
                            Text(user.displayName.prefix(1).uppercased())
                                .font(.title)
                                .bold()
                                .foregroundStyle(.white)
                        }
                        .frame(width: 70, height: 70)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(user.displayName)
                                .font(.title3)
                                .bold()
                            Text(user.email)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(roleLabel(user.role.rawValue))
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(.blue.opacity(0.15), in: Capsule())
                        }
                    }
                    .padding(.vertical, 8)
                }

                Section("Kontoinformationen") {
                    LabeledContent("E-Mail", value: user.email)
                    LabeledContent("Mitglied seit",
                                   value: user.createdAt.formatted(date: .abbreviated, time: .omitted))
                    LabeledContent("Teams", value: "\(user.memberships.count)")
                    LabeledContent("Teilnahmen", value: "\(user.participations.count)")
                    LabeledContent("Grazer VSC") {
                        Label(user.isGrazerVSCMember ? "Mitglied" : "Kein Mitglied",
                              systemImage: user.isGrazerVSCMember ? "checkmark.seal.fill" : "xmark.seal")
                            .foregroundStyle(user.isGrazerVSCMember ? .green : .secondary)
                    }
                }

                Section {
                    Button {
                        showEdit = true
                    } label: {
                        Label("Profil bearbeiten", systemImage: "pencil")
                    }

                    if user.isGrazerVSCMember {
                        Button {
                            showMyMember = true
                        } label: {
                            Label("Vereinsdaten bearbeiten", systemImage: "square.and.pencil")
                        }
                    }

                }

                Section {
                    Button(role: .destructive) {
                        onLogout()
                    } label: {
                        Label("Abmelden", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Account")
        .sheet(isPresented: $showEdit) {
            if let user = currentUser {
                EditAccountView(user: user)
            }
        }
        .sheet(isPresented: $showMyMember) {
            if let user = currentUser, let member = Member.first(matching: user, in: members) {
                MyMemberView(member: member)
            } else {
                ContentUnavailableView("Kein Vereinsdateneintrag gefunden",
                                       systemImage: "exclamationmark.triangle")
            }
        }
    }

    private func roleLabel(_ role: String) -> LocalizedStringKey {
        switch role {
        case "admin": return "Administrator"
        case "coach": return "Trainer:in"
        default: return "Mitglied"
        }
    }
}

struct EditAccountView: View {
    @Bindable var user: User
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        NavigationStack {
            Form {
                Section("Profil") {
                    TextField("Vorname", text: $user.firstName)
                    TextField("Nachname", text: $user.lastName)
                    TextField("E-Mail", text: $user.email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    // Advisory only, deliberately never blocks Fertig/dismiss (unlike
                    // nameIsBlank below) — an already-malformed pre-existing email
                    // must stay viewable/editable, not lock the user out of this sheet.
                    if !Validation.isPlausibleEmail(user.email) {
                        Label("Ungültige E-Mail-Adresse", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                Section {
                    LabeledContent("Rolle", value: roleLabel(user.role.rawValue))
                    Text("Die Rolle kann nur von einem Root-Benutzer geändert werden.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Profil bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                        .disabled(nameIsBlank)
                }
            }
            // Blocks swipe-to-dismiss too, not just the toolbar button — a
            // blank name here silently drops from every export that shows
            // this person (e.g. Trainingsfrequenzliste), unlike every other
            // name-entry point in the app (RegisterView, AddMemberView),
            // which already disable their save action the same way.
            .interactiveDismissDisabled(nameIsBlank)
            // Catches the case where firstName/lastName/email are edited into a
            // match for the club's designated root account (Models.swift's
            // elevateIfDesignatedRoot) -- that account is always created manually,
            // so this is the only place besides creation where the grant can fire.
            .onChange(of: user.firstName) { _, _ in applyDesignatedRootGrantIfNeeded() }
            .onChange(of: user.lastName) { _, _ in applyDesignatedRootGrantIfNeeded() }
            .onChange(of: user.email) { _, _ in applyDesignatedRootGrantIfNeeded() }
            .onDisappear {
                UserService.save(user, modelContext: modelContext)
            }
        }
    }

    private func applyDesignatedRootGrantIfNeeded() {
        let oldRole = user.role
        if user.elevateIfDesignatedRoot() {
            UserService.save(user, modelContext: modelContext)
            RoleChangeLogService.log(userID: user.id, oldRole: oldRole.rawValue, newRole: user.role.rawValue,
                                      changedBy: "system:designatedRoot", modelContext: modelContext)
        }
    }

    private var nameIsBlank: Bool {
        user.firstName.trimmingCharacters(in: .whitespaces).isEmpty ||
        user.lastName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func roleLabel(_ role: String) -> String {
        switch role {
        case "admin": return "Administrator"
        case "coach": return "Trainer:in"
        default: return "Mitglied"
        }
    }
}

struct UserListView: View {
    let currentUser: User
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\User.lastName), SortDescriptor(\User.firstName)]) private var users: [User]
    @Environment(\.dismiss) private var dismiss
    // Role changes are one of audit.md's two explicitly-prioritized areas
    // for visible save/sync failure signaling (alongside roster edits, see
    // MembersListView) — see ServiceFailureSignal.swift.
    private let failureSignal = ServiceFailureSignal.shared

    var body: some View {
        NavigationStack {
            List {
                ForEach(users) { user in
                    HStack {
                        HStack(spacing: 6) {
                            Text(user.displayName)
                            if user.isRoot {
                                Text("ROOT")
                                    .font(.caption2)
                                    .bold()
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1)
                                    .background(.orange.opacity(0.2), in: Capsule())
                                    .foregroundStyle(.orange)
                            }
                        }
                        Spacer()
                        if currentUser.isRoot && user.id != currentUser.id {
                            Picker("Rolle", selection: roleBinding(for: user)) {
                                Text("Mitglied").tag("member")
                                Text("Trainer:in").tag("coach")
                                Text("Admin").tag("admin")
                            }
                            .labelsHidden()
                        } else {
                            Text(user.role.rawValue)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { offsets in
                    for index in offsets {
                        UserService.delete(users[index], modelContext: modelContext)
                    }
                }
            }
            .navigationTitle("Benutzer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
            .alert("Fehler", isPresented: Binding(
                get: { failureSignal.message != nil },
                set: { if !$0 { failureSignal.clear() } }
            )) {
                Button("OK") { failureSignal.clear() }
            } message: {
                Text(failureSignal.message ?? "")
            }
        }
    }

    /// Only a root user reaches this binding (see the `currentUser.isRoot` gate above),
    /// and never for their own row — so this can never be used for self-promotion.
    /// Still `Binding<String>` — the Picker's `.tag(...)` values below are plain
    /// strings ("member"/"coach"/"admin"), so this bridges to/from `AppRole` at
    /// the edges rather than changing the Picker's own tag type.
    private func roleBinding(for user: User) -> Binding<String> {
        Binding(
            get: { user.role.rawValue },
            set: { newRoleRaw in
                let oldRole = user.role
                let newRole = AppRole.normalize(newRoleRaw)
                guard newRole != oldRole else { return }
                user.role = newRole
                guard UserService.save(user, modelContext: modelContext) else { return }
                RoleChangeLogService.log(userID: user.id, oldRole: oldRole.rawValue, newRole: newRole.rawValue,
                                          changedBy: currentUser.id.uuidString, modelContext: modelContext)
            }
        )
    }
}

/// Admin-only view of `RoleChangeLog` entries, newest first — audit.md P0
/// enhancement #2. Reuses the same `List` + `refreshable` + "Fertig" dismiss
/// pattern as `UserListView`/`MembersListView` right above.
struct RoleChangeLogView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \RoleChangeLog.changedAt, order: .reverse) private var entries: [RoleChangeLog]
    @Query private var users: [User]

    var body: some View {
        NavigationStack {
            List {
                if entries.isEmpty {
                    ContentUnavailableView("Keine Rollenänderungen",
                                           systemImage: "clock.arrow.circlepath",
                                           description: Text("Änderungen an Benutzerrollen erscheinen hier."))
                } else {
                    ForEach(entries) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(displayName(for: entry.userID)): \(entry.oldRole) → \(entry.newRole)")
                                .font(.body)
                            Text("Geändert von \(changedByLabel(entry.changedBy)) am \(entry.changedAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Rollenänderungen")
            .navigationBarTitleDisplayMode(.inline)
            .refreshable {
                await SyncOrchestrationService.syncAll(modelContext: modelContext)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
    }

    private func displayName(for userID: UUID) -> String {
        users.first { $0.id == userID }?.displayName ?? "?"
    }

    /// `changedBy` is either an acting User's `id` (uuidString) or a fixed
    /// "system:<mechanism>" tag — resolve the former to a display name,
    /// leave the latter as-is.
    private func changedByLabel(_ changedBy: String) -> String {
        guard let id = UUID(uuidString: changedBy) else { return changedBy }
        return users.first { $0.id == id }?.displayName ?? changedBy
    }
}
