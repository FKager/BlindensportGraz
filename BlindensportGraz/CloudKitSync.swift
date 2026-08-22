import CloudKit
import SwiftData
import Foundation
import os

/// Shares Team/Event/Training/Tournament/Membership/Participation/Member/
/// EventImage data across different users' Apple IDs via CloudKit's public
/// database.
/// SwiftData's own CloudKit integration only mirrors the private, per-user
/// database, so it can't do this — this layer pushes/pulls plain CKRecords
/// instead, matching local SwiftData objects by their stable `id` (used as
/// the CKRecord name).
///
/// Only non-sensitive identity fields (firstName, lastName, role,
/// isGrazerVSCMember) are ever published for a User — email and the Apple
/// identifier stay device-local. The Member roster (name/address/contact
/// details) is admin-managed data, synced so every admin's device and the
/// account-creation match check see the same roster. The CKRecord type
/// stays the historical "ClubMember" string (not renamed to "Member")
/// so already-synced production data keeps resolving after this
/// app-side rename — see cerebrum.md 2026-08-01.
///
/// Every CKRecord type/field name comes from `CKSchema.swift`, not a bare
/// string literal — see that file's doc comment.
///
/// Split by model into `CloudKitSync+*.swift` extension files (audit.md
/// Architecture Finding 2 — this used to be a single 921-line file). This
/// base file holds only what every extension needs: the CKContainer/
/// database, the shared logger, the retry helper, `upsert`, `syncAll()`'s
/// pull orchestration, and the `find*` lookup helpers several pull
/// functions share. All of these are `internal` (not `private`) so the
/// per-model extension files in other source files can call them — a plain
/// `private` member is invisible outside its own file in Swift, unlike
/// `private` within a single file's own multiple extensions.
@MainActor
final class CloudKitSync {
    static let shared = CloudKitSync()

    let container = CKContainer(identifier: "iCloud.it.a11y.BlindensportGraz")
    var publicDB: CKDatabase { container.publicCloudDatabase }
    let logger = Logger(subsystem: "it.a11y.BlindensportGraz", category: "CloudKitSync")

    init() {}

    func recordID(_ id: UUID) -> CKRecord.ID {
        CKRecord.ID(recordName: id.uuidString)
    }

    /// Retries `operation` up to 3 times (the original attempt plus up to 3
    /// retries) with short exponential backoff (0.5s / 1s / 2s between
    /// attempts) before giving up and logging final failure via `logger` —
    /// audit.md SwiftData & CloudKit Finding 1 (every write used to be
    /// fire-and-forget with `print`-statement-only error handling, invisible on a
    /// real device, and no retry at all). Deliberately simple: no offline
    /// queue, no infinite retry — audit.md frames exactly this as the
    /// achievable fix, not full offline-first sync.
    ///
    /// `await`ed from inside a `Task` at each call site rather than being a
    /// `Task` itself, so a caller that needs cleanup to run exactly once
    /// after every attempt is exhausted (see `CloudKitSync+EventImage.swift`'s
    /// temp-file removal) can wrap it in its own
    /// `Task { defer { ... }; await performWithRetry(...) }`.
    func performWithRetry(_ description: String, operation: () async throws -> Void) async {
        let backoffs: [UInt64] = [500_000_000, 1_000_000_000, 2_000_000_000] // 0.5s, 1s, 2s
        var lastError: Error?
        for attempt in 0...backoffs.count {
            do {
                try await operation()
                // Real, confirmed activity with CloudKit — drives the
                // user-visible sync indicator (audit.md SwiftData & CloudKit
                // Finding 3 / Enhancement #3), not a static decoration.
                SyncState.shared.markSynced()
                return
            } catch {
                lastError = error
                guard attempt < backoffs.count else { break }
                try? await Task.sleep(nanoseconds: backoffs[attempt])
            }
        }
        logger.error("\(description, privacy: .public) failed after \(backoffs.count + 1) attempts: \(String(describing: lastError), privacy: .public)")
        SyncState.shared.markFailed()
    }

    /// Push helper used by every per-model `pushX(_:)` — retries via
    /// `performWithRetry`, logs final failure, never throws to the caller
    /// (pushes have always been fire-and-forget from the UI's perspective;
    /// this phase adds retry + real logging, not a synchronous/blocking
    /// push API — that would be a bigger behavior change than this phase's
    /// scope).
    func save(_ record: CKRecord) {
        Task {
            await self.performWithRetry("push for \(record.recordType) \(record.recordID.recordName)") {
                try await self.upsert(record)
            }
        }
    }

    /// Delete helper used by every per-model `deleteX(_:)`.
    func delete(recordType: String, id: UUID) {
        Task {
            let recordID = self.recordID(id)
            await self.performWithRetry("delete for \(recordType) \(id)") {
                try await self.publicDB.deleteRecord(withID: recordID)
            }
        }
    }

    /// Every push here builds a brand-new `CKRecord` instance rather than
    /// fetching the existing one first, so it never carries a
    /// `recordChangeTag`. `CKDatabase.save(_:)`'s default save policy
    /// (`.ifServerRecordUnchanged`) treats that as an unverifiable conflict
    /// and throws `CKError.serverRecordChanged` on any push after the first
    /// (i.e. inserts work, updates silently fail). Using
    /// `CKModifyRecordsOperation` with `.changedKeys` instead makes this a
    /// true insert-or-update: it always writes the fields present on the
    /// record, whether or not a server copy already exists.
    func upsert(_ record: CKRecord) async throws {
        try await withCheckedThrowingContinuation { continuation in
            let operation = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
            operation.savePolicy = .changedKeys
            operation.qualityOfService = .userInitiated
            operation.modifyRecordsResultBlock = { result in
                continuation.resume(with: result)
            }
            publicDB.add(operation)
        }
    }

    func fetchAll(recordType: String) async -> [CKRecord] {
        do {
            let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
            let (results, _) = try await publicDB.records(matching: query)
            return results.compactMap { try? $1.get() }
        } catch {
            logger.error("pull failed for \(recordType, privacy: .public): \(String(describing: error), privacy: .public)")
            return []
        }
    }

    // MARK: - Shared lookup helpers (used by multiple per-model pull functions)

    func findTeam(_ id: UUID?, modelContext: ModelContext) -> Team? {
        guard let id else { return nil }
        var descriptor = FetchDescriptor<Team>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    func findTeams(_ ids: [String], modelContext: ModelContext) -> [Team] {
        ids.compactMap { UUID(uuidString: $0) }
            .compactMap { findTeam($0, modelContext: modelContext) }
    }

    func findUser(_ id: UUID, modelContext: ModelContext) -> User? {
        var descriptor = FetchDescriptor<User>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    func findMember(_ id: UUID, modelContext: ModelContext) -> Member? {
        var descriptor = FetchDescriptor<Member>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    /// SportEvent is polymorphically fetchable — this resolves a Training or
    /// Tournament id just as well as a plain SportEvent id, since they're all
    /// the same underlying type hierarchy now.
    func findEvent(_ id: UUID, modelContext: ModelContext) -> SportEvent? {
        var descriptor = FetchDescriptor<SportEvent>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    func findMembership(_ id: UUID, modelContext: ModelContext) -> TeamMembership? {
        var descriptor = FetchDescriptor<TeamMembership>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    // MARK: - Pull orchestration

    /// Pull ordering is deliberate and load-bearing — later pulls resolve
    /// relationships (e.g. TeamMembership needs Team+User+Member already
    /// local) against entities earlier pulls just inserted. audit.md marked
    /// this ordering itself correct (Positive Finding 5), but that finding
    /// was only ever validated against small test fixtures.
    ///
    /// **Found live, 2026-08-22, on a real device doing its first full
    /// resync of real production-scale data (200 ClubMembers, 30
    /// TeamMemberships) against a freshly wiped local store**: this used to
    /// call `modelContext.save()` exactly once, at the very end of the
    /// whole sequence — every relationship-resolution lookup inside a later
    /// pull (`findTeam`/`findMember`/`findUser`, all plain
    /// `FetchDescriptor`+`#Predicate` fetches) ran against still-UNSAVED
    /// inserts from earlier pulls in the same pass. That silently broke
    /// every single `TeamMembership` pull's `guard let team = findTeam(...)
    /// else { continue }` (and, by the same mechanism, `pullParticipations`/
    /// `pullAttendances`, which depend on Events/Trainings/Tournaments/
    /// Memberships pulled earlier in the same still-unsaved pass) — Teams
    /// themselves synced fine (nothing needed to look them up), but every
    /// TeamMembership was silently dropped, exactly matching the observed
    /// symptom ("teams are there but no team members"). Now saves after
    /// every pull a later one depends on, so each stage's relationship
    /// lookups run against durable, queryable data.
    func syncAll(modelContext: ModelContext) async {
        SyncState.shared.markSyncing()
        await pullUserIdentities(modelContext: modelContext)
        await pullMembers(modelContext: modelContext)
        await pullTeams(modelContext: modelContext)
        try? modelContext.save()
        await pullMemberships(modelContext: modelContext)
        try? modelContext.save()
        await pullEvents(modelContext: modelContext)
        await pullTrainings(modelContext: modelContext)
        await pullTournaments(modelContext: modelContext)
        try? modelContext.save()
        await pullEventImages(modelContext: modelContext)
        await pullExpenseReceipts(modelContext: modelContext)
        await pullParticipations(modelContext: modelContext)
        await pullAttendances(modelContext: modelContext)
        await pullTrainingFavorites(modelContext: modelContext)
        await pullRoleChangeLogs(modelContext: modelContext)
        // Outside the Phase 8 service layer deliberately: this saves data
        // just PULLED from CloudKit into the local store, the opposite
        // direction from every `*Service.save`/`.delete` (local edit -> push
        // to CloudKit) — there's no push to gate on here, and CloudKitSync
        // itself sits below the service layer, so it can't depend on it.
        try? modelContext.save()
        SyncState.shared.markSynced()
    }
}
