import SwiftUI
import SwiftData

/// Approval status and admin actions for one account in "App-Konten":
/// approve it for a Benutzerverwaltung entry (the suggested one, or picked
/// from the list), revoke an approval, or create a one-time activation code.
/// Every action is a Supabase RPC that re-checks `users.approve`.
struct UserApprovalControls: View {
    let user: User
    let onPickMember: () -> Void
    let onActivationCode: (String) -> Void

    @Environment(AuthContext.self) private var authContext
    @Query private var members: [Member]
    @Query private var approvals: [AccountApproval]
    @Query private var users: [User]
    @State private var errorMessage: String?

    private var approvedMember: Member? {
        AccessPolicy.approvedMember(for: user, roster: members, approvals: approvals, users: users)
    }

    private var suggestion: (member: Member, byEmail: Bool)? {
        AccessPolicy.suggestedMember(for: user, roster: members)
    }

    private var hasApproval: Bool {
        approvals.contains { $0.userID == user.id }
    }

    private var needsElevatedAccess: Bool {
        user.role != .admin && user.role != .root
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            status
            // Admin/root accounts have full access without an approval, but
            // the approval also links the account to its roster entry
            // (Grazer VSC membership, "Vereinsdaten bearbeiten"), so they
            // get the same actions.
            actions
        }
        .alert("Fehler", isPresented: Binding(get: { errorMessage != nil },
                                              set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @ViewBuilder
    private var status: some View {
        if !needsElevatedAccess {
            Label("Voller Zugriff als \(user.role.displayLabel)", systemImage: "checkmark.shield.fill")
                .font(.caption)
                .foregroundStyle(Theme.Palette.success)
        }
        if let approvedMember {
            Label("Freigegeben: \(approvedMember.fullName)", systemImage: "checkmark.seal.fill")
                .font(.caption)
                .foregroundStyle(Theme.Palette.success)
        } else if hasApproval {
            Label("Freigegeben (Eintrag in der Benutzerverwaltung fehlt)", systemImage: "exclamationmark.circle")
                .font(.caption)
                .foregroundStyle(Theme.Palette.warning)
        } else if let suggestion {
            Label(needsElevatedAccess
                  ? "Nicht freigegeben – Vorschlag: \(suggestion.member.fullName) (\(suggestion.byEmail ? "E-Mail" : "Name"))"
                  : "Kein Eintrag verknüpft – Vorschlag: \(suggestion.member.fullName) (\(suggestion.byEmail ? "E-Mail" : "Name"))",
                  systemImage: "questionmark.circle")
                .font(.caption)
                .foregroundStyle(Theme.Palette.warning)
        } else if needsElevatedAccess {
            Label("Nicht freigegeben – nur Termine sichtbar", systemImage: "eye.slash")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Label("Kein Eintrag in der Benutzerverwaltung verknüpft", systemImage: "questionmark.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var actions: some View {
        Menu("Freigabe", systemImage: "person.badge.shield.checkmark") {
            if hasApproval {
                Button("Freigabe entziehen", systemImage: "xmark.seal", role: .destructive) {
                    run { try await AccountApprovalService.revoke(user, authContext: authContext) }
                }
            } else {
                if let suggestion {
                    Button("Freigeben als \(suggestion.member.fullName)", systemImage: "checkmark.seal") {
                        run { try await AccountApprovalService.approve(user, as: suggestion.member, authContext: authContext) }
                    }
                }
                Button("Mitglied auswählen …", systemImage: "list.bullet", action: onPickMember)
                Button("Aktivierungscode erstellen", systemImage: "key") {
                    run {
                        let code = try await AccountApprovalService.createActivationCode(
                            for: user, member: suggestion?.member)
                        onActivationCode(code)
                    }
                }
            }
        }
        .font(.caption)
    }

    private func run(_ action: @escaping () async throws -> Void) {
        Task {
            do { try await action() }
            catch { errorMessage = AuthErrorMessage.text(for: error) }
        }
    }
}
