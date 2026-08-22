import Foundation
import SwiftData

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
