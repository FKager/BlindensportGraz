import Foundation
import SwiftData

/// Self-service roster edits awaiting admin review — architecture-review.md
/// §5 P2. One of the two areas `MemberService`'s own doc comment already
/// calls out as needing visible failure signaling (roster data), so this
/// follows the exact same `PersistenceService` pattern.
@MainActor
enum MemberChangeRequestService {
    @discardableResult
    static func save(_ request: MemberChangeRequest, modelContext: ModelContext) -> Bool {
        PersistenceService.saveAndPush(modelContext: modelContext, modelName: "MemberChangeRequest",
                                        failureMessage: "Änderungsantrag konnte nicht gespeichert werden.") {
            CloudKitSync.shared.pushMemberChangeRequest(request)
        }
    }

    /// Applies `request`'s proposed fields to `member`, saves+pushes the
    /// member, then marks the request approved and saves+pushes it too. If
    /// the member save fails, the request is left untouched (still
    /// pending) rather than marked approved against data that never
    /// actually persisted.
    @discardableResult
    static func approve(_ request: MemberChangeRequest, member: Member, reviewedBy: String, modelContext: ModelContext) -> Bool {
        request.apply(to: member)
        guard MemberService.save(member, modelContext: modelContext) else { return false }
        request.status = MemberChangeRequest.approvedStatus
        request.reviewedBy = reviewedBy
        request.reviewedAt = .now
        return save(request, modelContext: modelContext)
    }

    @discardableResult
    static func reject(_ request: MemberChangeRequest, reviewedBy: String, modelContext: ModelContext) -> Bool {
        request.status = MemberChangeRequest.rejectedStatus
        request.reviewedBy = reviewedBy
        request.reviewedAt = .now
        return save(request, modelContext: modelContext)
    }
}
