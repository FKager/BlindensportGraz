import SwiftUI
import SwiftData
import AuthenticationServices

struct RootView: View {
    @State private var currentUser: User?
    @State private var isResolvingAccount = true
    @AppStorage("appleUserIdentifier") private var storedAppleUserIdentifier = ""
    // appleUserIdentifier is deliberately never synced to CloudKit (privacy —
    // stays device-local), so if the local store is ever wiped and rebuilt
    // from a CloudKit resync (see BlindensportGrazApp's ModelContainer
    // migration fallback), the freshly-pulled User row has no
    // appleUserIdentifier to match against on this device anymore. This
    // second key remembers the local `id` (which CloudKit does carry) so
    // resolveAccount can re-link to the same synced account instead of
    // silently minting a duplicate one below.
    @AppStorage("localUserID") private var storedUserID = ""

    @Environment(\.modelContext) private var modelContext
    @Query private var users: [User]

    private let appleSignIn = AppleSignInCoordinator()

    var body: some View {
        Group {
            if isResolvingAccount {
                ProgressView()
            } else if let user = currentUser {
                MainTabView(currentUser: user, onLogout: { currentUser = nil })
            } else {
                LoginView(onLogin: { user in
                    applyDesignatedRootGrant(user)
                    applyTestAdminGrant(user)
                    currentUser = user
                })
            }
        }
        .task {
            await resolveAccount()
        }
    }

    /// On first run, creates the local account automatically from the device's
    /// signed-in Apple ID (email + name), instead of requiring manual registration.
    private func resolveAccount() async {
        defer { isResolvingAccount = false }

        if !storedAppleUserIdentifier.isEmpty {
            if let match = users.first(where: { $0.appleUserIdentifier == storedAppleUserIdentifier }) {
                currentUser = match
                storedUserID = match.id.uuidString
                applyDesignatedRootGrant(match)
                applyTestAdminGrant(match)
            } else if !storedUserID.isEmpty, let id = UUID(uuidString: storedUserID) {
                currentUser = users.first { $0.id == id }
                if let resumed = currentUser {
                    applyDesignatedRootGrant(resumed)
                    applyTestAdminGrant(resumed)
                }
            }
            triggerBackgroundSync()
            return
        }

        guard let result = try? await appleSignIn.requestSignIn() else { return }

        if let existing = users.first(where: { $0.appleUserIdentifier == result.userIdentifier }) {
            storedAppleUserIdentifier = result.userIdentifier
            storedUserID = existing.id.uuidString
            currentUser = existing
            applyDesignatedRootGrant(existing)
            applyTestAdminGrant(existing)
            triggerBackgroundSync()
            return
        }

        // Apple only sends a real email/fullName on the very first grant for
        // this Apple ID + bundle/team combo — never again, not even after an
        // app uninstall+reinstall (see cerebrum's 2026-07-15 Apple Sign-In
        // note). A blank result here, with no local storedAppleUserIdentifier/
        // storedUserID match either (both @AppStorage, wiped by the same
        // uninstall that wipes the local SwiftData store — see bug-164),
        // means this device almost certainly already has a real account
        // somewhere in CloudKit, we just lost every local pointer to it.
        // appleUserIdentifier is deliberately never synced to CloudKit (see
        // this struct's doc comment above), so there is no remote field left
        // to match against — silently minting a blank "Neues Mitglied"
        // account here would orphan the real one instead of asking. Sync
        // first so the real account is pulled in, then bail out to
        // LoginView's account picker instead of guessing.
        if result.fullName == nil && (result.email?.isEmpty ?? true) {
            await CloudKitSync.shared.syncAll(modelContext: modelContext)
            return
        }

        let appleFirstName = result.fullName?.givenName?.trimmingCharacters(in: .whitespaces) ?? ""
        let appleLastName = result.fullName?.familyName?.trimmingCharacters(in: .whitespaces) ?? ""
        let emailPrefix = result.email?.components(separatedBy: "@").first ?? ""
        let firstName: String
        let lastName: String
        if !appleFirstName.isEmpty || !appleLastName.isEmpty {
            firstName = appleFirstName
            lastName = appleLastName
        } else if !emailPrefix.isEmpty {
            firstName = emailPrefix
            lastName = ""
        } else {
            firstName = "Neues"
            lastName = "Mitglied"
        }

        let user = User(email: result.email ?? "",
                         firstName: firstName,
                         lastName: lastName,
                         appleUserIdentifier: result.userIdentifier)
        // The very first account ever created (locally and in CloudKit) becomes root,
        // and admin too — otherwise it'd be locked out of the admin features it needs
        // to set up the club (teams, roster, other admins) in the first place.
        if users.isEmpty, !(await CloudKitSync.shared.hasAnyUserIdentity()) {
            user.isRoot = true
            user.role = "admin"
        }
        user.elevateIfDesignatedRoot()
        user.elevateIfTestAdmin()
        modelContext.insert(user)
        Member.checkMembership(for: user, modelContext: modelContext)
        try? modelContext.save()
        CloudKitSync.shared.pushUserIdentity(user)

        storedAppleUserIdentifier = result.userIdentifier
        storedUserID = user.id.uuidString
        currentUser = user
        triggerBackgroundSync()
    }

    /// Saves/pushes only if User.elevateIfDesignatedRoot() actually changed
    /// something. The club's designated account (Models.swift) has no real Apple
    /// ID and is always created via RegisterView's manual form, so there's no
    /// Apple-verification signal to gate on here — matching on firstName+lastName+
    /// email together (rather than email alone) is what keeps the bar reasonably
    /// high instead.
    private func applyDesignatedRootGrant(_ user: User) {
        guard user.elevateIfDesignatedRoot() else { return }
        try? modelContext.save()
        CloudKitSync.shared.pushUserIdentity(user)
    }

    /// Saves/pushes only if User.elevateIfTestAdmin() actually changed something —
    /// see that method's doc comment (Models.swift) for why this one, unlike
    /// elevateIfDesignatedRoot, has no Apple-verification gate of its own.
    private func applyTestAdminGrant(_ user: User) {
        guard user.elevateIfTestAdmin() else { return }
        try? modelContext.save()
        CloudKitSync.shared.pushUserIdentity(user)
    }

    /// Pulls team/event/training/tournament data other users have shared, without
    /// blocking the UI on network/CloudKit latency.
    private func triggerBackgroundSync() {
        Task {
            await CloudKitSync.shared.syncAll(modelContext: modelContext)
        }
    }
}

struct MainTabView: View {
    let currentUser: User
    let onLogout: () -> Void

    var body: some View {
        TabView {
            NavigationStack { DashboardView(currentUser: currentUser) }
                .tabItem { Label("Übersicht", systemImage: "house.fill") }

            NavigationStack { EventsListView(currentUser: currentUser) }
                .tabItem { Label("Events", systemImage: "calendar") }

            NavigationStack { TournamentsListView(currentUser: currentUser) }
                .tabItem { Label("Turniere", systemImage: "trophy.fill") }

            NavigationStack { TrainingsListView(currentUser: currentUser) }
                .tabItem { Label("Trainings", systemImage: "figure.run") }

            NavigationStack { TeamsListView(currentUser: currentUser) }
                .tabItem { Label("Teams", systemImage: "person.3.fill") }

            if currentUser.role == "admin" || currentUser.isRoot {
                NavigationStack { MembersListView(currentUser: currentUser) }
                    .tabItem { Label("Benutzerverwaltung", systemImage: "building.columns.fill") }
            }

            NavigationStack { AccountView(currentUser: currentUser, onLogout: onLogout) }
                .tabItem { Label("Account", systemImage: "person.crop.circle") }
        }
    }
}

struct LoginView: View {
    let onLogin: (User) -> Void

    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\User.lastName), SortDescriptor(\User.firstName)]) private var users: [User]

    @State private var showRegister = false

    var body: some View {
        NavigationStack {
            List {
                if users.isEmpty {
                    ContentUnavailableView("Noch keine Konten",
                                           systemImage: "person.crop.circle.badge.plus",
                                           description: Text("Erstelle das erste Benutzerkonto."))
                } else {
                    Section("Konto auswählen") {
                        ForEach(users) { user in
                            Button {
                                onLogin(user)
                            } label: {
                                Text(user.displayName)
                                    .foregroundStyle(.primary)
                            }
                        }
                        .onDelete { offsets in
                            for index in offsets {
                                let user = users[index]
                                CloudKitSync.shared.deleteUserIdentity(user.id)
                                modelContext.delete(user)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Anmelden")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showRegister = true } label: {
                        Label("Neues Konto", systemImage: "person.badge.plus")
                    }
                }
            }
            .sheet(isPresented: $showRegister) {
                RegisterView(onRegister: onLogin)
            }
        }
    }
}

struct RegisterView: View {
    let onRegister: (User) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var users: [User]

    @State private var email = ""
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var isCreating = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Konto") {
                    TextField("Vorname", text: $firstName)
                    TextField("Nachname", text: $lastName)
                    TextField("E-Mail", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
            .navigationTitle("Neues Konto")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Erstellen") {
                        isCreating = true
                        Task {
                            let user = User(email: email, firstName: firstName, lastName: lastName)
                            // The very first account ever created (locally and in CloudKit) becomes
                            // root and admin — otherwise it'd be locked out of the admin features
                            // it needs to set up the club in the first place.
                            if users.isEmpty, !(await CloudKitSync.shared.hasAnyUserIdentity()) {
                                user.isRoot = true
                                user.role = "admin"
                            }
                            user.elevateIfDesignatedRoot()
                            user.elevateIfTestAdmin()
                            modelContext.insert(user)
                            Member.checkMembership(for: user, modelContext: modelContext)
                            try? modelContext.save()
                            CloudKitSync.shared.pushUserIdentity(user)
                            dismiss()
                            onRegister(user)
                        }
                    }
                    .disabled(isCreating ||
                              firstName.trimmingCharacters(in: .whitespaces).isEmpty ||
                              lastName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
