import Foundation

/// What the Events, Trainings and Tournaments lists show, and who may
/// change them there. One place, so the three lists can't drift apart.
enum EventListAccess {
    /// Club managers see everything; everyone else sees events for all teams
    /// plus the events of their own teams. Keeps the order of `events`.
    static func visible<Event: SportEvent>(_ events: [Event], to user: User?) -> [Event] {
        if user?.can(.clubManage) ?? false { return events }
        let myTeamIDs = Set(user?.memberships.map(\.team.id) ?? [])
        return events.filter { event in
            event.teams.isEmpty || event.teams.contains { myTeamIDs.contains($0.id) }
        }
    }

    /// Whether `user` may delete or cancel events in these lists. The server
    /// enforces the same rule; without this check the row would vanish on
    /// the phone and only come back with the next full sync.
    static func canManage(_ user: User?) -> Bool {
        user?.can(.eventsManage) ?? false
    }

    /// The rows a swipe-to-delete removes. `onDelete` offsets index the list
    /// as shown, so they must be resolved against that same list — never the
    /// unfiltered `@Query` result.
    static func rows<Event>(at offsets: IndexSet, in shown: [Event]) -> [Event] {
        offsets.compactMap { shown.indices.contains($0) ? shown[$0] : nil }
    }
}
