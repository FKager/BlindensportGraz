import Foundation
import SwiftData

@Model
final class User {
    @Attribute(.unique) var id: UUID = UUID()
    var username: String = ""
    var email: String = ""
    var displayName: String = ""
    var role: String = "member" // "member", "coach", "admin"
    var appleUserIdentifier: String = ""
    var createdAt: Date = Date.now
    // Set automatically on account creation by matching against the ClubMember roster.
    var isGrazerVSCMember: Bool = false
    // Super-user flag, distinct from `role`. Only a root account can change another
    // account's `role`; nobody (including root) can change their own via the app —
    // see EditAccountView/UserListView. Set only by RootView on first-ever account
    // creation, or externally via the RootCLI tool talking directly to CloudKit.
    var isRoot: Bool = false

    @Relationship(deleteRule: .cascade, inverse: \TeamMembership.user)
    var memberships: [TeamMembership] = []

    @Relationship(deleteRule: .cascade, inverse: \EventParticipation.user)
    var participations: [EventParticipation] = []

    init(id: UUID = UUID(),
         username: String,
         email: String,
         displayName: String,
         role: String = "member",
         appleUserIdentifier: String = "",
         createdAt: Date = .now,
         isGrazerVSCMember: Bool = false,
         isRoot: Bool = false) {
        self.id = id
        self.username = username
        self.email = email
        self.displayName = displayName
        self.role = role
        self.appleUserIdentifier = appleUserIdentifier
        self.createdAt = createdAt
        self.isGrazerVSCMember = isGrazerVSCMember
        self.isRoot = isRoot
    }
}

/// Membership roster for the sports club "Grazer VSC", administered by admins.
/// Used to automatically flag matching app accounts as club members on creation.
@Model
final class ClubMember {
    @Attribute(.unique) var id: UUID = UUID()
    var firstName: String = ""
    var lastName: String = ""
    var street: String = ""
    var zip: String = ""
    var city: String = ""
    var email: String = ""
    var phone: String = ""
    var memberNumber: String = ""
    var joinedAt: Date = Date.now
    var notes: String = ""

    @Relationship(deleteRule: .cascade, inverse: \TeamMembership.clubMember)
    var teamMemberships: [TeamMembership] = []

    init(id: UUID = UUID(),
         firstName: String,
         lastName: String,
         street: String = "",
         zip: String = "",
         city: String = "",
         email: String = "",
         phone: String = "",
         memberNumber: String = "",
         joinedAt: Date = .now,
         notes: String = "") {
        self.id = id
        self.firstName = firstName
        self.lastName = lastName
        self.street = street
        self.zip = zip
        self.city = city
        self.email = email
        self.phone = phone
        self.memberNumber = memberNumber
        self.joinedAt = joinedAt
        self.notes = notes
    }
}

extension ClubMember {
    /// Combines firstName/lastName for display and matching; not stored, so it
    /// can't be used as a @Query sort key path — sort by lastName/firstName instead.
    var fullName: String {
        [firstName, lastName].filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.joined(separator: " ")
    }

    /// Combines street/zip/city into one display line, e.g. "Hauptstraße 12, 8010 Graz".
    /// Not stored, mirrors fullName's pattern — can't be used as a @Query sort key.
    var fullAddress: String {
        let zipCity = [zip, city].filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.joined(separator: " ")
        return [street, zipCity].filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.joined(separator: ", ")
    }
}

extension ClubMember {
    /// Checks a newly created (or edited) account's email/display name against the
    /// local ClubMember roster and updates its `isGrazerVSCMember` flag accordingly.
    static func checkMembership(for user: User, modelContext: ModelContext) {
        let roster = (try? modelContext.fetch(FetchDescriptor<ClubMember>())) ?? []
        user.isGrazerVSCMember = matches(email: user.email, displayName: user.displayName, in: roster)
    }

    /// Matches a new account's email/display name against the roster, case- and
    /// whitespace-insensitively. Email match takes priority since names can collide.
    static func matches(email: String, displayName: String, in roster: [ClubMember]) -> Bool {
        let normalizedEmail = email.trimmingCharacters(in: .whitespaces).lowercased()
        let normalizedName = displayName.trimmingCharacters(in: .whitespaces).lowercased()
        guard !normalizedEmail.isEmpty || !normalizedName.isEmpty else { return false }

        return roster.contains { member in
            let memberEmail = member.email.trimmingCharacters(in: .whitespaces).lowercased()
            if !normalizedEmail.isEmpty, !memberEmail.isEmpty, memberEmail == normalizedEmail {
                return true
            }
            let memberName = member.fullName.trimmingCharacters(in: .whitespaces).lowercased()
            return !normalizedName.isEmpty && !memberName.isEmpty && memberName == normalizedName
        }
    }
}

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

/// Exactly one of `user`/`clubMember` is set, never both/neither. `user` covers
/// people with a registered app account; `clubMember` covers Grazer VSC roster
/// entries who haven't signed into the app yet — teams routinely include both,
/// since real club rosters aren't 1:1 with app installs.
@Model
final class TeamMembership {
    @Attribute(.unique) var id: UUID = UUID()
    var user: User?
    var clubMember: ClubMember?
    var team: Team
    var role: String = "player" // "player", "coach", "assistant"
    var joinedAt: Date = Date.now

    init(id: UUID = UUID(),
         user: User? = nil,
         clubMember: ClubMember? = nil,
         team: Team,
         role: String = "player",
         joinedAt: Date = .now) {
        self.id = id
        self.user = user
        self.clubMember = clubMember
        self.team = team
        self.role = role
        self.joinedAt = joinedAt
    }
}

extension TeamMembership {
    var displayName: String {
        user?.displayName ?? clubMember?.fullName ?? "?"
    }

    /// Secondary line under the name in member lists: "@username" for a
    /// registered account, or a note that this roster entry has none yet.
    var subtitle: String {
        if let user { return "@\(user.username)" }
        return "Grazer VSC – kein Konto"
    }
}

/// Base type for anything that's fundamentally "a sport happening at a place
/// and time": a plain SportEvent, or (via the Training/Tournament subclasses
/// below) a training session or a tournament. `kind` is a stored
/// discriminator ("event"/"training"/"tournament") — SwiftData's polymorphic
/// fetch means a plain `@Query`/`FetchDescriptor<SportEvent>` returns
/// Training/Tournament instances too, so any query that wants ONLY plain
/// events (EventsListView, DashboardView) must filter on `kind == "event"`.
@Model
@available(iOS 26, *)
class SportEvent {
    @Attribute(.unique) var id: UUID = UUID()
    var kind: String = "event" // "event", "training", "tournament"
    var title: String = ""
    var sport: String = ""
    var location: String = ""
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
        self.startDate = startDate
        self.endDate = endDate
        self.notes = notes
        self.createdBy = createdBy
        self.createdAt = createdAt
        self.teams = teams
    }
}

@Model
@available(iOS 26, *)
final class Tournament: SportEvent {
    var maxTeams: Int = 8
    var status: String = "planned" // "planned", "ongoing", "finished"

    init(id: UUID = UUID(),
         title: String,
         sport: String,
         location: String,
         startDate: Date,
         endDate: Date,
         maxTeams: Int = 8,
         status: String = "planned",
         notes: String = "",
         createdBy: String = "",
         createdAt: Date = .now,
         teams: [Team] = []) {
        self.maxTeams = maxTeams
        self.status = status
        super.init(id: id, title: title, sport: sport, location: location, startDate: startDate,
                   endDate: endDate, notes: notes, createdBy: createdBy, createdAt: createdAt, teams: teams)
        self.kind = "tournament"
    }
}

@Model
@available(iOS 26, *)
final class Training: SportEvent {
    var durationMinutes: Int = 90
    var focusArea: String = ""

    init(id: UUID = UUID(),
         title: String,
         sport: String,
         location: String,
         startDate: Date,
         durationMinutes: Int = 90,
         focusArea: String = "",
         notes: String = "",
         createdBy: String = "",
         createdAt: Date = .now,
         teams: [Team] = []) {
        self.durationMinutes = durationMinutes
        self.focusArea = focusArea
        let endDate = startDate.addingTimeInterval(TimeInterval(durationMinutes) * 60)
        super.init(id: id, title: title, sport: sport, location: location, startDate: startDate,
                   endDate: endDate, notes: notes, createdBy: createdBy, createdAt: createdAt, teams: teams)
        self.kind = "training"
    }

    /// Keeps the inherited, stored `endDate` in sync with startDate +
    /// durationMinutes. SwiftData model properties don't support
    /// didSet/property-observer sync, so this has to be called explicitly
    /// wherever startDate or durationMinutes changes — see
    /// TrainingDetailView's .onChange handlers.
    func recomputeEndDate() {
        endDate = startDate.addingTimeInterval(TimeInterval(durationMinutes) * 60)
    }
}

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

    init(id: UUID = UUID(),
         event: SportEvent,
         membership: TeamMembership,
         attended: Bool = false,
         recordedAt: Date = .now) {
        self.id = id
        self.event = event
        self.membership = membership
        self.attended = attended
        self.recordedAt = recordedAt
    }
}

/// A photo attached to a SportEvent (or, via inheritance, a Training or
/// Tournament). Randomly featured on that item's detail screen and browsable
/// as a full gallery — see EventImagesSection.
@Model
final class EventImage {
    @Attribute(.unique) var id: UUID = UUID()
    @Attribute(.externalStorage) var imageData: Data = Data()
    var uploadedBy: String = ""
    var uploadedAt: Date = Date.now
    var event: SportEvent?

    init(id: UUID = UUID(),
         imageData: Data,
         uploadedBy: String = "",
         uploadedAt: Date = .now,
         event: SportEvent? = nil) {
        self.id = id
        self.imageData = imageData
        self.uploadedBy = uploadedBy
        self.uploadedAt = uploadedAt
        self.event = event
    }
}

@Model
final class EventParticipation {
    @Attribute(.unique) var id: UUID = UUID()
    var user: User
    var event: SportEvent
    var status: String = "invited" // "invited", "confirmed", "declined"
    var registeredAt: Date = Date.now

    init(id: UUID = UUID(),
         user: User,
         event: SportEvent,
         status: String = "invited",
         registeredAt: Date = .now) {
        self.id = id
        self.user = user
        self.event = event
        self.status = status
        self.registeredAt = registeredAt
    }
}
