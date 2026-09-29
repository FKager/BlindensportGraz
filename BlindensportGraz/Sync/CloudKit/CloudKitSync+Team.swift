import CloudKit
import SwiftData
import Foundation

extension CloudKitSync {
    func pushTeam(_ team: Team) {
        let record = CKRecord(recordType: CKSchema.Team.recordType, recordID: recordID(team.id))
        record[CKSchema.Team.name] = team.name
        record[CKSchema.Team.sport] = team.sport
        record[CKSchema.Team.descriptionText] = team.descriptionText
        record[CKSchema.Team.createdAt] = team.createdAt
        save(record)
    }

    // Same gap as deleteMembership (CloudKitSync+TeamMembership.swift), for
    // Team's own delete path (TeamsListView.deleteTeams) — was also never
    // pushed until bug-163.
    func deleteTeam(_ id: UUID) {
        delete(recordType: CKSchema.Team.recordType, id: id)
    }

    func pullTeams(modelContext: ModelContext) async {
        for record in await fetchAll(recordType: CKSchema.Team.recordType) {
            guard let id = UUID(uuidString: record.recordID.recordName) else { continue }
            let name = record[CKSchema.Team.name] as? String ?? ""
            let sport = record[CKSchema.Team.sport] as? String ?? ""
            let descriptionText = record[CKSchema.Team.descriptionText] as? String ?? ""
            let createdAt = record[CKSchema.Team.createdAt] as? Date ?? .now

            var descriptor = FetchDescriptor<Team>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            if let existing = try? modelContext.fetch(descriptor).first {
                existing.name = name
                existing.sport = sport
                existing.descriptionText = descriptionText
            } else {
                let team = Team(id: id, name: name, sport: sport, descriptionText: descriptionText, createdAt: createdAt)
                modelContext.insert(team)
            }
        }
    }

    /// Creates and pushes any of `Team.defaultTeams` not already present in
    /// the LOCAL store (case-insensitive name match), so the club's standing
    /// teams exist automatically — a no-op once all four exist. Called once
    /// per launch from RootView.triggerBackgroundSync (right after syncAll)
    /// and again from TeamsListView's pull-to-refresh.
    ///
    /// Deliberately checks the local store, NOT a live CloudKit query —
    /// `syncAll` just ran immediately before every call site, so the local
    /// store already reflects the latest known remote state. An earlier
    /// version gated local creation behind its own live CKQuery and bailed
    /// out entirely (creating nothing, not even locally) if that query
    /// failed — which meant the whole feature silently never worked if
    /// CloudKit was unreachable/unauthenticated for any reason on a given
    /// device, regardless of retries (see bug-186 in buglog.json). Local
    /// team creation doesn't actually need CloudKit at all; only `pushTeam`
    /// below does, and it already fails silently/independently like every
    /// other push in this app if the network isn't there. The tradeoff is a
    /// narrow re-opened race (two devices seeding simultaneously, before
    /// either has pushed, could each create a duplicate) — accepted as a
    /// better tradeoff than a feature that doesn't reliably work at all for
    /// this single-club, at-most-a-few-admin-devices app.
    func ensureDefaultTeams(modelContext: ModelContext) async {
        let existingTeams = (try? modelContext.fetch(FetchDescriptor<Team>())) ?? []

        // One-time rename: the original sport-agnostic "Helfer" default team
        // was split into "Torball Helfer"/"Blindenfußball Helfer" (see
        // Team.defaultTeams). Renaming any already-created "Helfer" team in
        // place (same id, same memberships, still pushed under the same
        // CKRecord name) rather than leaving it orphaned and creating a
        // brand-new "Torball Helfer" team alongside it.
        if let legacyHelfer = existingTeams.first(where: {
            $0.name.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare("Helfer") == .orderedSame
        }) {
            legacyHelfer.name = "Torball Helfer"
            legacyHelfer.sport = "Torball"
            pushTeam(legacyHelfer)
        }

        let existingNames = Set(existingTeams.map { $0.name.trimmingCharacters(in: .whitespaces).lowercased() })
        for (name, sport) in Team.defaultTeams {
            guard !existingNames.contains(name.trimmingCharacters(in: .whitespaces).lowercased()) else { continue }
            let team = Team(name: name, sport: sport)
            modelContext.insert(team)
            pushTeam(team)
        }
        // Outside the Phase 8 service layer deliberately — CloudKitSync
        // itself sits below TeamService, it can't depend on it; see
        // CloudKitSync.swift's syncAll for the same reasoning.
        try? modelContext.save()
    }
}
