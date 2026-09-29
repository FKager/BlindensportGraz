import Foundation
import SwiftData

/// Direct person-to-event link for a plain `SportEvent` ("Event" kind only —
/// Training/Tournament keep using `teams`/`rosterAcrossTeams` instead, see
/// their own views). Added per user request 2026-09-12: events like
/// "Weihnachtsfeier"/"Generalversammlung" aren't naturally scoped to a Team's
/// roster, so an admin/coach picks individual people directly instead of
/// picking teams first.
///
/// Exactly one of `user`/`member` is set, never both/neither — same
/// user/member split as `TeamMembership` (see its own doc comment): `user`
/// covers people with a registered app account, `member` covers Grazer VSC
/// roster entries who haven't signed into the app yet.
@Model
final class EventMembership {
    @Attribute(.unique) var id: UUID = UUID()
    var user: User?
    var member: Member?
    var event: SportEvent
    var addedAt: Date = Date.now

    init(id: UUID = UUID(),
         user: User? = nil,
         member: Member? = nil,
         event: SportEvent,
         addedAt: Date = .now) {
        self.id = id
        self.user = user
        self.member = member
        self.event = event
        self.addedAt = addedAt
    }
}

extension EventMembership {
    // Same user/member fallback chain as TeamMembership.displayName.
    var displayName: String {
        user?.displayName ?? member?.fullName ?? "?"
    }

    var lastName: String { user?.lastName ?? member?.lastName ?? "" }
    var firstName: String { user?.firstName ?? member?.firstName ?? "" }
}

extension Sequence where Element == EventMembership {
    // Same sort convention as TeamMembership's identically-named helper.
    func sortedByLastName() -> [EventMembership] {
        sorted { ($0.lastName, $0.firstName) < ($1.lastName, $1.firstName) }
    }
}
