import SwiftUI
import SwiftData

/// "Rollen" in the Verein tab: who holds the Vereinsfunktionen, who is Admin
/// and Root, and the Rollenänderungen log. Admins and root change the
/// functions, which give no rights. Only root changes Admin and Root, which
/// belong to app accounts and can have several people.
struct RolesView: View {
    let currentUser: User

    @Environment(AuthContext.self) private var authContext
    @Query(sort: [SortDescriptor(\Member.lastName), SortDescriptor(\Member.firstName)])
    private var members: [Member]
    @Query private var users: [User]
    @State private var holders: [ClubFunction: UUID] = [:]
    @State private var isLoading = true
    @State private var errorMessage: String?

    private var canChangeAccounts: Bool { authContext.can(.rolesAssign) }

    private func accounts(in role: AppRole) -> [User] {
        users.filter { $0.role == role }.sorted { $0.displayName < $1.displayName }
    }

    /// Everyone who can be added to `role`: not yet in it, and not oneself,
    /// as nobody can change their own role.
    private func candidates(for role: AppRole) -> [User] {
        users.filter { $0.role != role && $0.id != currentUser.id }.sorted { $0.displayName < $1.displayName }
    }

    private var selectableMembers: [Member] {
        members.filter { $0.status != MemberStatus.delete.rawValue }
    }

    var body: some View {
        List {
            Section {
                ForEach(ClubFunction.allCases) { function in
                    Picker(function.label, selection: holderBinding(function)) {
                        Text("Nicht besetzt").tag(UUID?.none)
                        ForEach(selectableMembers) { member in
                            Text("\(member.lastName), \(member.firstName)").tag(UUID?.some(member.id))
                        }
                    }
                    .disabled(isLoading)
                }
            } header: {
                Text("Vereinsfunktionen")
            } footer: {
                Text("Halten fest, wer welche Funktion hat. Sie geben keine zusätzlichen Rechte.")
            }

            accountSection("Admin", role: .admin)
            accountSection("Root", role: .root)

            Section("Protokoll") {
                NavigationLink(value: AppRoute.roleChangeLog) {
                    Label("Rollenänderungen", systemImage: "clock.arrow.circlepath")
                }
            }
        }
        .navigationTitle("Rollen")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .alert("Rolle nicht geändert", isPresented: Binding(get: { errorMessage != nil },
                                                           set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func accountSection(_ title: String, role: AppRole) -> some View {
        Section(title) {
            let holders = accounts(in: role)
            if holders.isEmpty {
                Text("Niemand")
                    .foregroundStyle(.secondary)
            }
            ForEach(holders) { user in
                Text(user.displayName)
                    .swipeActions {
                        if canChangeAccounts && user.id != currentUser.id {
                            Button("Entfernen", role: .destructive) { setRole(.member, for: user) }
                        }
                    }
            }
            if canChangeAccounts {
                Picker("\(title) hinzufügen", selection: addBinding(role: role)) {
                    Text("Bitte wählen").tag(UUID?.none)
                    ForEach(candidates(for: role)) { user in
                        Text(user.displayName).tag(UUID?.some(user.id))
                    }
                }
            }
        }
    }

    private func holderBinding(_ function: ClubFunction) -> Binding<UUID?> {
        Binding(get: { holders[function] }, set: { memberID in
            let previous = holders[function]
            holders[function] = memberID
            Task {
                do {
                    try await ClubFunctionService.set(function, memberID: memberID)
                } catch {
                    holders[function] = previous
                    errorMessage = AuthErrorMessage.text(for: error)
                }
            }
        })
    }

    private func addBinding(role: AppRole) -> Binding<UUID?> {
        Binding(get: { nil }, set: { id in
            guard let user = users.first(where: { $0.id == id }) else { return }
            setRole(role, for: user)
        })
    }

    private func setRole(_ role: AppRole, for user: User) {
        Task {
            do {
                try await AccountApprovalService.setRole(role, for: user, authContext: authContext)
            } catch {
                errorMessage = AuthErrorMessage.text(for: error)
            }
        }
    }

    private func load() async {
        defer { isLoading = false }
        do {
            holders = try await ClubFunctionService.fetchHolders()
        } catch {
            errorMessage = AuthErrorMessage.text(for: error)
        }
    }
}
