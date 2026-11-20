import Foundation

/// Runs the sends for one record one after another, so an older edit (or its
/// retry) can never reach the server after a newer one. Sends for different
/// records still run side by side.
///
/// Keyed by "table/id" (`SupabaseSync.outboxKey`). Holds no network code
/// itself, so it is unit-testable — see `RecordPushQueueTests`.
final class RecordPushQueue {
    private var tails: [String: Task<Void, Never>] = [:]

    /// Starts `operation` once every earlier operation for `key` has finished.
    @discardableResult
    func enqueue(key: String, _ operation: @escaping @MainActor () async -> Void) -> Task<Void, Never> {
        let previous = tails[key]
        let task = Task {
            await previous?.value
            await operation()
        }
        tails[key] = task
        Task {
            await task.value
            // Only the last operation queued for this key clears the entry.
            if tails[key] == task { tails[key] = nil }
        }
        return task
    }

    /// True while a send for `key` is queued or running — `drainOutbox`
    /// leaves such rows to it instead of sending them a second time.
    func isBusy(_ key: String) -> Bool { tails[key] != nil }
}
