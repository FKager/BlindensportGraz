import SwiftUI
import SwiftData

/// App-role picker (Mitglied / Trainer:in / Admin) on a `UserListView` row.
/// Only a root user sees it, and never on their own row (see the gate in
/// `UserListView`), so it can't be used for self-promotion.
///
/// Bound to local `@State`, not the model: only a user's pick records a
/// `RoleAssignment` and writes a `RoleChangeLog` entry. A role written into the same `User`
/// by a CloudKit pull just updates the display — otherwise every synced role
/// change would be re-pushed and logged again as if this viewer had made it.
struct UserRolePicker: View {
    let user: User
    let currentUser: User

    @Environment(\.modelContext) private var modelContext
    @State private var role: AppRole = .member

    var body: some View {
        Picker("Rolle", selection: $role) {
            Text("Mitglied").tag(AppRole.member)
            Text("Trainer:in").tag(AppRole.coach)
            Text("Admin").tag(AppRole.admin)
        }
        .labelsHidden()
        .onChange(of: user.role, initial: true) { _, stored in
            role = stored
        }
        .onChange(of: role) { _, newRole in
            changeRole(to: newRole)
        }
    }

    /// Recorded as a `RoleAssignment` owned by the root user — writing the
    /// other account's own record would be rejected by iCloud (creator-only
    /// writes), so the change used to stay on this device.
    private func changeRole(to newRole: AppRole) {
        guard newRole != user.role else { return }
        RoleAssignmentService.assign(newRole, to: user, by: currentUser, modelContext: modelContext)
    }
}
