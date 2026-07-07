import SwiftUI
import SwiftData

struct AccountView: View {
    let currentUser: User?
    let onLogout: () -> Void
    @Environment(\.modelContext) private var modelContext
    @Query private var allUsers: [User]

    @State private var showEdit = false
    @State private var showUserList = false

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
                            Text("@\(user.username)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(roleLabel(user.role))
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
                }

                Section {
                    Button {
                        showEdit = true
                    } label: {
                        Label("Profil bearbeiten", systemImage: "pencil")
                    }

                    if user.role == "admin" {
                        Button {
                            showUserList = true
                        } label: {
                            Label("Benutzer verwalten", systemImage: "person.2.fill")
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
        .sheet(isPresented: $showUserList) {
            UserListView()
        }
    }

    private func roleLabel(_ role: String) -> String {
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

    var body: some View {
        NavigationStack {
            Form {
                Section("Profil") {
                    TextField("Anzeigename", text: $user.displayName)
                    TextField("E-Mail", text: $user.email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Section("Rolle") {
                    Picker("Rolle", selection: $user.role) {
                        Text("Mitglied").tag("member")
                        Text("Trainer:in").tag("coach")
                        Text("Admin").tag("admin")
                    }
                }
            }
            .navigationTitle("Profil bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
    }
}

struct UserListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \User.createdAt) private var users: [User]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(users) { user in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(user.displayName)
                            Text("@\(user.username)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(user.role)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .onDelete { offsets in
                    for index in offsets {
                        modelContext.delete(users[index])
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
        }
    }
}
