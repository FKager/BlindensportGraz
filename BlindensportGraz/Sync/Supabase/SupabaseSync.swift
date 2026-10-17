import Foundation
import Supabase
import SwiftData
import os

/// Keeps the local SwiftData cache in sync with the club data in Supabase
/// (v0.3.0; replaces the former CloudKit public-database sync).
///
/// - Writes go through the durable `PendingPush` outbox: record locally,
///   upsert/delete via PostgREST with a short retry, clear the outbox row on
///   success. `drainOutbox` replays anything left over (offline, app killed).
/// - Pulls are incremental: per table, only rows whose `updated_at` is at or
///   after the stored cursor, plus `public.deletions` since its cursor. A
///   full pull (no cursor) also removes local rows the server no longer
///   returns — which is how a change of account, role or approval (the
///   "access signature") shrinks or grows what this device holds.
/// - Anonymous and pending accounts only get `public_schedule`; everything
///   else is removed from the cache (the server wouldn't return it anyway).
///
/// The server enforces all access rules (RLS); this class never decides who
/// may see or change what. A push the server refuses (401/403/42501) is
/// dropped from the outbox instead of being retried forever.
@MainActor
final class SupabaseSync {
    static let shared = SupabaseSync()

    let logger = Logger(subsystem: "it.a11y.BlindensportGraz", category: "SupabaseSync")
    var client: SupabaseClient { SupabaseClientSingleton.shared.client }

    /// Set once at launch (`BlindensportGrazApp.init`). Without it (unit
    /// tests) the outbox is skipped and pushes are best-effort only.
    var modelContainer: ModelContainer?

    private var _outboxContext: ModelContext?
    private var outboxContext: ModelContext? {
        if let _outboxContext { return _outboxContext }
        guard let modelContainer else { return nil }
        let context = ModelContext(modelContainer)
        _outboxContext = context
        return context
    }

    let defaults = UserDefaults.standard
    /// Rows uploaded by the CloudKit handover without an outbox entry
    /// (images, receipts): not pruned during that sync.
    var handoverKeep: Set<UUID> = []
    private var handoverFailed = false
    init() {}

    // MARK: - Retry

    /// Up to 4 attempts (0.5 s / 1 s / 2 s backoff). Returns `.denied` without
    /// retrying when the server refuses the write for good.
    enum Outcome { case done, failed, denied }

    func performWithRetry(_ description: String, operation: () async throws -> Void) async -> Outcome {
        let backoffs: [Duration] = [.milliseconds(500), .seconds(1), .seconds(2)]
        var lastError: Error?
        for attempt in 0...backoffs.count {
            do {
                try await operation()
                SyncState.shared.markSynced()
                return .done
            } catch {
                lastError = error
                if Self.isDenied(error) {
                    logger.error("\(description, privacy: .public) refused by the server: \(String(describing: error), privacy: .public)")
                    SyncState.shared.markFailed("\(description): \(error)")
                    return .denied
                }
                guard attempt < backoffs.count else { break }
                try? await Task.sleep(for: backoffs[attempt])
            }
        }
        logger.error("\(description, privacy: .public) failed after \(backoffs.count + 1) attempts: \(String(describing: lastError), privacy: .public)")
        SyncState.shared.markFailed("\(description): \(lastError.map { String(describing: $0) } ?? "-")")
        return .failed
    }

    /// Permission/validation refusals — retrying can't help.
    nonisolated static func isDenied(_ error: Error) -> Bool {
        if let error = error as? PostgrestError {
            // 42501 RLS / privilege, 23xxx constraint violations, PGRST3xx JWT.
            let code = error.code ?? ""
            return code == "42501" || code.hasPrefix("23") || code.hasPrefix("PGRST3")
        }
        if let error = error as? StorageError {
            return ["400", "401", "403", "413"].contains(error.statusCode ?? "")
        }
        return false
    }

    // MARK: - Push

    /// Upsert one row (outbox-backed).
    func save<Row: Encodable>(_ row: Row, table: String, id: UUID) {
        let payload = (try? PostgrestClient.Configuration.jsonEncoder.encode(row)) ?? Data()
        enqueue(operation: PendingPush.saveOperation, table: table, id: id, payload: payload)
        Task {
            let outcome = await performWithRetry("push to \(table) \(id)") {
                try await self.upsert(payload: payload, table: table)
            }
            if outcome != .failed { self.clearOutboxEntry(table: table, id: id) }
        }
    }

    /// Delete one row (outbox-backed).
    func delete(table: String, id: UUID) {
        enqueue(operation: PendingPush.deleteOperation, table: table, id: id, payload: Data())
        Task {
            let outcome = await performWithRetry("delete from \(table) \(id)") {
                try await self.client.from(table).delete().eq("id", value: id.uuidString).execute()
            }
            if outcome != .failed { self.clearOutboxEntry(table: table, id: id) }
        }
    }

    private func upsert(payload: Data, table: String) async throws {
        let row = try PostgrestClient.Configuration.jsonDecoder.decode(AnyJSON.self, from: payload)
        try await client.from(table).upsert(row, onConflict: "id", returning: .minimal).execute()
    }

    // MARK: - Outbox

    private func enqueue(operation: String, table: String, id: UUID, payload: Data) {
        guard let outboxContext else { return }
        PendingPush.enqueue(in: outboxContext, operation: operation, recordType: table,
                            recordName: id.uuidString, payload: payload)
        refreshPendingCount()
    }

    private func clearOutboxEntry(table: String, id: UUID) {
        guard let outboxContext else { return }
        PendingPush.clear(recordName: id.uuidString, recordType: table, in: outboxContext)
        refreshPendingCount()
    }

    private func refreshPendingCount() {
        guard let outboxContext else { return }
        SyncState.shared.setPendingCount(PendingPush.count(in: outboxContext))
    }

    /// One attempt per queued write, oldest first; called at the start of
    /// `syncAll` and when the network returns. Refused writes are dropped.
    func drainOutbox() async {
        guard let outboxContext else { return }
        let rows = PendingPush.all(in: outboxContext)
        guard !rows.isEmpty else { refreshPendingCount(); return }

        for row in rows where Self.outboxTables.contains(row.recordType) {
            do {
                if row.operation == PendingPush.deleteOperation {
                    guard let id = UUID(uuidString: row.recordName) else { outboxContext.delete(row); continue }
                    try await client.from(row.recordType).delete().eq("id", value: id.uuidString).execute()
                } else {
                    guard !row.payloadData.isEmpty else { outboxContext.delete(row); continue }
                    try await upsert(payload: row.payloadData, table: row.recordType)
                }
                SyncState.shared.markSynced()
                outboxContext.delete(row)
            } catch where Self.isDenied(error) {
                logger.error("outbox: dropping refused \(row.operation, privacy: .public) for \(row.recordType, privacy: .public) \(row.recordName, privacy: .public): \(String(describing: error), privacy: .public)")
                outboxContext.delete(row)
            } catch {
                row.attemptCount += 1
                row.lastAttemptAt = .now
                row.lastError = String(describing: error)
            }
        }
        try? outboxContext.save()
        refreshPendingCount()
    }

    /// True if this row still has an unconfirmed local write — never prune it.
    func hasPendingPush(_ id: UUID) -> Bool {
        guard let outboxContext else { return false }
        let name = id.uuidString
        let descriptor = FetchDescriptor<PendingPush>(predicate: #Predicate { $0.recordName == name })
        return handoverKeep.contains(id) || ((try? outboxContext.fetchCount(descriptor)) ?? 0) > 0
    }

    // MARK: - Fetch helpers

    /// Rows changed at/after `since` (all rows when nil), oldest first, paged.
    func fetchChanged<Row: Decodable & Sendable>(_ table: String, since: Date?,
                                                  columns: String = "*") async throws -> [Row] {
        var collected: [Row] = []
        let pageSize = 1000
        var offset = 0
        while true {
            var query = client.from(table).select(columns)
            if let since { query = query.gte("updated_at", value: Self.iso(since)) }
            let page: [Row] = try await query
                .order("updated_at", ascending: true)
                .order("id", ascending: true)
                .range(from: offset, to: offset + pageSize - 1)
                .execute().value
            collected += page
            guard page.count == pageSize else { return collected }
            offset += pageSize
        }
    }

    nonisolated static func iso(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    // MARK: - Cursors

    private func cursorKey(_ table: String) -> String {
        "SupabaseSync.cursor.\(SupabaseConfig.projectURL?.host() ?? "-").\(table)"
    }

    func cursor(_ table: String) -> Date? { defaults.object(forKey: cursorKey(table)) as? Date }

    func setCursor(_ table: String, _ date: Date?) {
        guard let date else { return }
        if let current = cursor(table), current >= date { return }
        defaults.set(date, forKey: cursorKey(table))
    }

    func resetCursors() {
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("SupabaseSync.cursor.") {
            defaults.removeObject(forKey: key)
        }
    }

    /// Who this device syncs as. A different signature than last time means
    /// the visible data may differ: start over with a full pull.
    enum Access: Equatable {
        case scheduleOnly
        case full(signature: String)
    }

    func currentAccess() -> Access {
        guard let auth = AuthContext.current, let claims = auth.claims else { return .scheduleOnly }
        let isAdmin = claims.role == .admin || claims.role == .root
        guard claims.approved || isAdmin else { return .scheduleOnly }
        return .full(signature: "\(claims.userID.uuidString)|\(claims.role?.rawValue ?? "-")|\(claims.approved)")
    }

    private var signatureKey: String { "SupabaseSync.accessSignature.\(SupabaseConfig.projectURL?.host() ?? "-")" }

    // MARK: - Lookups (shared by pulls, services and the backup importer)

    func findTeam(_ id: UUID?, modelContext: ModelContext) -> Team? {
        guard let id else { return nil }
        var descriptor = FetchDescriptor<Team>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    func findTeams(_ ids: [UUID], modelContext: ModelContext) -> [Team] {
        ids.compactMap { findTeam($0, modelContext: modelContext) }
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

    /// Any SportEvent subclass (Training, Tournament) resolves too.
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

    // MARK: - Sync

    /// Pull order and `save()` stages are load-bearing (inherited from the
    /// CloudKit sync): later stages resolve relationships against rows
    /// earlier stages inserted, and smaller save batches avoid the SwiftData
    /// Release-build crash on large relationship-heavy transactions
    /// (bug-221, bug-371).
    func syncAll(modelContext: ModelContext) async {
        SyncState.shared.markSyncing()
        handoverFailed = false
        await handOverFromCloudKitIfNeeded(modelContext: modelContext)
        defer { handoverKeep.removeAll() }
        guard !handoverFailed else {
            SyncState.shared.markFailed("Übergabe der lokalen Daten fehlgeschlagen – wird beim nächsten Sync wiederholt.")
            return
        }
        await drainOutbox()

        let access = currentAccess()
        let signature: String
        switch access {
        case .scheduleOnly: signature = "schedule"
        case .full(let value): signature = value
        }
        if defaults.string(forKey: signatureKey) != signature {
            resetCursors()
            defaults.set(signature, forKey: signatureKey)
        }

        do {
            switch access {
            case .scheduleOnly:
                try await pullSchedule(modelContext: modelContext)
                try modelContext.save()
            case .full:
                try await pullAll(modelContext: modelContext)
            }
            SyncState.shared.markSynced()
        } catch {
            logger.error("sync failed: \(String(describing: error), privacy: .public)")
            try? modelContext.save()
            SyncState.shared.markFailed(String(describing: error))
        }
    }

    private func pullAll(modelContext: ModelContext) async throws {
        try await pullMembers(modelContext: modelContext)
        try await pullTeams(modelContext: modelContext)
        try modelContext.save()
        try await pullMemberships(modelContext: modelContext)
        try modelContext.save()
        try await pullEvents(modelContext: modelContext)
        try modelContext.save()
        try await pullEventImages(modelContext: modelContext)
        try await pullExpenseReceipts(modelContext: modelContext)
        try modelContext.save()
        try await pullParticipations(modelContext: modelContext)
        try await pullEventMemberships(modelContext: modelContext)
        try await pullBudgetEntries(modelContext: modelContext)
        try modelContext.save()
        try await pullAttendances(modelContext: modelContext)
        try modelContext.save()
        try await pullTrainingFavorites(modelContext: modelContext)
        try await pullMemberChangeRequests(modelContext: modelContext)
        try await pullWelcomeContent(modelContext: modelContext)
        try modelContext.save()
        try await applyDeletions(modelContext: modelContext)
        try modelContext.save()
    }

    // MARK: - Handover from the CloudKit era

    /// Set once this device's CloudKit-era data has been handed over (a new
    /// key: devices that ran the earlier, lossy version run this once more).
    private static let handoverKey = "SupabaseSync.cloudKitHandoverDone"

    /// Tables the Supabase outbox writes to. Any other `recordType` in the
    /// outbox is a CloudKit-era row (archived CKRecord) that can't be replayed.
    static let outboxTables: Set<String> = [
        "teams", "team_memberships", "members", "member_contacts", "events", "attendances",
        "event_participations", "event_memberships", "budget_entries", "training_favorites",
        "welcome_content", "member_change_requests"
    ]

    var isHandoverDone: Bool { defaults.bool(forKey: Self.handoverKey) }

    /// First full-access sync after the CloudKit era: nothing on this device
    /// may be lost. Uploads every local row the server doesn't have, and
    /// re-sends every row still queued in the CloudKit-era outbox (edits that
    /// never reached CloudKit), before the first pull prunes anything. Rows
    /// queued here are protected from pruning by their outbox entries
    /// (`hasPendingPush`); images/receipts, which aren't outbox-backed, via
    /// `handoverKeep`. The server decides what this account may write;
    /// refused rows are dropped and then pruned like any other.
    ///
    /// Trade-off: a row deleted in CloudKit that a stale device still holds
    /// comes back. Losing data that never left a phone is worse.
    private func handOverFromCloudKitIfNeeded(modelContext: ModelContext) async {
        guard !isHandoverDone, case .full = currentAccess() else { return }
        let queued = cloudKitEraOutboxIDs()

        do {
            func missing(_ table: String) async throws -> (UUID) -> Bool {
                let onServer = try await serverIDs(table)
                return { !onServer.contains($0) || queued.contains($0) }
            }
            func all<Model: PersistentModel>(_ type: Model.Type) -> [Model] {
                (try? modelContext.fetch(FetchDescriptor<Model>())) ?? []
            }
            // Parents before children, so foreign keys resolve on the server
            // (anything that still lands too early stays queued and is retried).
            var upload = try await missing("members")
            for member in all(Member.self) where upload(member.id) { pushMember(member) }
            upload = try await missing("teams")
            for team in all(Team.self) where upload(team.id) { pushTeam(team) }
            upload = try await missing("team_memberships")
            for membership in all(TeamMembership.self) where upload(membership.id) { pushMembership(membership) }
            upload = try await missing("events")
            for event in all(SportEvent.self) where upload(event.id) { pushEvent(event) }
            upload = try await missing("attendances")
            for attendance in all(Attendance.self) where upload(attendance.id) { pushAttendance(attendance) }
            upload = try await missing("event_participations")
            for participation in all(EventParticipation.self) where upload(participation.id) {
                pushParticipation(participation)
            }
            upload = try await missing("event_memberships")
            for membership in all(EventMembership.self) where upload(membership.id) { pushEventMembership(membership) }
            upload = try await missing("budget_entries")
            for entry in all(BudgetEntry.self) where upload(entry.id) { pushBudgetEntry(entry) }
            upload = try await missing("training_favorites")
            for favorite in all(TrainingFavorite.self) where upload(favorite.id) { pushTrainingFavorite(favorite) }
            upload = try await missing("welcome_content")
            for content in all(WelcomeContent.self) where upload(content.id) { pushWelcomeContent(content) }
            // Change requests carry the proposer's account: only re-send the
            // ones this device itself had queued, never other people's.
            for request in all(MemberChangeRequest.self) where queued.contains(request.id) {
                pushMemberChangeRequest(request)
            }
            upload = try await missing("event_images")
            for image in all(EventImage.self) where upload(image.id) {
                handoverKeep.insert(image.id)
                pushEventImage(image)
            }
            upload = try await missing("expense_receipts")
            for receipt in all(ExpenseReceipt.self) where upload(receipt.id) {
                handoverKeep.insert(receipt.id)
                pushExpenseReceipt(receipt)
            }
        } catch {
            // Try again on the next sync; the pull below must not prune yet.
            logger.error("handover: could not list server rows: \(String(describing: error), privacy: .public)")
            handoverFailed = true
            return
        }

        if let outboxContext {
            for row in PendingPush.all(in: outboxContext) where !Self.outboxTables.contains(row.recordType) {
                outboxContext.delete(row)
            }
            try? outboxContext.save()
            refreshPendingCount()
        }
        defaults.set(true, forKey: Self.handoverKey)
        logger.info("handover from CloudKit done (\(queued.count) queued CloudKit-era writes re-sent)")
    }

    /// Ids of rows queued in the CloudKit-era outbox (record name = id).
    private func cloudKitEraOutboxIDs() -> Set<UUID> {
        guard let outboxContext else { return [] }
        return Set(PendingPush.all(in: outboxContext)
            .filter { !Self.outboxTables.contains($0.recordType) }
            .compactMap { UUID(uuidString: $0.recordName) })
    }

    /// Every id in `table` this account can see (paged).
    private func serverIDs(_ table: String) async throws -> Set<UUID> {
        var ids = Set<UUID>()
        let pageSize = 1000
        var offset = 0
        while true {
            let page: [IDOnlyRow] = try await client.from(table).select("id").order("id")
                .range(from: offset, to: offset + pageSize - 1).execute().value
            ids.formUnion(page.map(\.id))
            guard page.count == pageSize else { return ids }
            offset += pageSize
        }
    }
}

nonisolated struct IDOnlyRow: Decodable, Sendable {
    let id: UUID
}
