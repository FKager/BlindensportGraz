import SwiftUI
import SwiftData

/// "Konto" menu on a `UserListView` row, for root (`roles.assign`) and never
/// on the own row: block (lock) / unblock an account, or delete it for good
/// after a confirmation. The RPCs enforce the same rules server-side.
struct UserAccountAdminMenu: View {
    let user: User
    let isBlocked: Bool
    /// Called after a successful change, so the list reloads its state.
    let onChange: () async -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var confirmBlock = false
    @State private var confirmDelete = false
    @State private var errorMessage: String?

    var body: some View {
        Menu("Konto", systemImage: "person.crop.circle.badge.exclamationmark") {
            if isBlocked {
                Button("Entsperren", systemImage: "lock.open") {
                    run(announce: "\(user.displayName) entsperrt.") {
                        try await SupabaseAccountAdminService.setBlocked(false, userID: user.id)
                    }
                }
            } else {
                Button("Sperren …", systemImage: "lock") { confirmBlock = true }
            }
            Button("Löschen …", systemImage: "trash", role: .destructive) { confirmDelete = true }
        }
        .font(.caption)
        .confirmationDialog("\(user.displayName) sperren?", isPresented: $confirmBlock,
                            titleVisibility: .visible) {
            Button("Sperren", role: .destructive) {
                run(announce: "\(user.displayName) gesperrt.") {
                    try await SupabaseAccountAdminService.setBlocked(true, userID: user.id)
                }
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Das Konto wird auf allen Geräten abgemeldet und kann sich nicht mehr anmelden, bis du es entsperrst. Daten, Rolle und Freigabe bleiben erhalten.")
        }
        .confirmationDialog("\(user.displayName) endgültig löschen?", isPresented: $confirmDelete,
                            titleVisibility: .visible) {
            Button("Konto löschen", role: .destructive) {
                let name = user.displayName
                run(announce: "\(name) gelöscht.") {
                    try await SupabaseAccountAdminService.delete(userID: user.id)
                    modelContext.delete(user)
                    try? modelContext.save()
                }
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Das App-Konto, seine Rolle, Freigabe, Teilnahmen und Teamzuordnungen werden gelöscht. Das kann nicht rückgängig gemacht werden. Der Eintrag in der Benutzerverwaltung bleibt.")
        }
        .alert("Fehler", isPresented: Binding(get: { errorMessage != nil },
                                              set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func run(announce: String, _ action: @escaping () async throws -> Void) {
        Task {
            do {
                try await action()
                AccessibilityNotification.Announcement(announce).post()
                await onChange()
            } catch {
                errorMessage = AuthErrorMessage.text(for: error)
            }
        }
    }
}
