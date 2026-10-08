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
/// a roster entry in one go. Accounts, roles and approvals come from Supabase
/// (mirrored locally by `AuthContext`); deleting an account is done by the
/// person themselves (Account → Konto löschen), not from this list.
struct UserListView: View {
    let currentUser: User
    @Environment(AuthContext.self) private var authContext
    @Query(sort: [SortDescriptor(\User.lastName), SortDescriptor(\User.firstName)]) private var users: [User]
    @Query(sort: [SortDescriptor(\Member.lastName), SortDescriptor(\Member.firstName)]) private var members: [Member]
    @State private var searchText = ""
    @Query private var approvals: [AccountApproval]
    @State private var pickingMemberFor: User?
    @State private var activationCodeInfo: (user: String, code: String)?
    @State private var showBulkApproval = false
    @State private var errorMessage: String?

    private var filteredUsers: [User] {
        let needle = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        // Name-only directory rows (no email) are other accounts' cache
        // entries for non-approvers; admins get full profiles.
        let accounts = users.filter { !$0.email.isEmpty }
        guard !needle.isEmpty else { return accounts }
        return accounts.filter { user in
            user.displayName.lowercased().contains(needle)
                || (!user.email.isEmpty && user.email.lowercased().contains(needle))
        }
    }

    // Extracted from `body` so the `List` modifier chain stays short enough
    // for the type-checker.
    private var errorShown: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    /// Unapproved non-admin accounts whose email matches a roster entry.
    private var emailSuggestions: [(user: User, member: Member)] {
        filteredUsers.compactMap { user in
            guard user.role != .admin, user.role != .root,
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
            }
        }
        .navigationTitle("App-Konten")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await authContext.reload() }
        .toolbar {
            if !emailSuggestions.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button("E-Mail-Vorschläge bestätigen", systemImage: "checkmark.seal") {
                        showBulkApproval = true
                    }
                    .confirmationDialog("\(emailSuggestions.count) Konten freigeben?", isPresented: $showBulkApproval,
                                        titleVisibility: .visible) {
                        Button("Freigeben") { Task { await approveEmailSuggestions() } }
                        Button("Abbrechen", role: .cancel) {}
                    } message: {
                        Text("Jedes Konto wird mit dem Eintrag in der Benutzerverwaltung verknüpft, der dieselbe E-Mail-Adresse hat.")
                    }
                }
            }
        }
        .sheet(item: $pickingMemberFor) { user in
            ApprovalMemberPicker(user: user)
        }
        .alert("Aktivierungscode", isPresented: activationCodeShown) {
        } message: {
            if let activationCodeInfo {
                Text("Code für \(activationCodeInfo.user): \(activationCodeInfo.code)\n\nBitte persönlich weitergeben. Der Code wird nur jetzt angezeigt, gilt 14 Tage und kann nur in diesem Konto eingelöst werden (Account → Aktivierungscode einlösen).")
            }
        }
        .searchable(text: $searchText, prompt: "Name oder E-Mail")
        .alert("Fehler", isPresented: errorShown) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @ViewBuilder
    private func row(for user: User) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                HStack(spacing: Theme.Spacing.s) {
                    Text(user.displayName)
                    if user.role == .root {
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
                UserApprovalControls(user: user,
                                     onPickMember: { pickingMemberFor = user },
                                     onActivationCode: { activationCodeInfo = (user.displayName, $0) })
            }
            Spacer()
            if authContext.can(.rolesAssign) && user.id != currentUser.id {
                UserRolePicker(user: user)
            }
        }
    }

    private func approveEmailSuggestions() async {
        for suggestion in emailSuggestions {
            do {
                try await SupabaseApprovalService.approve(userID: suggestion.user.id, memberID: suggestion.member.id)
            } catch {
                errorMessage = AuthErrorMessage.text(for: error)
                break
            }
        }
        await authContext.reload()
    }
}
