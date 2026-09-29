import SwiftUI
import SwiftData

/// Tappable role capsule on a `TeamDetailView` roster row; opens a menu to
/// change the membership's team role (Spieler:in / Trainer:in / Assistent:in).
///
/// The picker is bound to local `@State`: only a user's pick saves and
/// re-pushes the membership. A role written into the same `TeamMembership`
/// by a CloudKit pull just updates the display, so it's never pushed back.
struct MembershipRoleMenu: View {
    let membership: TeamMembership

    @Environment(\.modelContext) private var modelContext
    @State private var role: MembershipRole = .player

    var body: some View {
        Menu {
            Picker("Rolle", selection: $role) {
                Text("Spieler:in").tag(MembershipRole.player)
                Text("Trainer:in").tag(MembershipRole.coach)
                Text("Assistent:in").tag(MembershipRole.assistant)
            }
        } label: {
            MembershipRoleCapsule(role: membership.role)
        }
        .accessibilityLabel("Rolle: \(membership.role.displayLabel)")
        .accessibilityHint("Doppeltippen, um die Rolle zu ändern")
        .onChange(of: membership.role, initial: true) { _, stored in
            role = stored
        }
        .onChange(of: role) { _, newRole in
            guard newRole != membership.role else { return }
            membership.role = newRole
            TeamMembershipService.save(membership, modelContext: modelContext)
        }
    }
}
