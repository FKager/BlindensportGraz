import SwiftUI
import SwiftData
import AuthenticationServices

struct RootView: View {
    @State private var currentUser: User?
    @State private var isResolvingAccount = true
    @AppStorage("appleUserIdentifier") private var storedAppleUserIdentifier = ""

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
            currentUser = users.first { $0.appleUserIdentifier == storedAppleUserIdentifier }
            triggerBackgroundSync()
            return
        }

        guard let result = try? await appleSignIn.requestSignIn() else { return }

        if let existing = users.first(where: { $0.appleUserIdentifier == result.userIdentifier }) {
            storedAppleUserIdentifier = result.userIdentifier
            currentUser = existing
            triggerBackgroundSync()
            return
        }

        let formattedName = result.fullName.map {
            PersonNameComponentsFormatter.localizedString(from: $0, style: .default)
        }?.trimmingCharacters(in: .whitespaces) ?? ""
        let emailPrefix = result.email?.components(separatedBy: "@").first ?? ""
        let displayName = !formattedName.isEmpty ? formattedName
            : (!emailPrefix.isEmpty ? emailPrefix : "Neues Mitglied")
        let username = !emailPrefix.isEmpty ? emailPrefix.lowercased() : "mitglied\(Int.random(in: 1000...9999))"

        let user = User(username: username,
                         email: result.email ?? "",
                         displayName: displayName,
                         appleUserIdentifier: result.userIdentifier)
        // The very first account ever created (locally and in CloudKit) becomes root,
        // and admin too — otherwise it'd be locked out of the admin features it needs
        // to set up the club (teams, roster, other admins) in the first place.
        if users.isEmpty, !(await CloudKitSync.shared.hasAnyUserIdentity()) {
            user.isRoot = true
            user.role = "admin"
        }
        modelContext.insert(user)
        ClubMember.checkMembership(for: user, modelContext: modelContext)
        try? modelContext.save()
        CloudKitSync.shared.pushUserIdentity(user)

        storedAppleUserIdentifier = result.userIdentifier
        currentUser = user
        triggerBackgroundSync()
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
    @Query(sort: \User.displayName) private var users: [User]

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
                                VStack(alignment: .leading) {
                                    Text(user.displayName)
                                        .foregroundStyle(.primary)
                                    Text("@\(user.username)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
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

    @State private var username = ""
    @State private var email = ""
    @State private var displayName = ""
    @State private var isCreating = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Konto") {
                    TextField("Anzeigename", text: $displayName)
                    TextField("Benutzername", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
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
                            let user = User(username: username, email: email, displayName: displayName)
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
                              username.trimmingCharacters(in: .whitespaces).isEmpty ||
                              displayName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
