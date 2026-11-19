import XCTest
import Supabase
@testable import BlindensportGraz

/// Sports and event types as club lists (migration 20261119000001):
/// picker options, the event's type name, and the event row's new
/// `event_type` field.
@MainActor
final class CatalogTests: XCTestCase {

    // MARK: - Picker options

    func testWithoutSyncedListsThePickersOfferTheBuiltInDefaults() {
        XCTAssertEqual(CatalogOptions.sportNames(from: []), ClubSport.defaultNames)
        XCTAssertEqual(CatalogOptions.eventTypeNames(from: [], behavior: .training), ["Training"])
        XCTAssertTrue(CatalogOptions.eventTypeNames(from: [], behavior: .event).contains("Langlaufkurs"))
    }

    func testSportsAreOfferedActiveOnlyInTheirOrder() {
        let sports = [
            ClubSport(name: "Schwimmen", sortOrder: 20),
            ClubSport(name: "Torball", sortOrder: 10),
            ClubSport(name: "Ski", isActive: false, sortOrder: 5),
            ClubSport(name: "Goalball", sortOrder: 20)
        ]
        XCTAssertEqual(CatalogOptions.sportNames(from: sports), ["Torball", "Goalball", "Schwimmen"])
    }

    func testEventTypesAreFilteredByBehaviour() {
        let types = [
            EventType(name: "Training", behavior: "training", sortOrder: 10),
            EventType(name: "Trainingslager", behavior: "training", sortOrder: 15),
            EventType(name: "Turnier", behavior: "tournament", sortOrder: 20),
            EventType(name: "Kurs", behavior: "event", sortOrder: 30),
            EventType(name: "Alt", behavior: "event", isActive: false, sortOrder: 40)
        ]
        XCTAssertEqual(CatalogOptions.eventTypeNames(from: types, behavior: .training), ["Training", "Trainingslager"])
        XCTAssertEqual(CatalogOptions.eventTypeNames(from: types, behavior: .event), ["Kurs"])
    }

    func testAStoredValueThatIsNoLongerOfferedStaysSelectable() {
        XCTAssertEqual(CatalogOptions.including("Ski", in: ["Torball"]), ["Torball", "Ski"])
        XCTAssertEqual(CatalogOptions.including("Torball", in: ["Torball"]), ["Torball"])
        XCTAssertEqual(CatalogOptions.including("", in: ["Torball"]), ["Torball"])
    }

    func testNamesAreCleanedBeforeSaving() {
        XCTAssertEqual(CatalogService.clean("  Tisch   tennis "), "Tisch tennis")
        XCTAssertEqual(CatalogService.nextSortOrder(after: []), 10)
        XCTAssertEqual(CatalogService.nextSortOrder(after: [10, 90, 95]), 100)
    }

    // MARK: - Event type name

    func testTypeNameFallsBackToTheKindsDefaultAndToOlderPlainEvents() {
        let training = Training(title: "T", sport: "Torball", location: "", startDate: .now)
        XCTAssertEqual(training.typeName, "Training")
        training.eventType = "Trainingslager"
        XCTAssertEqual(training.typeName, "Trainingslager")

        let oldEvent = SportEvent(title: "Kurs", sport: "Langlaufkurs", location: "", startDate: .now, endDate: .now)
        XCTAssertEqual(oldEvent.typeName, "Langlaufkurs", "the old picker stored the type in sport")
        oldEvent.eventType = "Kurs"
        oldEvent.sport = "Ski"
        XCTAssertEqual(oldEvent.typeName, "Kurs")
    }

    // MARK: - Event row

    private func json<Row: Encodable>(_ row: Row) throws -> [String: Any] {
        let data = try PostgrestClient.Configuration.jsonEncoder.encode(row)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testEventRowSendsTheTypeOnlyWhenSet() throws {
        let training = Training(title: "T", sport: "Torball", location: "", startDate: .now)
        XCTAssertNil(try json(EventDBRow(training))["event_type"], "empty: the server fills in the default")
        training.eventType = "Trainingslager"
        XCTAssertEqual(try json(EventDBRow(training))["event_type"] as? String, "Trainingslager")
    }

    func testEventRowDecodesWithAndWithoutTheTypeColumn() throws {
        let training = Training(title: "T", sport: "Torball", location: "", startDate: .now)
        training.eventType = "Trainingslager"
        var object = try json(EventDBRow(training))
        object["updated_at"] = "2026-11-19T10:00:00Z"
        let decoder = PostgrestClient.Configuration.jsonDecoder

        let withType = try decoder.decode(EventDBRow.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(withType.eventType, "Trainingslager")
        XCTAssertNotNil(withType.updatedAt)

        object.removeValue(forKey: "event_type")
        let withoutType = try decoder.decode(EventDBRow.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(withoutType.eventType, "", "a server before the migration has no event_type column")
        XCTAssertEqual(withoutType.title, "T")
    }

    func testCatalogRowsUseTheServerColumnNames() throws {
        let object = try json(EventTypeDBRow(id: UUID(), name: "Kurs", behavior: "event", isActive: true, sortOrder: 30))
        XCTAssertEqual(object["behavior"] as? String, "event")
        XCTAssertEqual(object["is_active"] as? Bool, true)
        XCTAssertEqual(object["sort_order"] as? Int, 30)
        XCTAssertNil(object["updated_at"], "set by the server")
    }
}
