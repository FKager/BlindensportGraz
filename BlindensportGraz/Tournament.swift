import Foundation
import SwiftData

@Model
@available(iOS 26, *)
final class Tournament: SportEvent {
    var maxTeams: Int = 8
    var status: String = "planned" // "planned", "ongoing", "finished"

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
         maxTeams: Int = 8,
         status: String = "planned",
         notes: String = "",
         createdBy: String = "",
         createdAt: Date = .now,
         teams: [Team] = []) {
        self.maxTeams = maxTeams
        self.status = status
        super.init(id: id, title: title, sport: sport, location: location, street: street, zip: zip, city: city, country: country,
                   startDate: startDate, endDate: endDate, notes: notes, createdBy: createdBy, createdAt: createdAt, teams: teams)
        self.kind = "tournament"
    }
}
