import SwiftUI
import SwiftData

/// App-role picker on a `UserListView` row. Shown only with `roles.assign`
/// (root) and never on the own row; the `set_user_role` RPC enforces the same
/// rules (no self-change, last root protected) and a trigger writes the
/// audit log.
///
/// Bound to local `@State`: only a user's pick calls the RPC; a role that
/// arrives from the server just updates the display.
struct UserRolePicker: View {
    let user: User

    @Environment(AuthContext.self) private var authContext
    @State private var role: AppRole = .member
    @State private var errorMessage: String?

    var body: some View {
        Picker("Rolle", selection: $role) {
            Text("Mitglied").tag(AppRole.member)
            Text("Trainer:in").tag(AppRole.coach)
            Text("Admin").tag(AppRole.admin)
            Text("Root").tag(AppRole.root)
        }
        .labelsHidden()
        .onChange(of: user.role, initial: true) { _, stored in
            role = stored
        }
        .onChange(of: role) { _, newRole in
            changeRole(to: newRole)
        }
        .alert("Rolle nicht geändert", isPresented: Binding(get: { errorMessage != nil },
                                                           set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func changeRole(to newRole: AppRole) {
        guard newRole != user.role else { return }
        Task {
            do {
                try await AccountApprovalService.setRole(newRole, for: user, authContext: authContext)
            } catch {
                errorMessage = AuthErrorMessage.text(for: error)
                role = user.role
            }
        }
    }
}
