import Foundation
import SwiftData

@Model
final class Team {
    @Attribute(.unique) var id: UUID = UUID()
    var name: String = ""
    var sport: String = ""
    var descriptionText: String = ""
    var createdAt: Date = Date.now

    @Relationship(deleteRule: .cascade, inverse: \TeamMembership.team)
    var memberships: [TeamMembership] = []

    // Never read directly anywhere in the app (SportEvent/Training/Tournament
    // membership is always navigated the other way, filtering `.teams`
    // client-side) — this exists so deleteRule: .nullify protects any
    // assigned event/training/tournament from a dangling Team reference when
    // a team is deleted (see TeamsViews.swift's delete). One relationship
    // covers all three now that Training/Tournament are SportEvent subclasses.
    @Relationship(deleteRule: .nullify, inverse: \SportEvent.teams)
    var sportEvents: [SportEvent] = []

    init(id: UUID = UUID(),
         name: String,
         sport: String,
         descriptionText: String = "",
         createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.sport = sport
        self.descriptionText = descriptionText
        self.createdAt = createdAt
    }
}

extension Team {
    /// The club's standing teams, expected to always exist — recreated
    /// automatically by `CloudKitSync.ensureDefaultTeams` on every launch if
    /// missing (e.g. very first launch ever, or a local store rebuilt from a
    /// ModelContainer migration reset — see the 2026-08-01 rename entry in
    /// cerebrum.md). Kept as a plain data constant next to the model, same
    /// convention as `User.designatedRootEmail`.
    static let defaultTeams: [(name: String, sport: String)] = [
        ("Grazer VSC Damen", "Torball"),
        ("Grazer VSC Herren", "Torball"),
        ("Blindenfußball", "Blindenfußball"),
        // Originally a single sport-agnostic "Helfer" team; split into two
        // sport-specific ones per user request 2026-08-03 — see
        // CloudKitSync.ensureDefaultTeams' one-time rename of any
        // already-created "Helfer" team into "Torball Helfer" in place
        // (same id/memberships), so existing devices don't end up with a
        // duplicate/orphaned team under the old name.
        ("Torball Helfer", "Torball"),
        ("Blindenfußball Helfer", "Blindenfußball"),
    ]

    /// Maps a SportEvent's `sport` string to the teams automatically
    /// assigned to any new training/tournament of that sport, regardless of
    /// who creates it or which teams they personally belong to — see
    /// AddTrainingView/AddTournamentView's save actions. Names must match
    /// `defaultTeams` above exactly (case-insensitive lookup), since that's
    /// what actually creates these teams in the first place. Sports not
    /// listed here get no automatic assignment.
    static let autoAssignTeamNames: [String: [String]] = [
        "Torball": ["Grazer VSC Damen", "Grazer VSC Herren", "Torball Helfer"],
        "Blindenfußball": ["Blindenfußball", "Blindenfußball Helfer"],
    ]
}
