import Foundation
import SwiftData

/// One entry of the club's list of event types (Supabase `event_types`):
/// Training, Turnier, Kurs, Generalversammlung … Each type has a behaviour —
/// the `SportEvent.kind` its events get ("training", "tournament" or
/// "event") — which decides status values, teams, PRAE and reports. A type
/// like "Trainingslager" can therefore behave like a training.
///
/// Read-only cache: written only by `SupabaseSync.pullEventTypes`; edits go
/// straight to the server via `CatalogService`.
@Model
final class EventType {
    @Attribute(.unique) var id: UUID = UUID()
    var name: String = ""
    var behavior: String = EventType.Behavior.event.rawValue
    var isActive: Bool = true
    var sortOrder: Int = 0

    init(id: UUID = UUID(), name: String, behavior: String, isActive: Bool = true, sortOrder: Int = 0) {
        self.id = id
        self.name = name
        self.behavior = behavior
        self.isActive = isActive
        self.sortOrder = sortOrder
    }
}

nonisolated extension EventType {
    /// The three behaviours, equal to `SportEvent.kind`.
    enum Behavior: String, CaseIterable, Identifiable, Sendable {
        case training, tournament, event

        var id: String { rawValue }

        var label: String {
            switch self {
            case .training: String(localized: "wie ein Training")
            case .tournament: String(localized: "wie ein Turnier")
            case .event: String(localized: "wie eine Veranstaltung")
            }
        }

        /// The type an event of this kind gets when nothing else is chosen
        /// (also what the server fills in for older app builds).
        var defaultTypeName: String? {
            switch self {
            case .training: "Training"
            case .tournament: "Turnier"
            case .event: nil
            }
        }
    }

    /// Used until the first sync has brought the club's list.
    static let defaults: [(name: String, behavior: Behavior)] = [
        ("Training", .training), ("Turnier", .tournament), ("Kurs", .event), ("Langlaufkurs", .event),
        ("Tandemfahrt", .event), ("Generalversammlung", .event), ("Weihnachtsfeier", .event),
        ("ÖSTM Nordisch", .event), ("ÖM Torball", .event)
    ]
}
