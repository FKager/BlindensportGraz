import Foundation
import SwiftData

/// One entry of the club's sport list (Supabase `sports`). Admins
/// (club.manage) extend it; teams, trainings, tournaments and favourites
/// still store the sport by name in their `sport` text field, so older
/// builds and free-text values keep working. Renaming goes through the
/// server (`rename_sport`), which updates every row using the old name.
///
/// Read-only cache: written only by `SupabaseSync.pullSports`; edits go
/// straight to the server via `CatalogService`.
@Model
final class ClubSport {
    @Attribute(.unique) var id: UUID = UUID()
    var name: String = ""
    var isActive: Bool = true
    var sortOrder: Int = 0

    init(id: UUID = UUID(), name: String, isActive: Bool = true, sortOrder: Int = 0) {
        self.id = id
        self.name = name
        self.isActive = isActive
        self.sortOrder = sortOrder
    }
}

nonisolated extension ClubSport {
    /// Used until the first sync has brought the club's list (and for
    /// accounts that can't read it yet) — the list the pickers had built in.
    static let defaultNames = ["Torball", "Goalball", "Blindenfußball", "Showdown", "Judo",
                               "Leichtathletik", "Schwimmen", "Ski", "Radfahren"]
}
