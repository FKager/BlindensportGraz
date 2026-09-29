import SwiftUI
import SwiftData

/// The list of every app account (`User`), pushed from `VereinView`'s admin
/// hub as "App-Konten" — it used to self-wrap a NavigationStack + "Fertig"
/// button as a sheet off MembersListView. Only a root user sees the role
/// Picker (and never for their own row); everyone else sees roles read-only
/// under the name.
///
/// Rows show whether the account fuzzily matches a `Member` roster entry
/// (`Member.first(matching:)`). Email now syncs via CloudKit like every
/// other identity field (account-tiers refactor, decision #4 — needed so
/// LoginView's email+password form works from any device), so it's still
/// shown only when non-blank but that's just ordinary "not filled in yet",
/// not a device-locality caveat anymore.
struct UserListView: View {
    let currentUser: User
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\User.lastName), SortDescriptor(\User.firstName)]) private var users: [User]
    @Query(sort: [SortDescriptor(\Member.lastName), SortDescriptor(\Member.firstName)]) private var members: [Member]
    @State private var searchText = ""
    @State private var pendingDeletion: [User] = []
    // Role changes are one of audit.md's two explicitly-prioritized areas
    // for visible save/sync failure signaling (alongside roster edits, see
    // MembersListView) — see ServiceFailureSignal.swift.
    private let failureSignal = ServiceFailureSignal.shared

    private var filteredUsers: [User] {
        let needle = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return users }
        return users.filter { user in
            user.displayName.lowercased().contains(needle)
                || (!user.email.isEmpty && user.email.lowercased().contains(needle))
        }
    }

    // Extracted from `body` so the `List` modifier chain stays short enough
    // for the type-checker.
    private var deletionDialogShown: Binding<Bool> {
        Binding(get: { !pendingDeletion.isEmpty }, set: { if !$0 { pendingDeletion = [] } })
    }
    private var failureAlertShown: Binding<Bool> {
        Binding(get: { failureSignal.message != nil }, set: { if !$0 { failureSignal.clear() } })
    }

    var body: some View {
        List {
            Section {
                ForEach(filteredUsers) { user in
                    row(for: user)
                }
                .onDelete { offsets in
                    pendingDeletion = offsets.map { filteredUsers[$0] }.filter { $0.id != currentUser.id }
                }
            }
        }
        .navigationTitle("App-Konten")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Name oder E-Mail")
        .confirmationDialog("Konto löschen?", isPresented: deletionDialogShown, titleVisibility: .visible) {
            Button("Löschen", role: .destructive) {
                for user in pendingDeletion {
                    UserService.delete(user, modelContext: modelContext)
                }
                pendingDeletion = []
            }
            Button("Abbrechen", role: .cancel) { pendingDeletion = [] }
        } message: {
            Text("Alle Team-Mitgliedschaften und Event-Teilnahmen dieses Kontos werden ebenfalls gelöscht.")
        }
        .alert("Fehler", isPresented: failureAlertShown) {
            Button("OK") { failureSignal.clear() }
        } message: {
            Text(failureSignal.message ?? "")
        }
    }

    @ViewBuilder
    private func row(for user: User) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(user.displayName)
                    if user.isRoot {
                        Text("ROOT")
                            .font(.caption2)
                            .bold()
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .badge(tint: .orange, opacity: Theme.emphasizedBadgeOpacity)
                            .foregroundStyle(.orange)
                    }
                }
                Text(user.role.displayLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if user.isGrazerVSCMember {
                    Label("Grazer VSC", systemImage: "checkmark.seal.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
                Text("Konto seit " + user.createdAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !user.email.isEmpty {
                    Text(user.email)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if Member.first(matching: user, in: members) != nil {
                    Label("Mit Vereinsmitglied verknüpft", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                        .accessibilityLabel("Mit einem Vereinsmitglied verknüpft")
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
