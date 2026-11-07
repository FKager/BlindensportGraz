import SwiftUI
import SwiftData

/// Role-change audit log from Supabase (`role_change_log`, written by a
/// database trigger on every role change; readable with `rolelog.read`),
/// plus root's account blocks, unblocks and deletions (`account_admin_log`,
/// which keeps the email and name of deleted accounts). Pushed from
/// `VereinView`'s admin hub.
struct RoleChangeLogView: View {
    @Query private var users: [User]
    @State private var entries: [SupabaseRoleChange] = []
    @State private var accountEntries: [SupabaseAccountAdminLogEntry] = []
    @State private var functionEntries: [ClubFunctionLogEntry] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        List {
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Theme.Palette.warning)
            } else if entries.isEmpty, accountEntries.isEmpty, functionEntries.isEmpty, !isLoading {
                ContentUnavailableView("Keine Rollenänderungen",
                                       systemImage: "clock.arrow.circlepath",
                                       description: Text("Änderungen an Benutzerrollen erscheinen hier."))
            } else {
                if !functionEntries.isEmpty {
                    Section("Vereinsfunktionen") {
                        ForEach(functionEntries) { entry in
                            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                                Text("\(entry.functionLabel): \(entry.oldLabel) → \(entry.newLabel)")
                                    .font(.body)
                                Text("Geändert von \(changedByLabel(entry.changedBy)) am \(entry.changedAt.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
                if !accountEntries.isEmpty {
                    Section("Sperren und Löschen") {
                        ForEach(accountEntries) { entry in
                            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                                Text("\(entry.targetLabel): \(entry.actionLabel)")
                                    .font(.body)
                                Text("Von \(changedByLabel(entry.actor)) am \(entry.at.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
                if !entries.isEmpty {
                Section("Rollen") {
                ForEach(entries) { entry in
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text("\(displayName(for: entry.userID)): \(label(entry.oldRole)) → \(label(entry.newRole))")
                            .font(.body)
                        Text("Geändert von \(changedByLabel(entry.changedBy)) am \(entry.changedAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
                }
                }
            }
        }
        .overlay { if isLoading { ProgressView() } }
        .navigationTitle("Rollenänderungen")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        defer { isLoading = false }
        do {
            entries = try await SupabaseRoleService.fetchChangeLog()
            accountEntries = try await SupabaseAccountAdminService.fetchLog()
            functionEntries = try await ClubFunctionService.fetchLog()
            errorMessage = nil
        } catch {
            errorMessage = AuthErrorMessage.text(for: error)
        }
    }

    private func label(_ role: String?) -> String {
        role.map { AppRole.normalize($0).displayLabel } ?? String(localized: "ausstehend")
    }

    private func displayName(for userID: UUID) -> String {
        users.first { $0.id == userID }?.displayName ?? "?"
    }

    /// nil = system (migration, seed, RootCLI with the service key).
    private func changedByLabel(_ changedBy: UUID?) -> String {
        guard let changedBy else { return String(localized: "System") }
        return users.first { $0.id == changedBy }?.displayName ?? changedBy.uuidString
    }
}
