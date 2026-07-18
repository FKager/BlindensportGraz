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

    @Relationship(deleteRule: .nullify, inverse: \SportEvent.teams)
    var events: [SportEvent] = []

    @Relationship(deleteRule: .nullify, inverse: \Training.teams)
    var trainings: [Training] = []

    @Relationship(deleteRule: .nullify, inverse: \Tournament.teams)
    var tournaments: [Tournament] = []

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

@Model
final class SportEvent {
    @Attribute(.unique) var id: UUID = UUID()
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
final class Tournament {
    @Attribute(.unique) var id: UUID = UUID()
    var name: String = ""
    var sport: String = ""
    var venue: String = ""
    var startDate: Date = Date.now
    var endDate: Date = Date.now
    var maxTeams: Int = 8
    var status: String = "planned" // "planned", "ongoing", "finished"
    var notes: String = ""
    var createdAt: Date = Date.now
    // Empty = visible to everyone; non-empty = scoped to members of any listed team.
    var teams: [Team] = []

    @Relationship(deleteRule: .cascade, inverse: \EventImage.tournament)
    var images: [EventImage] = []

    @Relationship(deleteRule: .cascade, inverse: \TournamentAttendance.tournament)
    var attendances: [TournamentAttendance] = []

    init(id: UUID = UUID(),
         name: String,
         sport: String,
         venue: String,
         startDate: Date,
         endDate: Date,
         maxTeams: Int = 8,
         status: String = "planned",
         notes: String = "",
         createdAt: Date = .now,
         teams: [Team] = []) {
        self.id = id
        self.name = name
        self.sport = sport
        self.venue = venue
        self.startDate = startDate
        self.endDate = endDate
        self.maxTeams = maxTeams
        self.status = status
        self.notes = notes
        self.createdAt = createdAt
        self.teams = teams
    }
}

/// Attendance record for one team-roster entry (TeamMembership) at one
/// Tournament. Mirrors TrainingAttendance — created lazily the first time a
/// checkbox is toggled in TournamentDetailView's "Anwesenheit" section.
@Model
final class TournamentAttendance {
    @Attribute(.unique) var id: UUID = UUID()
    var tournament: Tournament
    var membership: TeamMembership
    var attended: Bool = false
    var recordedAt: Date = Date.now

    init(id: UUID = UUID(),
         tournament: Tournament,
         membership: TeamMembership,
         attended: Bool = false,
         recordedAt: Date = .now) {
        self.id = id
        self.tournament = tournament
        self.membership = membership
        self.attended = attended
        self.recordedAt = recordedAt
    }
}

@Model
final class Training {
    @Attribute(.unique) var id: UUID = UUID()
    var title: String = ""
    var sport: String = ""
    var location: String = ""
    var startDate: Date = Date.now
    var durationMinutes: Int = 90
    var focusArea: String = ""
    var notes: String = ""
    var createdBy: String = ""
    var createdAt: Date = Date.now
    // Empty = visible to everyone; non-empty = scoped to members of any listed team.
    var teams: [Team] = []

    @Relationship(deleteRule: .cascade, inverse: \EventImage.training)
    var images: [EventImage] = []

    @Relationship(deleteRule: .cascade, inverse: \TrainingAttendance.training)
    var attendances: [TrainingAttendance] = []

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
        self.id = id
        self.title = title
        self.sport = sport
        self.location = location
        self.startDate = startDate
        self.durationMinutes = durationMinutes
        self.focusArea = focusArea
        self.notes = notes
        self.createdBy = createdBy
        self.createdAt = createdAt
        self.teams = teams
    }
}

/// Attendance record for one team-roster entry (TeamMembership) at one
/// Training. Created lazily the first time a checkbox is toggled in
/// TrainingDetailView's "Anwesenheit" section, not upfront for every
/// assigned member — most trainings will only ever get some members checked.
@Model
final class TrainingAttendance {
    @Attribute(.unique) var id: UUID = UUID()
    var training: Training
    var membership: TeamMembership
    var attended: Bool = false
    var recordedAt: Date = Date.now

    init(id: UUID = UUID(),
         training: Training,
         membership: TeamMembership,
         attended: Bool = false,
         recordedAt: Date = .now) {
        self.id = id
        self.training = training
        self.membership = membership
        self.attended = attended
        self.recordedAt = recordedAt
    }
}

/// A photo attached to a SportEvent, Training, or Tournament (exactly one of the
/// three relationships is set). Randomly featured on that item's detail screen
/// and browsable as a full gallery — see EventImagesSection.
@Model
final class EventImage {
    @Attribute(.unique) var id: UUID = UUID()
    @Attribute(.externalStorage) var imageData: Data = Data()
    var uploadedBy: String = ""
    var uploadedAt: Date = Date.now
    var event: SportEvent?
    var training: Training?
    var tournament: Tournament?

    init(id: UUID = UUID(),
         imageData: Data,
         uploadedBy: String = "",
         uploadedAt: Date = .now,
         event: SportEvent? = nil,
         training: Training? = nil,
         tournament: Tournament? = nil) {
        self.id = id
        self.imageData = imageData
        self.uploadedBy = uploadedBy
        self.uploadedAt = uploadedAt
        self.event = event
        self.training = training
        self.tournament = tournament
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
