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
                            Text(user.email)
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

                    if user.role == "admin" || user.isRoot {
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
            if let user = currentUser {
                UserListView(currentUser: user)
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
                }
                Section {
                    LabeledContent("Rolle", value: roleLabel(user.role))
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
                }
            }
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

struct UserListView: View {
    let currentUser: User
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \User.createdAt) private var users: [User]
    @Environment(\.dismiss) private var dismiss

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
                            Text(user.role)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
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

    /// Only a root user reaches this binding (see the `currentUser.isRoot` gate above),
    /// and never for their own row — so this can never be used for self-promotion.
    private func roleBinding(for user: User) -> Binding<String> {
        Binding(
            get: { user.role },
            set: { newRole in
                user.role = newRole
                try? modelContext.save()
                CloudKitSync.shared.pushUserIdentity(user)
            }
        )
    }
}
