import SwiftUI
import SwiftData

struct RootView: View {
    @State private var currentUser: User?

    var body: some View {
        Group {
            if let user = currentUser {
                MainTabView(currentUser: user, onLogout: { currentUser = nil })
            } else {
                LoginView(onLogin: { user in currentUser = user })
            }
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

    @State private var username = ""
    @State private var email = ""
    @State private var displayName = ""

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
                        let user = User(username: username, email: email, displayName: displayName)
                        modelContext.insert(user)
                        try? modelContext.save()
                        dismiss()
                        onRegister(user)
                    }
                    .disabled(username.trimmingCharacters(in: .whitespaces).isEmpty ||
                              displayName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
