import SwiftUI
import SwiftData

/// Admin-only view of `RoleChangeLog` entries, newest first — audit.md P0
/// enhancement #2. Pushed from `VereinView`'s admin hub (previously a sheet
/// off MembersListView), so it no longer wraps its own NavigationStack.
struct RoleChangeLogView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \RoleChangeLog.changedAt, order: .reverse) private var entries: [RoleChangeLog]
    @Query private var users: [User]

    var body: some View {
        List {
            if entries.isEmpty {
                ContentUnavailableView("Keine Rollenänderungen",
                                       systemImage: "clock.arrow.circlepath",
                                       description: Text("Änderungen an Benutzerrollen erscheinen hier."))
            } else {
                ForEach(entries) { entry in
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text("\(displayName(for: entry.userID)): \(entry.oldRole) → \(entry.newRole)")
                            .font(.body)
                        Text("Geändert von \(changedByLabel(entry.changedBy)) am \(entry.changedAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Rollenänderungen")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await SyncOrchestrationService.syncAll(modelContext: modelContext)
        }
    }

    private func displayName(for userID: UUID) -> String {
        users.first { $0.id == userID }?.displayName ?? "?"
    }

    /// `changedBy` is either an acting User's `id` (uuidString) or a fixed
    /// "system:<mechanism>" tag — resolve the former to a display name,
    /// leave the latter as-is.
    private func changedByLabel(_ changedBy: String) -> String {
        guard let id = UUID(uuidString: changedBy) else { return changedBy }
        return users.first { $0.id == id }?.displayName ?? changedBy
    }
}
