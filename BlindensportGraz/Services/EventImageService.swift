import Foundation
import SwiftData

@MainActor
enum EventImageService {
    @discardableResult
    static func save(_ image: EventImage, modelContext: ModelContext) -> Bool {
        PersistenceService.saveAndPush(modelContext: modelContext, modelName: "EventImage",
                                        failureMessage: "Foto konnte nicht gespeichert werden.") {
            CloudKitSync.shared.pushEventImage(image)
        }
    }

    @discardableResult
    static func delete(_ image: EventImage, modelContext: ModelContext) -> Bool {
        let id = image.id
        modelContext.delete(image)
        return PersistenceService.deleteAndPush(modelContext: modelContext, modelName: "EventImage",
                                                 failureMessage: "Foto konnte nicht gelöscht werden.") {
            CloudKitSync.shared.deleteEventImage(id)
        }
    }
}
