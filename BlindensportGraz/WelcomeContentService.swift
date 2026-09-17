import Foundation
import SwiftData

@MainActor
enum WelcomeContentService {
    @discardableResult
    static func save(_ content: WelcomeContent, modelContext: ModelContext) -> Bool {
        content.updatedAt = .now
        return PersistenceService.saveAndPush(modelContext: modelContext, modelName: "WelcomeContent",
                                               failureMessage: "Willkommenstext konnte nicht gespeichert werden.") {
            CloudKitSync.shared.pushWelcomeContent(content)
        }
    }
}
