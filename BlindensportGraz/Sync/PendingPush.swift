import CloudKit
import Foundation
import SwiftData
import os

/// Durable outbox for CloudKit writes — architecture-review.md 2.2 / 2.3.
///
/// Before this, every `CloudKitSync.save`/`delete` was fire-and-forget: it
/// retried a few times over ~3.5s (`performWithRetry`) and, if the network
/// was still down, the write was simply lost — nothing recorded that it
/// hadn't reached CloudKit, and the `ModelContainer` reset fallback in
/// `BlindensportGrazApp` even admits it can't tell what synced.
///
/// Now every push/delete first writes a `PendingPush` row here; the row is
/// deleted only once CloudKit confirms the write. Rows that outlive their
/// inline retries are re-attempted by `CloudKitSync.drainOutbox()` (run at
/// the start of every `syncAll` and whenever the network comes back), and
/// their count drives the "N Änderungen noch nicht synchronisiert" banner.
///
/// This model is **local-only** — it is deliberately NOT in `CKSchema` and
/// never itself synced; it *is* the sync mechanism.
@Model
final class PendingPush {
    static let saveOperation = "save"
    static let deleteOperation = "delete"

    @Attribute(.unique) var id: UUID = UUID()
    /// The `CKRecord.recordType` (from `CKSchema`) — kept for deletes too, so
    /// `drainOutbox` doesn't need the archived record to issue the delete.
    var recordType: String = ""
    /// `CKRecord.ID.recordName` == the SwiftData model's `id.uuidString`. The
    /// dedupe key: at most one pending row per record.
    var recordName: String = ""
    /// `PendingPush.saveOperation` or `.deleteOperation`.
    var operation: String = PendingPush.saveOperation
    /// `NSKeyedArchiver`-encoded `CKRecord` for a save; empty for a delete.
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

    /// Archives a fully-built `CKRecord` for later replay. `CKRecord` is
    /// `NSSecureCoding`, so this round-trips every field it currently carries.
    static func archived(_ record: CKRecord) -> Data? {
        try? NSKeyedArchiver.archivedData(withRootObject: record, requiringSecureCoding: true)
    }

    /// The `CKRecord` to replay for a `save` row, or `nil` if the payload is
    /// missing/corrupt (a `nil` here means the row can never succeed — the
    /// caller drops it rather than retrying forever).
    func decodedRecord() -> CKRecord? {
        guard operation == Self.saveOperation, !payloadData.isEmpty else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKRecord.self, from: payloadData)
    }

    /// Inserts a pending write, or folds it into the existing row for the
    /// same `recordName` — the latest intent wins, so a save superseded by a
    /// later save just updates the payload, and a delete supersedes any
    /// pending save (and clears its now-useless payload). Either way the
    /// attempt counter resets, since this is a fresh user action.
    ///
    /// Pure w.r.t. CloudKit (takes only a `ModelContext`), so it's unit-
    /// testable without touching the network — see `PendingPushTests`.
    static func enqueue(in context: ModelContext, operation: String, recordType: String,
                        recordName: String, payload: Data) {
        let descriptor = FetchDescriptor<PendingPush>(
            predicate: #Predicate { $0.recordName == recordName }
        )
        if let existing = try? context.fetch(descriptor).first {
            existing.operation = operation
            existing.recordType = recordType
            existing.payloadData = operation == deleteOperation ? Data() : payload
            existing.enqueuedAt = .now
            existing.attemptCount = 0
            existing.lastError = nil
        } else {
            context.insert(PendingPush(recordType: recordType, recordName: recordName,
                                       operation: operation,
                                       payloadData: operation == deleteOperation ? Data() : payload))
        }
        try? context.save()
    }

    /// Removes the pending row for `recordName` once CloudKit has confirmed
    /// the write. No-op if it was already superseded/removed.
    static func clear(recordName: String, in context: ModelContext) {
        let descriptor = FetchDescriptor<PendingPush>(
            predicate: #Predicate { $0.recordName == recordName }
        )
        for row in (try? context.fetch(descriptor)) ?? [] {
            context.delete(row)
        }
        try? context.save()
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
