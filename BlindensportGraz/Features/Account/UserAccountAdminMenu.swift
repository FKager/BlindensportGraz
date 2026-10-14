import SwiftUI
import SwiftData

/// "Konto" menu on a `UserListView` row, for root (`roles.assign`), never on
/// the own row and never on a root account (demote it first): block (lock)
/// / unblock an account, or delete it for good. Both destructive actions
/// confirm first and name the account by name *and* email, since names can
/// repeat. The RPCs enforce the same rules server-side and write
/// `account_admin_log`.
struct UserAccountAdminMenu: View {
    let user: User
    let isBlocked: Bool
    /// Called after a successful change; reloads the list from the server,
    /// which also drops a deleted account from the local cache
    /// (`AuthContext.mirrorServerState`) — deleting it here, while this row
    /// still renders it, could crash SwiftData.
    let onChange: () async -> Void

    @State private var confirmBlock = false
    @State private var confirmDelete = false
    @State private var isWorking = false
    @State private var errorMessage: String?

    private var accountLabel: String {
        user.email.isEmpty ? user.displayName : "\(user.displayName) (\(user.email))"
    }

    var body: some View {
        Menu("Konto", systemImage: "person.crop.circle.badge.exclamationmark") {
            if isBlocked {
                Button("Entsperren", systemImage: "lock.open") {
                    run(announce: String(localized: "\(user.displayName) entsperrt.")) {
                        try await SupabaseAccountAdminService.setBlocked(false, userID: user.id)
                    }
                }
            } else {
                Button("Sperren …", systemImage: "lock") { confirmBlock = true }
            }
            Button("Löschen …", systemImage: "trash", role: .destructive) { confirmDelete = true }
        }
        .font(.caption)
        .disabled(isWorking)
        .confirmationDialog("\(accountLabel) sperren?", isPresented: $confirmBlock,
                            titleVisibility: .visible) {
            Button("Sperren", role: .destructive) {
                run(announce: String(localized: "\(user.displayName) gesperrt.")) {
                    try await SupabaseAccountAdminService.setBlocked(true, userID: user.id)
                }
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Das Konto wird auf allen Geräten abgemeldet und kann sich nicht mehr anmelden, bis du es entsperrst. Der Kalender-Link wird ungültig. Daten, Rolle und Freigabe bleiben erhalten.")
        }
        .confirmationDialog("\(accountLabel) endgültig löschen?", isPresented: $confirmDelete,
                            titleVisibility: .visible) {
            Button("Konto löschen", role: .destructive) {
                run(announce: String(localized: "\(user.displayName) gelöscht.")) {
                    try await SupabaseAccountAdminService.delete(userID: user.id)
                }
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Das App-Konto, seine Rolle, Freigabe, Teilnahmen und Teamzuordnungen werden gelöscht. Das kann nicht rückgängig gemacht werden. Der Eintrag in der Benutzerverwaltung bleibt.\n\nMit derselben E-Mail-Adresse kann sich die Person neu registrieren. Um das zu verhindern, sperre das Konto stattdessen.")
        }
        .alert("Fehler", isPresented: Binding(get: { errorMessage != nil },
                                              set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func run(announce: String, _ action: @escaping () async throws -> Void) {
        guard !isWorking else { return }
        isWorking = true
        Task {
            defer { isWorking = false }
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
