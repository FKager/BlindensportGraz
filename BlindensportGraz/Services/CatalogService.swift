import Foundation
import Supabase
import SwiftData

/// Edits the club's sport and event-type lists directly on the server (an
/// online screen, like Rollen): the lists are small, admin-only and
/// renames must reach every row that uses the old name in one transaction
/// (`rename_sport` / `rename_event_type`). After each change the two lists
/// are pulled again, so the local cache (`ClubSport`/`EventType`) and the
/// renamed events, teams and favourites follow.
///
/// The server checks club.manage on every call (RLS and the functions).
@MainActor
enum CatalogService {
    private static var client: SupabaseClient { SupabaseClientSingleton.shared.client }

    // MARK: - Sports

    static func addSport(name: String, sortOrder: Int) async throws {
        try await client.from("sports")
            .insert(SportDBRow(id: UUID(), name: clean(name), isActive: true, sortOrder: sortOrder))
            .execute()
    }

    static func renameSport(id: UUID, to name: String) async throws {
        nonisolated struct Params: Encodable { let p_id: UUID; let p_name: String }
        try await client.rpc("rename_sport", params: Params(p_id: id, p_name: clean(name))).execute()
    }

    static func setSport(id: UUID, isActive: Bool) async throws {
        try await client.from("sports").update(ActiveFlag(is_active: isActive)).eq("id", value: id).execute()
    }

    // MARK: - Event types

    static func addEventType(name: String, behavior: EventType.Behavior, sortOrder: Int) async throws {
        try await client.from("event_types")
            .insert(EventTypeDBRow(id: UUID(), name: clean(name), behavior: behavior.rawValue,
                                   isActive: true, sortOrder: sortOrder))
            .execute()
    }

    static func renameEventType(id: UUID, to name: String) async throws {
        nonisolated struct Params: Encodable { let p_id: UUID; let p_name: String }
        try await client.rpc("rename_event_type", params: Params(p_id: id, p_name: clean(name))).execute()
    }

    static func setEventType(id: UUID, isActive: Bool) async throws {
        try await client.from("event_types").update(ActiveFlag(is_active: isActive)).eq("id", value: id).execute()
    }

    // MARK: - Order

    /// Stores the given order as sort_order 10, 20, 30 …
    static func reorder(table: String, ids: [UUID]) async throws {
        nonisolated struct Order: Encodable { let sort_order: Int }
        for (index, id) in ids.enumerated() {
            try await client.from(table).update(Order(sort_order: (index + 1) * 10)).eq("id", value: id).execute()
        }
    }

    /// Next free sort_order after the given ones.
    static func nextSortOrder(after orders: [Int]) -> Int {
        ((orders.max() ?? 0) / 10 + 1) * 10
    }

    // MARK: - Refresh

    /// Pulls both lists, plus the events, teams and favourites a rename
    /// touched (incremental, so cheap).
    static func refresh(modelContext: ModelContext) async {
        await SyncOrchestrationService.syncAll(modelContext: modelContext)
    }

    /// A name a person typed: trimmed, inner runs of spaces collapsed.
    nonisolated static func clean(_ name: String) -> String {
        name.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private nonisolated struct ActiveFlag: Encodable { let is_active: Bool }
}
