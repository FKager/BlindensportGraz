import Foundation
import SwiftData

@MainActor
enum TournamentInvitationService {
    /// The tournament's current invitation (newest, if several exist).
    static func invitation(for tournament: Tournament, in invitations: [TournamentInvitation]) -> TournamentInvitation? {
        invitations.filter { $0.tournament?.id == tournament.id }.max { $0.uploadedAt < $1.uploadedAt }
    }

    /// Stores `data` as the tournament's invitation, removing any previous one.
    @discardableResult
    static func replace(for tournament: Tournament, data: Data, fileName: String, uploadedBy: String,
                        modelContext: ModelContext) -> TournamentInvitation? {
        let tournamentID = tournament.id
        let existing = (try? modelContext.fetch(FetchDescriptor<TournamentInvitation>()))?
            .filter { $0.tournament?.id == tournamentID } ?? []
        for old in existing { delete(old, modelContext: modelContext) }

        let invitation = TournamentInvitation(fileData: data, fileName: fileName,
                                              contentType: TournamentInvitation.contentType(forFileName: fileName),
                                              uploadedBy: uploadedBy, tournament: tournament)
        modelContext.insert(invitation)
        return save(invitation, modelContext: modelContext) ? invitation : nil
    }

    @discardableResult
    static func save(_ invitation: TournamentInvitation, modelContext: ModelContext) -> Bool {
        PersistenceService.saveAndPush(modelContext: modelContext, modelName: "TournamentInvitation",
                                        failureMessage: "Einladung konnte nicht gespeichert werden.") {
            SupabaseSync.shared.pushTournamentInvitation(invitation)
        }
    }

    @discardableResult
    static func delete(_ invitation: TournamentInvitation, modelContext: ModelContext) -> Bool {
        let id = invitation.id
        let path = TournamentInvitationDBRow.path(for: invitation)
        modelContext.delete(invitation)
        return PersistenceService.deleteAndPush(modelContext: modelContext, modelName: "TournamentInvitation",
                                                 failureMessage: "Einladung konnte nicht gelöscht werden.") {
            SupabaseSync.shared.deleteTournamentInvitation(id, path: path)
        }
    }
}
