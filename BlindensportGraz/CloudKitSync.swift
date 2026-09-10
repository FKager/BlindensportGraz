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

    /// Set once at launch (`BlindensportGrazApp.init`). When nil — e.g. in a
    /// unit test that never wired it — the `PendingPush` outbox is skipped
    /// entirely and `save`/`delete` behave exactly as they did before the
    /// outbox existed (best-effort push, no durable record).
    var modelContainer: ModelContainer?

    /// Dedicated context for the outbox so its writes never piggyback on an
    /// unrelated `mainContext.save()` and vice versa. Lazily made on first use.
    private var _outboxContext: ModelContext?
    private var outboxContext: ModelContext? {
        if let _outboxContext { return _outboxContext }
        guard let modelContainer else { return nil }
        let context = ModelContext(modelContainer)
        _outboxContext = context
        return context
    }

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
    /// Returns `true` if `operation` eventually succeeded, `false` if every
    /// attempt failed. Callers that enqueued a `PendingPush` use the result
    /// to decide whether to clear it or leave it for `drainOutbox`.
    @discardableResult
    func performWithRetry(_ description: String, operation: () async throws -> Void) async -> Bool {
        let backoffs: [UInt64] = [500_000_000, 1_000_000_000, 2_000_000_000] // 0.5s, 1s, 2s
        var lastError: Error?
        for attempt in 0...backoffs.count {
            do {
                try await operation()
                // Real, confirmed activity with CloudKit — drives the
                // user-visible sync indicator (audit.md SwiftData & CloudKit
                // Finding 3 / Enhancement #3), not a static decoration.
                SyncState.shared.markSynced()
                return true
            } catch {
                lastError = error
                guard attempt < backoffs.count else { break }
                try? await Task.sleep(nanoseconds: backoffs[attempt])
            }
        }
        logger.error("\(description, privacy: .public) failed after \(backoffs.count + 1) attempts: \(String(describing: lastError), privacy: .public)")
        SyncState.shared.markFailed()
        return false
    }

    /// Push helper used by every per-model `pushX(_:)`. Records the write in
    /// the durable `PendingPush` outbox first, fires the inline retry, and
    /// clears the outbox row only once CloudKit confirms it — a write that
    /// outlives its retries stays queued for `drainOutbox`
    /// (architecture-review.md 2.2). Still fire-and-forget from the UI's
    /// perspective; the outbox is what makes "fire" durable.
    func save(_ record: CKRecord) {
        let recordName = record.recordID.recordName
        enqueue(operation: PendingPush.saveOperation, recordType: record.recordType,
                recordName: recordName, record: record)
        Task {
            let ok = await self.performWithRetry("push for \(record.recordType) \(recordName)") {
                try await self.upsert(record)
            }
            if ok { self.clearOutboxEntry(recordName: recordName) }
        }
    }

    /// Delete helper used by every per-model `deleteX(_:)`.
    func delete(recordType: String, id: UUID) {
        let recordName = id.uuidString
        enqueue(operation: PendingPush.deleteOperation, recordType: recordType,
                recordName: recordName, record: nil)
        Task {
            let ok = await self.performWithRetry("delete for \(recordType) \(id)") {
                try await self.publicDB.deleteRecord(withID: self.recordID(id))
            }
            if ok { self.clearOutboxEntry(recordName: recordName) }
        }
    }

    // MARK: - PendingPush outbox

    private func enqueue(operation: String, recordType: String, recordName: String, record: CKRecord?) {
        guard let outboxContext else { return }
        let payload = record.flatMap { PendingPush.archived($0) } ?? Data()
        PendingPush.enqueue(in: outboxContext, operation: operation, recordType: recordType,
                            recordName: recordName, payload: payload)
        refreshPendingCount()
    }

    private func clearOutboxEntry(recordName: String) {
        guard let outboxContext else { return }
        PendingPush.clear(recordName: recordName, in: outboxContext)
        refreshPendingCount()
    }

    private func refreshPendingCount() {
        guard let outboxContext else { return }
        SyncState.shared.setPendingCount(PendingPush.count(in: outboxContext))
    }

    /// Re-attempts every queued write once, oldest first. Called at the start
    /// of `syncAll` and whenever the network comes back (see `RootView`).
    /// Each attempt is a single try — `drainOutbox` being called again *is*
    /// the retry loop — so a persistently-unreachable CloudKit just leaves
    /// the rows (and the banner count) in place rather than spinning.
    func drainOutbox() async {
        guard let outboxContext else { return }
        let rows = PendingPush.all(in: outboxContext)
        guard !rows.isEmpty else { refreshPendingCount(); return }

        for row in rows {
            let succeeded: Bool
            switch row.operation {
            case PendingPush.deleteOperation:
                succeeded = await attemptOutboxDelete(row)
            default:
                guard let record = row.decodedRecord() else {
                    // Payload missing/corrupt — it can never succeed; drop it
                    // rather than retrying forever.
                    logger.error("outbox: dropping unreplayable row for \(row.recordType, privacy: .public) \(row.recordName, privacy: .public)")
                    outboxContext.delete(row)
                    continue
                }
                succeeded = await attemptOutboxSave(record, description: "outbox push for \(row.recordType) \(row.recordName)")
            }
            if succeeded {
                outboxContext.delete(row)
            } else {
                row.attemptCount += 1
                row.lastAttemptAt = .now
            }
        }
        try? outboxContext.save()
        refreshPendingCount()
    }

    private func attemptOutboxSave(_ record: CKRecord, description: String) async -> Bool {
        do {
            try await upsert(record)
            SyncState.shared.markSynced()
            return true
        } catch {
            logger.error("\(description, privacy: .public) failed: \(String(describing: error), privacy: .public)")
            return false
        }
    }

    private func attemptOutboxDelete(_ row: PendingPush) async -> Bool {
        guard let id = UUID(uuidString: row.recordName) else { return true } // unparseable → drop
        do {
            try await publicDB.deleteRecord(withID: recordID(id))
            SyncState.shared.markSynced()
            return true
        } catch let error as CKError where error.code == .unknownItem {
            // Already gone on the server — the delete is effectively done.
            return true
        } catch {
            logger.error("outbox delete for \(row.recordType, privacy: .public) \(row.recordName, privacy: .public) failed: \(String(describing: error), privacy: .public)")
            return false
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

    /// Pulls EVERY record of `recordType`, following CloudKit's query cursor
    /// across pages. `CKDatabase.records(matching:)` returns at most one
    /// server page (~100 rows) plus a `queryCursor` for the rest — an earlier
    /// version discarded that cursor (`let (results, _) = …`), so any record
    /// type larger than one page (the `ClubMember` roster is ~200) was
    /// silently truncated on every `syncAll` pull, leaving freshly-synced
    /// devices missing roster/attendance rows (architecture-review.md 2.1 /
    /// buglog bug-387). `RootCLI`'s server-to-server client already pages via
    /// `continuationMarker`; this brings the on-device path to parity.
    ///
    /// On any error the whole pull for this type returns `[]` (unchanged
    /// behaviour): callers only ever upsert what comes back, so an empty
    /// result is a no-op rather than a partial reconciliation against a
    /// half-fetched set.
    func fetchAll(recordType: String) async -> [CKRecord] {
        var collected: [CKRecord] = []
        do {
            let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
            var page = try await publicDB.records(matching: query, resultsLimit: CKQueryOperation.maximumResults)
            while true {
                collected.append(contentsOf: page.matchResults.compactMap { try? $1.get() })
                guard let cursor = page.queryCursor else { break }
                page = try await publicDB.records(continuingMatchFrom: cursor, resultsLimit: CKQueryOperation.maximumResults)
            }
            return collected
        } catch {
            logger.error("pull failed for \(recordType, privacy: .public) after \(collected.count) record(s): \(String(describing: error), privacy: .public)")
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
    /// **2026-09-07**: after Production CloudKit went from empty to ~190
    /// real records (first time any Release/TestFlight build ever had to
    /// pull this much relationship-heavy data at once — see bug-371), the
    /// final stage below (EventImages/ExpenseReceipts/Participations/
    /// Attendances/TrainingFavorites/RoleChangeLogs, previously all batched
    /// into one unsaved transaction) crashed on-device with a
    /// `_assertionFailure` inside SwiftData's `BackingData.set` —
    /// Release-build-only, matching a known unresolved SwiftData framework
    /// bug (developer.apple.com/forums/thread/781246) triggered by large
    /// batches of relationship-heavy inserts/updates. Not reproducible in
    /// Debug (same reason bug-221's crash never showed there either).
    /// Mitigated the same way bug-221 fixed the earlier "TeamMembership
    /// silently dropped" issue: split into smaller `save()`-bounded stages
    /// so no single transaction touches this many relationship-carrying
    /// rows at once. `pullAttendances` gets its own save — it's by far the
    /// largest/most relationship-heavy set (Attendance -> event + membership)
    /// among these.
    func syncAll(modelContext: ModelContext) async {
        SyncState.shared.markSyncing()
        // Push anything still queued from a previous offline/failed session
        // before pulling, so a full pass doesn't overwrite local edits that
        // never made it out (architecture-review.md 2.2).
        await drainOutbox()
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
        try? modelContext.save()
        await pullParticipations(modelContext: modelContext)
        try? modelContext.save()
        await pullAttendances(modelContext: modelContext)
        try? modelContext.save()
        await pullTrainingFavorites(modelContext: modelContext)
        await pullRoleChangeLogs(modelContext: modelContext)
        await pullMemberChangeRequests(modelContext: modelContext)
        // Outside the Phase 8 service layer deliberately: this saves data
        // just PULLED from CloudKit into the local store, the opposite
        // direction from every `*Service.save`/`.delete` (local edit -> push
        // to CloudKit) — there's no push to gate on here, and CloudKitSync
        // itself sits below the service layer, so it can't depend on it.
        try? modelContext.save()
        SyncState.shared.markSynced()
    }
}
