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
    @State private var showMembershipTypeChoice = false
    @State private var requestedMember: Member?

    // Derived live from the roster @Query, not from the possibly-stale
    // user.isGrazerVSCMember flag (only recalculated at register/login) —
    // gating "Vereinsdaten bearbeiten" vs. "Mitgliedschaft beantragen" on a
    // stale flag risks the exact User+Member duplicate-record scenario the
    // duplicate-names investigation is chasing (two independent
    // TeamMembership rows for the same real person, one keyed by user, one
    // by member): re-checking here before ever creating a new Member is
    // what keeps requestMembership() safe against that.
    private var matchedMember: Member? {
        currentUser.flatMap { Member.first(matching: $0, in: members) }
    }

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

                    if let member = matchedMember {
                        Button {
                            requestedMember = member
                            showMyMember = true
                        } label: {
                            Label("Vereinsdaten bearbeiten", systemImage: "square.and.pencil")
                        }
                    } else {
                        Button {
                            showMembershipTypeChoice = true
                        } label: {
                            Label("Mitgliedschaft beantragen", systemImage: "person.badge.plus")
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
            // Uses requestedMember (set right before showMyMember = true, by
            // either button above) rather than re-deriving via
            // Member.first(matching:in:) here — a freshly-inserted Member
            // from requestMembership(for:as:) isn't guaranteed to already be
            // reflected in the `members` @Query by the time this closure
            // first runs, so re-deriving here could flash the "not found"
            // fallback right after a successful request.
            if let member = requestedMember {
                MyMemberView(member: member)
            } else {
                ContentUnavailableView("Kein Vereinsdateneintrag gefunden",
                                       systemImage: "exclamationmark.triangle")
            }
        }
        // Helfer vs. Sportler selection for a brand-new self-request — sets
        // the new Member's defaultFunction so it isn't left blank/ambiguous,
        // matching the field's own stated purpose ("Default TeamMembership.role
        // for this person"). Both choices lead to the exact same
        // requestMembership(for:as:) call, just a different `role` argument —
        // deliberately no branch that only allows one or the other, per user
        // request ("A registration for member should be possible in both cases").
        .confirmationDialog("Mitgliedschaft beantragen", isPresented: $showMembershipTypeChoice, titleVisibility: .visible) {
            if let user = currentUser {
                Button("Als Sportler:in") { requestMembership(for: user, as: .player) }
                Button("Als Helfer:in") { requestMembership(for: user, as: .coach) }
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Als Sportler:in oder als Helfer:in (Trainer:in/Betreuer:in) registrieren?")
        }
    }

    /// Self-service roster signup for an account with no matching `Member`
    /// entry yet ("Mitgliedschaft beantragen"). `role` is the Sportler/Helfer
    /// choice from the confirmationDialog above, stored as the new Member's
    /// `defaultFunction` (using the same raw strings as `MembershipRole` —
    /// "player"/"coach" — so it stays directly usable as a
    /// `MembershipRole.normalize(...)` input if a future admin-assignment
    /// flow ever pre-fills from it, matching this codebase's existing role
    /// vocabulary rather than inventing a separate one). Only applied to a
    /// freshly-created entry — an existing matched Member already has
    /// admin-managed data, so its defaultFunction is left untouched.
    /// `Member.resolveMembershipRequest` re-derives the match live rather
    /// than trusting `matchedMember`'s value from whenever the button last
    /// rendered (e.g. an admin could have added a matching roster entry in
    /// between) — see that function's doc comment for why this re-check
    /// matters. Calls `Member.checkMembership` right after so
    /// `user.isGrazerVSCMember`/AccountView's status row update immediately,
    /// without waiting for the next login.
    private func requestMembership(for user: User, as role: MembershipRole) {
        switch Member.resolveMembershipRequest(for: user, in: members, defaultFunction: role.rawValue) {
        case .existing(let member):
            requestedMember = member
        case .new(let member):
            modelContext.insert(member)
            guard MemberService.save(member, modelContext: modelContext) else { return }
            let allMembers = (try? modelContext.fetch(FetchDescriptor<Member>())) ?? []
            MemberBackup.snapshot(members: allMembers)
            requestedMember = member
        }
        Member.checkMembership(for: user, modelContext: modelContext)
        _ = UserService.save(user, modelContext: modelContext)
        showMyMember = true
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
