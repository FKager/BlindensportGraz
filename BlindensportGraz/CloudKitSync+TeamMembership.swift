import CloudKit
import SwiftData
import Foundation

extension CloudKitSync {
    func pushMembership(_ membership: TeamMembership) {
        let record = CKRecord(recordType: CKSchema.TeamMembership.recordType, recordID: recordID(membership.id))
        record[CKSchema.TeamMembership.userID] = membership.user?.id.uuidString
        // Field key stays "clubMemberID" (not renamed) for wire compatibility
        // with already-synced production data — see CloudKitSync.swift's top doc comment.
        record[CKSchema.TeamMembership.clubMemberID] = membership.member?.id.uuidString
        record[CKSchema.TeamMembership.teamID] = membership.team.id.uuidString
        record[CKSchema.TeamMembership.role] = membership.role.rawValue
        record[CKSchema.TeamMembership.joinedAt] = membership.joinedAt
        save(record)
    }

    // Was missing entirely until bug-163: TeamsViews' roster swipe-to-delete
    // called modelContext.delete(membership) with no CloudKit counterpart, so
    // a "deleted" membership silently reappeared on the next pullMemberships
    // (find-or-create by id, see pullMemberships below) — and, combined with
    // TeamMembership lacking a cascade rule for its Attendance records at the
    // time, corrupted the local store outright (see the TeamMembership.
    // attendances doc comment in Models.swift). See CloudKitSync+Team.swift's
    // deleteTeam for the same gap on Team's own delete path.
    func deleteMembership(_ id: UUID) {
        delete(recordType: CKSchema.TeamMembership.recordType, id: id)
    }

    func pullMemberships(modelContext: ModelContext) async {
        for record in await fetchAll(recordType: CKSchema.TeamMembership.recordType) {
            guard let id = UUID(uuidString: record.recordID.recordName),
                  let teamIDString = record[CKSchema.TeamMembership.teamID] as? String, let teamID = UUID(uuidString: teamIDString),
                  let team = findTeam(teamID, modelContext: modelContext) else { continue }
            let user = (record[CKSchema.TeamMembership.userID] as? String).flatMap { UUID(uuidString: $0) }
                .flatMap { findUser($0, modelContext: modelContext) }
            // Field key stays "clubMemberID" on the wire — see CloudKitSync.swift's top doc comment.
            let member = (record[CKSchema.TeamMembership.clubMemberID] as? String).flatMap { UUID(uuidString: $0) }
                .flatMap { findMember($0, modelContext: modelContext) }
            // Exactly one side must resolve — a membership with neither is orphaned data.
            guard user != nil || member != nil else { continue }
            let role = MembershipRole.normalize(record[CKSchema.TeamMembership.role] as? String ?? "player")
            let joinedAt = record[CKSchema.TeamMembership.joinedAt] as? Date ?? .now

            var descriptor = FetchDescriptor<TeamMembership>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            if let existing = try? modelContext.fetch(descriptor).first {
                existing.role = role
            } else {
                let membership = TeamMembership(id: id, user: user, member: member, team: team, role: role, joinedAt: joinedAt)
                modelContext.insert(membership)
            }
        }
    }
}
