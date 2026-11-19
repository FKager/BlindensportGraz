import Foundation

/// What the sport and event-type pickers offer: the club's active entries in
/// their order, or the built-in defaults until the first sync has brought
/// the lists. A value that's already stored but no longer offered
/// (deactivated, or free text from an older build) stays selectable, so
/// opening an old event never changes it.
enum CatalogOptions {
    static func sportNames(from sports: [ClubSport]) -> [String] {
        guard !sports.isEmpty else { return ClubSport.defaultNames }
        return sports.filter(\.isActive).sorted(by: ordered).map(\.name)
    }

    static func eventTypeNames(from types: [EventType], behavior: EventType.Behavior) -> [String] {
        guard !types.isEmpty else {
            return EventType.defaults.filter { $0.behavior == behavior }.map(\.name)
        }
        return types.filter { $0.isActive && $0.behavior == behavior.rawValue }.sorted(by: ordered).map(\.name)
    }

    /// `names` plus `current` when it's set but missing from them.
    static func including(_ current: String, in names: [String]) -> [String] {
        let trimmed = current.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !names.contains(current) else { return names }
        return names + [current]
    }

    private static func ordered(_ a: ClubSport, _ b: ClubSport) -> Bool {
        (a.sortOrder, a.name.localizedLowercase) < (b.sortOrder, b.name.localizedLowercase)
    }

    private static func ordered(_ a: EventType, _ b: EventType) -> Bool {
        (a.sortOrder, a.name.localizedLowercase) < (b.sortOrder, b.name.localizedLowercase)
    }
}
