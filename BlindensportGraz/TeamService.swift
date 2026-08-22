import Foundation
import SwiftData

/// Thin wrapper over `PersistenceService` for `Team` — see that file's doc
/// comment for why this pattern (not one generic type) is used at call
/// sites. Every other `*Service` in this app follows this exact shape.
@MainActor
enum TeamService {
    @discardableResult
    static func save(_ team: Team, modelContext: ModelContext) -> Bool {
        PersistenceService.saveAndPush(modelContext: modelContext, modelName: "Team",
                                        failureMessage: "Team konnte nicht gespeichert werden.") {
            CloudKitSync.shared.pushTeam(team)
        }
    }

    /// Batch variant for `TeamImportExport`'s import — a team-roster JSON
    /// file touches Team, TeamMembership, AND Member records in one pass
    /// (see `importMembership`); one save covers the whole file, then
    /// pushes everything touched only on save success (previously pushed
    /// each record mid-loop, before the batch save even ran).
    @discardableResult
    static func saveImportBatch(teams: [Team], memberships: [TeamMembership], members: [Member],
                                 modelContext: ModelContext) -> Bool {
        PersistenceService.saveAndPush(modelContext: modelContext, modelName: "Team (batch import)",
                                        failureMessage: "Team-Import konnte nicht gespeichert werden.") {
            for team in teams { CloudKitSync.shared.pushTeam(team) }
            for membership in memberships { CloudKitSync.shared.pushMembership(membership) }
            for member in members { CloudKitSync.shared.pushMember(member) }
        }
    }

    @discardableResult
    static func delete(_ team: Team, modelContext: ModelContext) -> Bool {
        let id = team.id
        modelContext.delete(team)
        return PersistenceService.deleteAndPush(modelContext: modelContext, modelName: "Team",
                                                 failureMessage: "Team konnte nicht gelöscht werden.") {
            CloudKitSync.shared.deleteTeam(id)
        }
    }
}
