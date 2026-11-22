import Foundation
import SwiftData

@Model
@available(iOS 26, *)
final class Tournament: SportEvent {
    var maxTeams: Int = 8
    var status: String = "planned" // "planned", "ongoing", "finished"

    /// German label for `status` (the edit Picker's tags), for TournamentRow's
    /// badge and TournamentDetailView — the row used to show the raw "planned".
    var statusLabel: String {
        switch status {
        case "planned": return String(localized: "Geplant")
        case "ongoing": return String(localized: "Laufend")
        case "finished": return String(localized: "Beendet")
        default: return status
        }
    }

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
