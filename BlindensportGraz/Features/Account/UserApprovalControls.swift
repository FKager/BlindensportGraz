import SwiftUI
import SwiftData

/// Approval status and admin actions for one account in "App-Konten":
/// approve it for a Benutzerverwaltung entry (the suggested one, or picked
/// from the list), revoke an approval, or create a one-time activation code
/// for an account without a password. See `AccountApproval`.
struct UserApprovalControls: View {
    let user: User
    let currentUser: User
    let onPickMember: () -> Void
    let onActivationCode: (String) -> Void

    @Environment(\.modelContext) private var modelContext
    @Query private var members: [Member]
    @Query private var approvals: [AccountApproval]
    @Query private var users: [User]

    private var approvedMember: Member? {
        AccessPolicy.approvedMember(for: user, roster: members, approvals: approvals, users: users)
    }

    private var suggestion: (member: Member, byEmail: Bool)? {
        AccessPolicy.suggestedMember(for: user, roster: members)
    }

    private var activeApproval: AccountApproval? {
        AccessPolicy.activeApproval(for: user, roster: members, approvals: approvals, users: users)
    }

    /// CloudKit only lets a record's creator delete it.
    private var canRevoke: Bool {
        activeApproval?.approvedBy == currentUser.id.uuidString
    }

    private var needsElevatedAccess: Bool {
        user.role != .admin && !user.isRoot
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            status
            if needsElevatedAccess || user.passwordHash.isEmpty {
                actions
            }
        }
    }

    @ViewBuilder
    private var status: some View {
        if !needsElevatedAccess {
            Label("Voller Zugriff als \(user.isRoot ? "Root" : "Admin")", systemImage: "checkmark.shield.fill")
                .font(.caption)
                .foregroundStyle(Theme.Palette.success)
        } else if let approvedMember {
            Label("Freigegeben: \(approvedMember.fullName)", systemImage: "checkmark.seal.fill")
                .font(.caption)
                .foregroundStyle(Theme.Palette.success)
        } else if let suggestion {
            Label("Nicht freigegeben – Vorschlag: \(suggestion.member.fullName) (\(suggestion.byEmail ? "E-Mail" : "Name"))",
                  systemImage: "questionmark.circle")
                .font(.caption)
                .foregroundStyle(Theme.Palette.warning)
        } else {
            Label("Nicht freigegeben – nur Termine sichtbar", systemImage: "eye.slash")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var actions: some View {
        Menu("Freigabe", systemImage: "person.badge.shield.checkmark") {
            if needsElevatedAccess {
                if activeApproval != nil {
                    Button("Freigabe entziehen", systemImage: "xmark.seal", role: .destructive, action: revoke)
                        .disabled(!canRevoke)
                    if !canRevoke {
                        Text("Nur der Admin, der freigegeben hat, kann die Freigabe entziehen.")
                    }
                } else {
                    if let suggestion {
                        Button("Freigeben als \(suggestion.member.fullName)", systemImage: "checkmark.seal") {
                            approve(as: suggestion.member)
                        }
                    }
                    Button("Mitglied auswählen …", systemImage: "list.bullet", action: onPickMember)
                }
            }
            if user.passwordHash.isEmpty {
                Button("Aktivierungscode erstellen", systemImage: "key", action: createActivationCode)
            }
        }
        .font(.caption)
    }

    private func approve(as member: Member) {
        AccountApprovalService.approve(user, as: member, by: currentUser, modelContext: modelContext)
    }

    private func revoke() {
        guard let activeApproval else { return }
        AccountApprovalService.revoke(activeApproval, modelContext: modelContext)
    }

    private func createActivationCode() {
        if let code = AccountApprovalService.createActivationCode(for: user, by: currentUser, modelContext: modelContext) {
            onActivationCode(code)
        }
    }
}
