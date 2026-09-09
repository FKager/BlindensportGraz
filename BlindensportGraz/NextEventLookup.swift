import Foundation
import SwiftData

/// Read-only "what's next" lookups over the app's SwiftData store, shared by
/// the App Shortcuts intents (`AppShortcuts.swift`) and — later — a widget.
/// Kept out of the view layer because it runs in the App Intents execution
/// context, where there is no `@Environment(\.modelContext)`.
///
/// Visibility mirrors `TrainingsListView.visibleTrainings` /
/// `TournamentsListView.visibleTournaments` exactly: an admin sees every
/// event; anyone else sees only events with no team scoping or a team they
/// belong to.
@MainActor
enum NextEventLookup {

    /// A context on the SAME store the running app uses. Reuses
    /// `CloudKitSync.shared.modelContainer` (set in `BlindensportGrazApp.init`,
    /// which runs whenever the system spins the app up to service an intent)
    /// rather than opening a second `ModelContainer` on the same file; falls
    /// back to its own only if that handle isn't set.
    static func makeContext() -> ModelContext? {
        if let container = CloudKitSync.shared.modelContainer {
            return ModelContext(container)
        }
        guard let container = try? ModelContainer(for: AppModelSchema.schema,
                                                  configurations: [AppModelSchema.configuration]) else {
            return nil
        }
        return ModelContext(container)
    }

    /// The account last used on this device — `RootView` persists its id under
    /// `"localUserID"`. `nil` (no one logged in) falls back to "only
    /// unscoped events are visible".
    static func currentUser(in context: ModelContext) -> User? {
        guard let raw = UserDefaults.standard.string(forKey: "localUserID"),
              let id = UUID(uuidString: raw) else { return nil }
        var descriptor = FetchDescriptor<User>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    static func isVisible(teams: [Team], to user: User?) -> Bool {
        guard let user else { return teams.isEmpty }
        if user.role == .admin { return true }
        let myTeamIDs = Set(user.memberships.map { $0.team.id })
        return teams.isEmpty || teams.contains { myTeamIDs.contains($0.id) }
    }

    /// Soonest training starting at or after `now` that `user` may see.
    /// In-memory filter + `min` (not a `@Query`/`FetchDescriptor` sort) —
    /// `startDate` is inherited from `SportEvent` and SwiftData traps on an
    /// inherited-property sort key path in Release builds (bug-352).
    static func nextTraining(in context: ModelContext, for user: User?, now: Date = .now) -> Training? {
        let all = (try? context.fetch(FetchDescriptor<Training>())) ?? []
        return all
            .filter { $0.startDate >= now && isVisible(teams: $0.teams, to: user) }
            .min { $0.startDate < $1.startDate }
    }

    static func nextTournament(in context: ModelContext, for user: User?, now: Date = .now) -> Tournament? {
        let all = (try? context.fetch(FetchDescriptor<Tournament>())) ?? []
        return all
            .filter { $0.startDate >= now && isVisible(teams: $0.teams, to: user) }
            .min { $0.startDate < $1.startDate }
    }

    /// German one-liner for a Siri/Shortcuts spoken + shown answer.
    /// `includeTime` is false for tournaments (their date picker is
    /// day-only, so the stored time is meaningless — see SportEvent).
    static func spokenLine(kind: String, title: String, date: Date, location: String, includeTime: Bool) -> String {
        let format: Date.FormatStyle = includeTime
            ? .dateTime.weekday(.wide).day().month(.wide).hour().minute()
            : .dateTime.weekday(.wide).day().month(.wide)
        let when = date.formatted(format)
        let place = location.trimmingCharacters(in: .whitespaces)
        return place.isEmpty
            ? "Dein nächstes \(kind): \(title) am \(when)."
            : "Dein nächstes \(kind): \(title) am \(when) in \(place)."
    }
}
