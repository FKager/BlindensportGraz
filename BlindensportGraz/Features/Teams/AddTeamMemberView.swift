import SwiftUI
import SwiftData
import UniformTypeIdentifiers

private enum MemberSelection: Hashable {
    case user(UUID)
    case member(UUID)
}

/// Assigns an existing `User` (registered app account) or roster `Member` to
/// a `Team` via a new `TeamMembership` — named distinctly from `Member`'s own
/// creation view (`AddMemberView`) since this doesn't
/// create a `Member`, it links one that already exists.
struct AddTeamMemberView: View {
    let team: Team
    let availableUsers: [User]
    let availableMembers: [Member]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var selection: MemberSelection?
    @State private var role = "player"

    var body: some View {
        NavigationStack {
            Form {
                Section("Mitglied") {
                    Picker("Mitglied", selection: $selection) {
                        Text("Auswählen").tag(MemberSelection?.none)
                        if !availableUsers.isEmpty {
                            Section("Registrierte Benutzer") {
                                ForEach(availableUsers) { user in
                                    Text(user.displayName).tag(MemberSelection?.some(.user(user.id)))
                                }
                            }
                        }
                        if !availableMembers.isEmpty {
                            Section("Mitglieder ohne Konto") {
                                ForEach(availableMembers) { member in
                                    Text(member.fullName).tag(MemberSelection?.some(.member(member.id)))
                                }
                            }
                        }
                    }
                }
                Section("Rolle") {
                    Picker("Rolle", selection: $role) {
                        Text("Spieler:in").tag("player")
                        Text("Trainer:in").tag("coach")
                        Text("Assistent:in").tag("assistant")
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle("Mitglied hinzufügen")
            .navigationBarTitleDisplayMode(.inline)
            // Pre-fills Rolle from the picked Member's own defaultFunction
            // (e.g. the Sportler/Helfer choice made at self-service
            // registration time, see AccountView's "Mitgliedschaft
            // beantragen" — Member.swift's doc comment on defaultFunction:
            // "to pre-fill role when assigning them to a team", previously
            // not actually wired up anywhere). Only fires when `selection`
            // itself changes, not on every `role` edit, so admins can still
            // freely override the pre-filled value afterward without it
            // snapping back. A `.user` selection (no defaultFunction to read —
            // that field only exists on Member) or an unrecognized/blank
            // defaultFunction both fall back to the segmented control's
            // existing "player" default rather than left blank/mismatched.
            .onChange(of: selection) { _, newValue in
                role = defaultRole(for: newValue)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Hinzufügen") {
                        let membership: TeamMembership?
                        switch selection {
                        case .user(let id):
                            guard let user = availableUsers.first(where: { $0.id == id }) else { membership = nil; break }
                            membership = TeamMembership(user: user, team: team, role: MembershipRole.normalize(role))
                        case .member(let id):
                            guard let member = availableMembers.first(where: { $0.id == id }) else { membership = nil; break }
                            membership = TeamMembership(member: member, team: team, role: MembershipRole.normalize(role))
                        case nil:
                            membership = nil
                        }
                        if let membership {
                            modelContext.insert(membership)
                            TeamMembershipService.save(membership, modelContext: modelContext)
                        }
                        dismiss()
                    }
                    .disabled(selection == nil)
                }
            }
        }
    }

    /// Only `.member` selections carry a `defaultFunction` (`User` has no
    /// such field) — falls back to "player" for a `.user` selection or no
    /// selection; `Member.preferredMembershipRoleRawValue` itself handles
    /// falling back for a blank/unrecognized `defaultFunction`.
    private func defaultRole(for selection: MemberSelection?) -> String {
        guard case .member(let id) = selection,
              let member = availableMembers.first(where: { $0.id == id }) else { return "player" }
        return member.preferredMembershipRoleRawValue
    }
}
