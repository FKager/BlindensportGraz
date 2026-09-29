import Foundation
import SwiftData

@MainActor
enum TrainingFavoriteService {
    /// `TrainingFavorite.recordUsage`/`.populateFromRecentTrainings` can
    /// both upsert a favorite AND evict a least-recently-used one in the
    /// same local operation (already applied to `modelContext` by the time
    /// this is called) — one save covers both, then pushes whichever of
    /// `favorite`/`evictedID` are non-nil, only on save success.
    @discardableResult
    static func saveResult(favorite: TrainingFavorite?, evictedID: UUID?, modelContext: ModelContext) -> Bool {
        PersistenceService.saveAndPush(modelContext: modelContext, modelName: "TrainingFavorite",
                                        failureMessage: "Trainings-Favorit konnte nicht gespeichert werden.") {
            if let favorite { CloudKitSync.shared.pushTrainingFavorite(favorite) }
            if let evictedID { CloudKitSync.shared.deleteTrainingFavorite(evictedID) }
        }
    }

    @discardableResult
    static func delete(_ favorite: TrainingFavorite, modelContext: ModelContext) -> Bool {
        let id = favorite.id
        modelContext.delete(favorite)
        return PersistenceService.deleteAndPush(modelContext: modelContext, modelName: "TrainingFavorite",
                                                 failureMessage: "Trainings-Favorit konnte nicht gelöscht werden.") {
            CloudKitSync.shared.deleteTrainingFavorite(id)
        }
    }
}
