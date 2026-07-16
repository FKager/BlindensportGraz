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
    var fullName: String = ""
    var address: String = ""
    var email: String = ""
    var phone: String = ""
    var memberNumber: String = ""
    var joinedAt: Date = Date.now
    var notes: String = ""

    init(id: UUID = UUID(),
         fullName: String,
         address: String = "",
         email: String = "",
         phone: String = "",
         memberNumber: String = "",
         joinedAt: Date = .now,
         notes: String = "") {
        self.id = id
        self.fullName = fullName
        self.address = address
        self.email = email
        self.phone = phone
        self.memberNumber = memberNumber
        self.joinedAt = joinedAt
        self.notes = notes
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

    @Relationship(deleteRule: .nullify, inverse: \Training.team)
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

@Model
final class TeamMembership {
    @Attribute(.unique) var id: UUID = UUID()
    var user: User
    var team: Team
    var role: String = "player" // "player", "coach", "assistant"
    var joinedAt: Date = Date.now

    init(id: UUID = UUID(),
         user: User,
         team: Team,
         role: String = "player",
         joinedAt: Date = .now) {
        self.id = id
        self.user = user
        self.team = team
        self.role = role
        self.joinedAt = joinedAt
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
    // nil = visible to everyone; set = scoped to that team's members only.
    var team: Team?

    @Relationship(deleteRule: .cascade, inverse: \EventImage.training)
    var images: [EventImage] = []

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
         team: Team? = nil) {
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
        self.team = team
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
