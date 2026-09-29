import Foundation
import Network
import Observation

/// Abstraction over "is the network reachable" — audit.md Enhancement #4
/// (offline-mode messaging). A protocol, not a direct `NWPathMonitor`
/// dependency, specifically so tests can simulate offline/online
/// transitions without needing a real network change (see
/// `FakeReachabilitySource` in `NetworkMonitorTests.swift`).
protocol ReachabilitySource {
    /// Starts observing reachability, calling `onChange` with the current
    /// state immediately and again on every subsequent change.
    func start(onChange: @escaping (Bool) -> Void)
}

/// Real implementation, backed by `NWPathMonitor`.
final class NWPathReachabilitySource: ReachabilitySource {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "it.a11y.BlindensportGraz.NWPathReachabilitySource")

    func start(onChange: @escaping (Bool) -> Void) {
        monitor.pathUpdateHandler = { path in
            onChange(path.status == .satisfied)
        }
        monitor.start(queue: queue)
    }
}

/// App-wide reachability state — audit.md Enhancement #4. `@Observable`
/// singleton, same shape as `SyncState`/`ServiceFailureSignal`.
///
/// `isOnline` starts `true` (optimistic default): showing a false "offline"
/// banner for the brief moment before `NWPathMonitor` reports its first
/// real reading would be a worse experience than a brief false negative on
/// the opposite side, and every push/pull already has its own retry+failure
/// handling (Phase 6) regardless of what this banner shows.
@Observable
final class NetworkMonitor {
    static let shared = NetworkMonitor()

    private(set) var isOnline = true
    private let source: ReachabilitySource

    /// Internal `init` (not `private`) so tests can construct their own
    /// instance with a `FakeReachabilitySource` instead of driving the real
    /// `NetworkMonitor.shared` singleton.
    init(source: ReachabilitySource = NWPathReachabilitySource()) {
        self.source = source
    }

    func start() {
        source.start { [weak self] online in
            Task { @MainActor in
                self?.isOnline = online
            }
        }
    }
}
