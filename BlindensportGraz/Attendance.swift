import Foundation
import SwiftData

/// Attendance record for one team-roster entry (TeamMembership) at one
/// SportEvent — in practice always a Training or Tournament, since only
/// their detail views have an "Anwesenheit" section. Created lazily the
/// first time a checkbox is toggled, not upfront for every assigned member.
@Model
final class Attendance {
    @Attribute(.unique) var id: UUID = UUID()
    var event: SportEvent
    var membership: TeamMembership
    var attended: Bool = false
    var recordedAt: Date = Date.now
    // Pauschale Reiseaufwandsentschädigung (PRAE) amount for this one
    // deployment day, EUR. Nil by default — an admin opts a specific
    // attendance into PRAE by entering an amount (see PraeCalculation.swift),
    // it's never inferred automatically. Only meaningful for coach/assistant
    // memberships (see TrainingsViews/TournamentsViews' Anwesenheit section,
    // which only shows the amount field for those roles) — "helpers and
    // coaches" per the feature request, matching this app's existing
    // TeamMembership.role vocabulary rather than Sport Austria's broader
    // (Sportler:in/Trainer:in/Übungsleiter:in/...) role list.
    var praeAmount: Double?

    init(id: UUID = UUID(),
         event: SportEvent,
         membership: TeamMembership,
         attended: Bool = false,
         recordedAt: Date = .now,
         praeAmount: Double? = nil) {
        self.id = id
        self.event = event
        self.membership = membership
        self.attended = attended
        self.recordedAt = recordedAt
        self.praeAmount = praeAmount
    }
}
