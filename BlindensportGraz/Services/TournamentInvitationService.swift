import Foundation
import SwiftData

/// A tournament's documents (`TournamentInvitation`): any number per
/// tournament, oldest first.
@MainActor
enum TournamentInvitationService {
    /// The tournament's documents, in upload order.
    static func documents(for tournament: Tournament, in documents: [TournamentInvitation]) -> [TournamentInvitation] {
        documents.filter { $0.tournament?.id == tournament.id }
            .sorted { ($0.uploadedAt, $0.fileName) < ($1.uploadedAt, $1.fileName) }
    }

    /// Adds `data` as another document of the tournament.
    @discardableResult
    static func add(to tournament: Tournament, data: Data, fileName: String, uploadedBy: String,
                    modelContext: ModelContext) -> TournamentInvitation? {
        let document = TournamentInvitation(fileData: data, fileName: fileName,
                                            contentType: TournamentInvitation.contentType(forFileName: fileName),
                                            uploadedBy: uploadedBy, tournament: tournament)
        modelContext.insert(document)
        return save(document, modelContext: modelContext) ? document : nil
    }

    @discardableResult
    static func save(_ document: TournamentInvitation, modelContext: ModelContext) -> Bool {
        PersistenceService.saveAndPush(modelContext: modelContext, modelName: "TournamentInvitation",
                                        failureMessage: "Dokument konnte nicht gespeichert werden.") {
            SupabaseSync.shared.pushTournamentInvitation(document)
        }
    }

    @discardableResult
    static func delete(_ document: TournamentInvitation, modelContext: ModelContext) -> Bool {
        let id = document.id
        let path = TournamentInvitationDBRow.path(for: document)
        modelContext.delete(document)
        return PersistenceService.deleteAndPush(modelContext: modelContext, modelName: "TournamentInvitation",
                                                 failureMessage: "Dokument konnte nicht gelöscht werden.") {
            SupabaseSync.shared.deleteTournamentInvitation(id, path: path)
        }
    }
}
