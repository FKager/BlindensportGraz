import Foundation
import SwiftData

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
