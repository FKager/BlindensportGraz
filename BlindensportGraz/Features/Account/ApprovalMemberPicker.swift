import SwiftUI
import SwiftData

/// Admin picks which Benutzerverwaltung entry an app account belongs to
/// ("App-Konten" → Freigabe → "Mitglied auswählen …"). Picking one creates the
/// approval (Supabase RPC `approve_account`) that grants the account full access.
struct ApprovalMemberPicker: View {
    let user: User

    @Environment(AuthContext.self) private var authContext
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss
    @Query(sort: [SortDescriptor(\Member.lastName), SortDescriptor(\Member.firstName)]) private var members: [Member]
    @State private var searchText = ""

    private var filteredMembers: [Member] {
        let needle = searchText.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return members }
        return members.filter {
            $0.fullName.localizedStandardContains(needle) || $0.email.localizedStandardContains(needle)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(filteredMembers) { member in
                        Button {
                            approve(as: member)
                        } label: {
                            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                                Text(member.fullName)
                                    .foregroundStyle(.primary)
                                if !member.email.isEmpty {
                                    Text(member.email)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } header: {
                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(Theme.Palette.warning)
                    }
                } footer: {
                    Text("Wähle den Eintrag aus der Benutzerverwaltung, zu dem das Konto von \(user.displayName) (\(user.email)) gehört.")
                }
            }
            .navigationTitle("Mitglied auswählen")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Name oder E-Mail")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
            }
        }
    }

    private func approve(as member: Member) {
        Task {
            do {
                try await AccountApprovalService.approve(user, as: member, authContext: authContext)
                dismiss()
            } catch {
                errorMessage = AuthErrorMessage.text(for: error)
            }
        }
    }
}
