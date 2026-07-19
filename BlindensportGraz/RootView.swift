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

    // The club's official account is always granted root/admin automatically,
    // regardless of signup order — see resolveAccount()'s elevateIfDesignatedRoot.
    // Matched by email only (not first/last name): Apple Sign-In verifies the
    // email on its end, so it's the one field that can't be spoofed through the
    // manual RegisterView form, which is deliberately NOT covered by this check.
    private let designatedRootEmail = "blindensport.gvsc@gmail.com"

    var body: some View {
        Group {
            if isResolvingAccount {
                ProgressView()
            } else if let user = currentUser {
                MainTabView(currentUser: user, onLogout: { currentUser = nil })
            } else {
                LoginView(onLogin: { user in currentUser = user })
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
                elevateIfDesignatedRoot(match, verifiedEmail: match.email)
            } else if !storedUserID.isEmpty, let id = UUID(uuidString: storedUserID) {
                currentUser = users.first { $0.id == id }
                if let resumed = currentUser {
                    elevateIfDesignatedRoot(resumed, verifiedEmail: resumed.email)
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
            elevateIfDesignatedRoot(existing, verifiedEmail: result.email)
            triggerBackgroundSync()
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
        if isDesignatedRootEmail(result.email) {
            user.isRoot = true
            user.role = "admin"
        }
        modelContext.insert(user)
        ClubMember.checkMembership(for: user, modelContext: modelContext)
        try? modelContext.save()
        CloudKitSync.shared.pushUserIdentity(user)

        storedAppleUserIdentifier = result.userIdentifier
        storedUserID = user.id.uuidString
        currentUser = user
        triggerBackgroundSync()
    }

    private func isDesignatedRootEmail(_ email: String?) -> Bool {
        guard let email else { return false }
        return email.trimmingCharacters(in: .whitespaces).lowercased() == designatedRootEmail
    }

    /// Grants root/admin to the club's designated account if it isn't already root,
    /// matching solely on the Apple-verified email (see designatedRootEmail's doc
    /// comment for why manual registration is deliberately excluded). Idempotent
    /// and safe to call on every sign-in — a no-op once the account is already root.
    private func elevateIfDesignatedRoot(_ user: User, verifiedEmail: String?) {
        guard isDesignatedRootEmail(verifiedEmail), !user.isRoot else { return }
        user.isRoot = true
        user.role = "admin"
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

            if currentUser.role == "admin" {
                NavigationStack { ClubMembersListView() }
                    .tabItem { Label("Grazer VSC", systemImage: "building.columns.fill") }
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
                            modelContext.insert(user)
                            ClubMember.checkMembership(for: user, modelContext: modelContext)
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
