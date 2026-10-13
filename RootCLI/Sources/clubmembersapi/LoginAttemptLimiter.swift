import Foundation

/// In-memory sliding-window limiter for failed sign-ins on `clubmembersapi`
/// (audit.md Security Finding 9, `POST /api/session` in Auth.swift). Keyed
/// by client IP, not email, so guessing across many addresses is throttled
/// too (Supabase Auth adds its own per-project rate limits on top).
/// Deliberately a plain in-memory
/// actor with no database or external dependency — this is small internal
/// tooling, not a public API, and state resetting on process restart is an
/// acceptable tradeoff for a mechanism whose job is slowing down brute-force
/// guessing, not permanent banning.
actor LoginAttemptLimiter {
    private var failuresByClient: [String: [Date]] = [:]
    private let maxFailures: Int
    private let window: TimeInterval

    /// 5 failures per 5-minute sliding window per client IP.
    init(maxFailures: Int = 5, window: TimeInterval = 300) {
        self.maxFailures = maxFailures
        self.window = window
    }

    /// True if this client should be rejected with 429 without even
    /// checking credentials this time.
    func isLockedOut(client: String) -> Bool {
        prune(client: client)
        return (failuresByClient[client]?.count ?? 0) >= maxFailures
    }

    func recordFailure(client: String) {
        prune(client: client)
        failuresByClient[client, default: []].append(.now)
    }

    /// A successful login clears this client's failure history entirely —
    /// the point of a sliding window is to slow down guessing, not to keep
    /// punishing a client after they eventually authenticate correctly.
    func recordSuccess(client: String) {
        failuresByClient[client] = nil
    }

    private func prune(client: String) {
        let cutoff = Date.now.addingTimeInterval(-window)
        failuresByClient[client]?.removeAll { $0 < cutoff }
    }
}
