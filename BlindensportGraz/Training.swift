import Foundation
import SwiftData

@Model
@available(iOS 26, *)
final class Training: SportEvent {
    var durationMinutes: Int = 90
    var focusArea: String = ""

    init(id: UUID = UUID(),
         title: String,
         sport: String,
         location: String,
         street: String = "",
         zip: String = "",
         city: String = "",
         country: String = "",
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
        super.init(id: id, title: title, sport: sport, location: location, street: street, zip: zip, city: city, country: country,
                   startDate: startDate, endDate: endDate, notes: notes, createdBy: createdBy, createdAt: createdAt, teams: teams)
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
