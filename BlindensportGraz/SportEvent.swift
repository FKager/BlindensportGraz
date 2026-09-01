import Foundation
import SwiftData

/// Base type for anything that's fundamentally "a sport happening at a place
/// and time": a plain SportEvent, or (via the Training/Tournament subclasses
/// in their own files) a training session or a tournament. `kind` is a
/// stored discriminator ("event"/"training"/"tournament") — SwiftData's
/// polymorphic fetch means a plain `@Query`/`FetchDescriptor<SportEvent>`
/// returns Training/Tournament instances too, so any query that wants ONLY
/// plain events (EventsListView, DashboardView) must filter on
/// `kind == "event"`.
///
/// Training/Tournament subclass this across separate files
/// (`Training.swift`/`Tournament.swift`) — Swift class inheritance doesn't
/// require the same file, only the same module, so splitting Models.swift
/// per-@Model-class (audit.md Architecture Finding 2) didn't need to keep
/// this hierarchy artificially bundled together.
@Model
@available(iOS 26, *)
class SportEvent {
    @Attribute(.unique) var id: UUID = UUID()
    var kind: String = "event" // "event", "training", "tournament"
    var title: String = ""
    var sport: String = ""
    var location: String = "" // venue name, e.g. "Sporthalle Eggenberg" — see street/zip/city/country below for the postal address
    var street: String = ""
    var zip: String = ""
    var city: String = ""
    var country: String = ""
    var startDate: Date = Date.now
    var endDate: Date = Date.now
    var notes: String = ""
    var createdBy: String = ""
    var createdAt: Date = Date.now
    // Empty = visible to everyone; non-empty = scoped to members of any listed team.
    var teams: [Team] = []

    @Relationship(deleteRule: .cascade, inverse: \EventParticipation.event)
    var participations: [EventParticipation] = []

    @Relationship(deleteRule: .cascade, inverse: \EventImage.event)
    var images: [EventImage] = []

    @Relationship(deleteRule: .cascade, inverse: \Attendance.event)
    var attendances: [Attendance] = []

    init(id: UUID = UUID(),
         title: String,
         sport: String,
         location: String,
         street: String = "",
         zip: String = "",
         city: String = "",
         country: String = "",
         startDate: Date,
         endDate: Date,
         notes: String = "",
         createdBy: String = "",
         createdAt: Date = .now,
         teams: [Team] = []) {
        self.id = id
        self.title = title
        self.sport = sport
        self.location = location
        self.street = street
        self.zip = zip
        self.city = city
        self.country = country
        self.startDate = startDate
        self.endDate = endDate
        self.notes = notes
        self.createdBy = createdBy
        self.createdAt = createdAt
        self.teams = teams
    }
}

extension SportEvent {
    /// Combines street/zip/city/country into one display line, e.g.
    /// "Hauptstraße 12, 8010 Graz, Österreich" — mirrors Member.fullAddress
    /// exactly (same join logic). Not stored, so it can't be used as a
    /// @Query sort key.
    var fullAddress: String {
        let zipCity = [zip, city].filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.joined(separator: " ")
        return [street, zipCity, country].filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.joined(separator: ", ")
    }

    /// `location` with `country` appended, comma-separated, but only when
    /// `country` is set to something other than "Österreich" — Austria is
    /// the assumed default for this club's events, so it stays implicit;
    /// a foreign country is the one case worth calling out in something
    /// like the Teilnehmerliste's "Ort" field. Kept separate from
    /// `fullAddress` above, which always shows `country` unconditionally
    /// as part of the full postal address.
    var locationWithCountry: String {
        let trimmedCountry = country.trimmingCharacters(in: .whitespaces)
        guard !trimmedCountry.isEmpty, trimmedCountry != "Österreich" else { return location }
        return "\(location), \(trimmedCountry)"
    }

    /// Inclusive count of calendar days this event spans — a tournament
    /// running Fri-Sun is 3, not 2. Same day-count convention as
    /// TeilnehmerlisteExport's private `dayCount(from:to:)`/KostZExport's
    /// `dayCount` (kept separate rather than consolidated — out of scope for
    /// the PRAE change that introduced this shared one). Used to size a
    /// tournament's PRAE picker max (`PraeCalculator.dailyCap * dayCount`)
    /// and to spread a tournament's single PRAE amount evenly across its
    /// days (`PraeCalculator.summary(for:tournament:)`).
    var dayCount: Int {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: startDate)
        let end = calendar.startOfDay(for: endDate)
        let days = calendar.dateComponents([.day], from: start, to: end).day ?? 0
        return max(1, days + 1)
    }
}
