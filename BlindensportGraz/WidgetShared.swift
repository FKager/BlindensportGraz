import Foundation

/// The small payload the home-screen widget needs, shared between the app and
/// the widget extension through the App Group. Deliberately **not** SwiftData:
/// the widget never opens the store. The app recomputes this after every sync
/// or event edit (`WidgetRefresher`) and writes it here; the widget only
/// reads it. That keeps the main SwiftData store exactly where it is — no App
/// Group relocation, no one-time CloudKit resync.
///
/// This file is compiled into **both** targets (see `project.yml`), so each
/// module gets its own copy of the type; they only ever meet as the JSON in
/// `UserDefaults`, which is identical because the source is.
struct NextUpSnapshot: Codable, Equatable {
    enum Kind: String, Codable {
        case training
        case tournament
    }

    var kind: Kind
    var title: String
    var startDate: Date
    /// Venue name; may be empty.
    var location: String
}

enum WidgetBridge {
    /// Must match the App Group id registered on both App IDs.
    static let appGroup = "group.it.a11y.BlindensportGraz"
    private static let key = "nextUp.v1"

    private static var store: UserDefaults? { UserDefaults(suiteName: appGroup) }

    /// Writes the current "what's next", or clears it when there is nothing
    /// upcoming. No-op if the App Group container isn't available (e.g. the
    /// entitlement hasn't propagated yet).
    static func write(_ snapshot: NextUpSnapshot?) {
        guard let store else { return }
        if let snapshot, let data = try? JSONEncoder().encode(snapshot) {
            store.set(data, forKey: key)
        } else {
            store.removeObject(forKey: key)
        }
    }

    static func read() -> NextUpSnapshot? {
        guard let data = store?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(NextUpSnapshot.self, from: data)
    }
}
