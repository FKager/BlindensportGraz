import SwiftUI
import SwiftData

/// The list of every app account (`User`), pushed from `VereinView`'s admin
/// hub as "App-Konten" — it used to self-wrap a NavigationStack + "Fertig"
/// button as a sheet off MembersListView. Only a root user sees the role
/// Picker (and never for their own row); everyone else sees roles read-only
/// under the name.
///
/// Rows show each account's approval: full access needs an admin's approval
/// linking it to a Benutzerverwaltung entry (`AccountApproval`,
/// `UserApprovalControls`); a matching name/email is only a suggestion.
/// "E-Mail-Vorschläge bestätigen" approves every account whose email matches
/// a roster entry in one go (e.g. once after this approval step was added). Email now syncs via CloudKit like every
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
    @Query private var approvals: [AccountApproval]
    @State private var pickingMemberFor: User?
    @State private var activationCodeInfo: (user: String, code: String)?
    @State private var showBulkApproval = false
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

    /// Unapproved non-admin accounts whose email matches a roster entry.
    private var emailSuggestions: [(user: User, member: Member)] {
        users.compactMap { user in
            guard user.role != .admin, !user.isRoot,
                  AccessPolicy.approvedMember(for: user, roster: members, approvals: approvals, users: users) == nil,
                  let suggestion = AccessPolicy.suggestedMember(for: user, roster: members), suggestion.byEmail
            else { return nil }
            return (user, suggestion.member)
        }
    }

    private var activationCodeShown: Binding<Bool> {
        Binding(get: { activationCodeInfo != nil }, set: { if !$0 { activationCodeInfo = nil } })
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
        .toolbar {
            if !emailSuggestions.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button("E-Mail-Vorschläge bestätigen", systemImage: "checkmark.seal") {
                        showBulkApproval = true
                    }
                    .confirmationDialog("\(emailSuggestions.count) Konten freigeben?", isPresented: $showBulkApproval,
                                        titleVisibility: .visible) {
                        Button("Freigeben", action: approveEmailSuggestions)
                        Button("Abbrechen", role: .cancel) {}
                    } message: {
                        Text("Jedes Konto wird mit dem Eintrag in der Benutzerverwaltung verknüpft, der dieselbe E-Mail-Adresse hat.")
                    }
                }
            }
        }
        .sheet(item: $pickingMemberFor) { user in
            ApprovalMemberPicker(user: user, admin: currentUser)
        }
        .alert("Aktivierungscode", isPresented: activationCodeShown) {
        } message: {
            if let activationCodeInfo {
                Text("Code für \(activationCodeInfo.user): \(activationCodeInfo.code)\n\nBitte persönlich weitergeben. Der Code wird nur jetzt angezeigt; damit kann einmalig ein Passwort festgelegt werden.")
            }
        }
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
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                HStack(spacing: Theme.Spacing.s) {
                    Text(user.displayName)
                    if user.isRoot {
                        TagLabel("ROOT", tint: Theme.Palette.warning, emphasized: true)
                    }
                }
                Text(user.role.displayLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Konto seit " + user.createdAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !user.email.isEmpty {
                    Text(user.email)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                UserApprovalControls(user: user, currentUser: currentUser,
                                     onPickMember: { pickingMemberFor = user },
                                     onActivationCode: { activationCodeInfo = (user.displayName, $0) })
            }
            Spacer()
            if currentUser.isRoot && user.id != currentUser.id {
                UserRolePicker(user: user, currentUser: currentUser)
            }
        }
    }

    private func approveEmailSuggestions() {
        for suggestion in emailSuggestions {
            AccountApprovalService.approve(suggestion.user, as: suggestion.member, by: currentUser, modelContext: modelContext)
        }
    }
}
