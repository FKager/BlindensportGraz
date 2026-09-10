import XCTest
import SwiftData
@testable import BlindensportGraz

/// Coverage for the app↔widget bridge (architecture-review.md §5):
/// `NextUpSnapshot` serialization, the `WidgetBridge` App-Group store, and
/// `WidgetRefresher`'s "which event is next" pick. `WidgetCenter` reloads
/// are a harmless no-op in the test process.
@MainActor
final class WidgetBridgeTests: XCTestCase {

    override func setUp() { super.setUp(); WidgetBridge.write(nil) }
    override func tearDown() { WidgetBridge.write(nil); super.tearDown() }

    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(schema: AppModelSchema.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return ModelContext(try ModelContainer(for: AppModelSchema.schema, configurations: [config]))
    }

    // Real "now" — WidgetRefresher.refresh uses NextEventLookup's default
    // `.now`, so the fixtures have to be genuinely past/future.
    private let now = Date.now

    // MARK: - NextUpSnapshot / WidgetBridge

    func testSnapshotSurvivesAWriteReadRoundTrip() {
        let snap = NextUpSnapshot(kind: .tournament, title: "Herbstcup",
                                  startDate: now, location: "Linz")
        WidgetBridge.write(snap)
        XCTAssertEqual(WidgetBridge.read(), snap)
    }

    func testWritingNilClearsTheStoredSnapshot() {
        WidgetBridge.write(NextUpSnapshot(kind: .training, title: "x", startDate: now, location: ""))
        WidgetBridge.write(nil)
        XCTAssertNil(WidgetBridge.read())
    }

    // MARK: - WidgetRefresher pick

    func testRefreshPicksTheSoonerOfTrainingAndTournament() throws {
        let context = try makeContext()
        context.insert(Training(title: "Bald", sport: "Torball", location: "Graz",
                                startDate: now.addingTimeInterval(3600)))
        context.insert(Tournament(title: "Später", sport: "Torball", location: "Wien",
                                  startDate: now.addingTimeInterval(5 * 86400), endDate: now.addingTimeInterval(6 * 86400)))
        try context.save()

        WidgetRefresher.refresh(modelContext: context, for: nil)

        let snap = try XCTUnwrap(WidgetBridge.read())
        XCTAssertEqual(snap.kind, .training)
        XCTAssertEqual(snap.title, "Bald")
    }

    func testRefreshFallsBackToTournamentWhenNoUpcomingTraining() throws {
        let context = try makeContext()
        context.insert(Tournament(title: "Nur Turnier", sport: "Torball", location: "Wien",
                                  startDate: now.addingTimeInterval(86400), endDate: now.addingTimeInterval(2 * 86400)))
        try context.save()

        WidgetRefresher.refresh(modelContext: context, for: nil)

        XCTAssertEqual(WidgetBridge.read()?.kind, .tournament)
    }

    func testRefreshClearsTheSnapshotWhenNothingIsUpcoming() throws {
        let context = try makeContext()
        context.insert(Training(title: "Vorbei", sport: "Torball", location: "Graz",
                                startDate: now.addingTimeInterval(-3600)))
        try context.save()
        WidgetBridge.write(NextUpSnapshot(kind: .training, title: "stale", startDate: now, location: ""))

        WidgetRefresher.refresh(modelContext: context, for: nil)

        XCTAssertNil(WidgetBridge.read(), "a stale snapshot must be cleared when there's nothing to show")
    }
}
