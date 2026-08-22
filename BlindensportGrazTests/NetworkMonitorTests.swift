import XCTest
@testable import BlindensportGraz

/// A controllable `ReachabilitySource` for tests — lets a test flip
/// online/offline deterministically instead of needing a real network
/// change, per this phase's own acceptance criterion ("simulated via a
/// mockable/testable reachability abstraction").
final class FakeReachabilitySource: ReachabilitySource {
    private var onChange: ((Bool) -> Void)?
    private(set) var startCallCount = 0

    func start(onChange: @escaping (Bool) -> Void) {
        startCallCount += 1
        self.onChange = onChange
        onChange(true) // matches NWPathMonitor's real behavior: reports current state immediately
    }

    func simulate(online: Bool) {
        onChange?(online)
    }
}

@MainActor
final class NetworkMonitorTests: XCTestCase {

    func testStartReportsInitialStateImmediately() {
        let fake = FakeReachabilitySource()
        let monitor = NetworkMonitor(source: fake)

        monitor.start()

        XCTAssertEqual(fake.startCallCount, 1)
        XCTAssertTrue(monitor.isOnline)
    }

    /// The core of this phase's offline-UX requirement: going offline must
    /// be observable, and reconnecting must clear it — both through the
    /// same `isOnline` property `SyncStatusBanner` reads.
    func testGoingOfflineThenReconnectingUpdatesIsOnline() async {
        let fake = FakeReachabilitySource()
        let monitor = NetworkMonitor(source: fake)
        monitor.start()
        XCTAssertTrue(monitor.isOnline)

        fake.simulate(online: false)
        // The real callback hops to MainActor via Task { @MainActor in ... } —
        // yield once so that hop has a chance to run before asserting.
        await Task.yield()
        XCTAssertFalse(monitor.isOnline, "going offline must be reflected in isOnline")

        fake.simulate(online: true)
        await Task.yield()
        XCTAssertTrue(monitor.isOnline, "reconnecting must clear the offline state")
    }
}
