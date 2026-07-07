import Foundation
import SwiftData

@Model
final class User {
    @Attribute(.unique) var id: UUID
    var username: String
    var email: String
    var displayName: String
    var role: String // "member", "coach", "admin"
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \TeamMembership.user)
    var memberships: [TeamMembership] = []

    @Relationship(deleteRule: .cascade, inverse: \EventParticipation.user)
    var participations: [EventParticipation] = []

    init(id: UUID = UUID(),
         username: String,
         email: String,
         displayName: String,
         role: String = "member",
         createdAt: Date = .now) {
        self.id = id
        self.username = username
        self.email = email
        self.displayName = displayName
        self.role = role
        self.createdAt = createdAt
    }
}

@Model
final class Team {
    @Attribute(.unique) var id: UUID
    var name: String
    var sport: String
    var descriptionText: String
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \TeamMembership.team)
    var memberships: [TeamMembership] = []

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
    @Attribute(.unique) var id: UUID
    var user: User
    var team: Team
    var role: String // "player", "coach", "assistant"
    var joinedAt: Date

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
    @Attribute(.unique) var id: UUID
    var title: String
    var sport: String
    var location: String
    var startDate: Date
    var endDate: Date
    var notes: String
    var createdBy: String
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \EventParticipation.event)
    var participations: [EventParticipation] = []

    init(id: UUID = UUID(),
         title: String,
         sport: String,
         location: String,
         startDate: Date,
         endDate: Date,
         notes: String = "",
         createdBy: String = "",
         createdAt: Date = .now) {
        self.id = id
        self.title = title
        self.sport = sport
        self.location = location
        self.startDate = startDate
        self.endDate = endDate
        self.notes = notes
        self.createdBy = createdBy
        self.createdAt = createdAt
    }
}

@Model
final class Tournament {
    @Attribute(.unique) var id: UUID
    var name: String
    var sport: String
    var venue: String
    var startDate: Date
    var endDate: Date
    var maxTeams: Int
    var status: String // "planned", "ongoing", "finished"
    var notes: String
    var createdAt: Date

    init(id: UUID = UUID(),
         name: String,
         sport: String,
         venue: String,
         startDate: Date,
         endDate: Date,
         maxTeams: Int = 8,
         status: String = "planned",
         notes: String = "",
         createdAt: Date = .now) {
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
    }
}

@Model
final class Training {
    @Attribute(.unique) var id: UUID
    var title: String
    var sport: String
    var location: String
    var startDate: Date
    var durationMinutes: Int
    var focusArea: String
    var notes: String
    var createdBy: String
    var createdAt: Date

    init(id: UUID = UUID(),
         title: String,
         sport: String,
         location: String,
         startDate: Date,
         durationMinutes: Int = 90,
         focusArea: String = "",
         notes: String = "",
         createdBy: String = "",
         createdAt: Date = .now) {
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
    }
}

@Model
final class EventParticipation {
    @Attribute(.unique) var id: UUID
    var user: User
    var event: SportEvent
    var status: String // "invited", "confirmed", "declined"
    var registeredAt: Date

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
