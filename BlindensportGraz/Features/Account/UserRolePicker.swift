import SwiftUI
import SwiftData

/// App-role picker (Mitglied / Trainer:in / Admin) on a `UserListView` row.
/// Only a root user sees it, and never on their own row (see the gate in
/// `UserListView`), so it can't be used for self-promotion.
///
/// Bound to local `@State`, not the model: only a user's pick saves the user
/// and writes a `RoleChangeLog` entry. A role written into the same `User`
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

    private func changeRole(to newRole: AppRole) {
        let oldRole = user.role
        guard newRole != oldRole else { return }
        user.role = newRole
        guard UserService.save(user, modelContext: modelContext) else { return }
        RoleChangeLogService.log(userID: user.id, oldRole: oldRole.rawValue, newRole: newRole.rawValue,
                                 changedBy: currentUser.id.uuidString, modelContext: modelContext)
    }
}
