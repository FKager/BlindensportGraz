import Foundation
import SwiftData
import os

/// Durable outbox for writes to Supabase — architecture-review.md 2.2 / 2.3.
///
/// Every push/delete first writes a `PendingPush` row here; the row is
/// deleted once the server confirms (or refuses) the write. Rows that
/// outlive their inline retries are re-attempted by
/// `SupabaseSync.drainOutbox()` (run at the start of every `syncAll` and
/// whenever the network comes back), and their count drives the
/// "N Änderungen noch nicht synchronisiert" banner.
///
/// This model is **local-only** — never itself synced; it *is* the sync
/// mechanism.
@Model
final class PendingPush {
    static let saveOperation = "save"
    static let deleteOperation = "delete"

    @Attribute(.unique) var id: UUID = UUID()
    /// The Supabase table, e.g. "events".
    var recordType: String = ""
    /// The row's (and the SwiftData model's) `id.uuidString`. Together with
    /// `recordType` the dedupe key: at most one pending write per table row
    /// (a Member is two rows: `members` and `member_contacts`).
    var recordName: String = ""
    /// `PendingPush.saveOperation` or `.deleteOperation`.
    var operation: String = PendingPush.saveOperation
    /// The row as JSON (PostgREST encoding) for a save; empty for a delete.
    var payloadData: Data = Data()
    var enqueuedAt: Date = Date.now
    var attemptCount: Int = 0
    var lastAttemptAt: Date?
    var lastError: String?

    init(recordType: String, recordName: String, operation: String, payloadData: Data) {
        self.recordType = recordType
        self.recordName = recordName
        self.operation = operation
        self.payloadData = payloadData
        self.enqueuedAt = .now
    }
}

extension PendingPush {
    private static let logger = Logger(subsystem: "it.a11y.BlindensportGraz", category: "PendingPush")

    /// Inserts a pending write, or folds it into the existing row for the
    /// same `recordName` — the latest intent wins, so a save superseded by a
    /// later save just updates the payload, and a delete supersedes any
    /// pending save (and clears its now-useless payload). Either way the
    /// attempt counter resets, since this is a fresh user action.
    ///
    /// Returns the row's new `enqueuedAt`, which identifies this version of
    /// the write: a later enqueue for the same record always gets a later
    /// stamp, so a send can tell whether its write is still the latest
    /// (`isCurrent`) and clear only its own version (`clear(…, enqueuedAt:)`).
    ///
    /// Pure w.r.t. the network (takes only a `ModelContext`), so it's unit-
    /// testable without touching the network — see `PendingPushTests`.
    @discardableResult
    static func enqueue(in context: ModelContext, operation: String, recordType: String,
                        recordName: String, payload: Data) -> Date {
        let stamp: Date
        if let existing = row(recordName: recordName, recordType: recordType, in: context) {
            stamp = nextStamp(after: existing.enqueuedAt)
            existing.operation = operation
            existing.recordType = recordType
            existing.payloadData = operation == deleteOperation ? Data() : payload
            existing.enqueuedAt = stamp
            existing.attemptCount = 0
            existing.lastError = nil
        } else {
            let pending = PendingPush(recordType: recordType, recordName: recordName,
                                      operation: operation,
                                      payloadData: operation == deleteOperation ? Data() : payload)
            stamp = pending.enqueuedAt
            context.insert(pending)
        }
        try? context.save()
        return stamp
    }

    /// `Date.now`, or just after `previous` when the clock hasn't moved past
    /// it, so two quick edits never share a stamp.
    static func nextStamp(after previous: Date, now: Date = .now) -> Date {
        now > previous ? now : previous.addingTimeInterval(0.001)
    }

    /// Removes the pending row for `recordName` once the server has confirmed
    /// (or refused) the write. With `enqueuedAt`, only if the row is still
    /// that version — a newer edit queued meanwhile stays queued. No-op if
    /// the row was already removed.
    static func clear(recordName: String, recordType: String, enqueuedAt: Date? = nil,
                      in context: ModelContext) {
        guard let row = row(recordName: recordName, recordType: recordType, in: context) else { return }
        if let enqueuedAt, row.enqueuedAt != enqueuedAt { return }
        context.delete(row)
        try? context.save()
    }

    /// True while the queued write for this record is still the version
    /// stamped `enqueuedAt` (not superseded by a newer edit, not cleared).
    static func isCurrent(recordName: String, recordType: String, enqueuedAt: Date,
                          in context: ModelContext) -> Bool {
        row(recordName: recordName, recordType: recordType, in: context)?.enqueuedAt == enqueuedAt
    }

    private static func row(recordName: String, recordType: String, in context: ModelContext) -> PendingPush? {
        var descriptor = FetchDescriptor<PendingPush>(
            predicate: #Predicate { $0.recordName == recordName && $0.recordType == recordType }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    static func count(in context: ModelContext) -> Int {
        (try? context.fetchCount(FetchDescriptor<PendingPush>())) ?? 0
    }

    static func all(in context: ModelContext) -> [PendingPush] {
        (try? context.fetch(FetchDescriptor<PendingPush>(
            sortBy: [SortDescriptor(\.enqueuedAt)]
        ))) ?? []
    }
}
