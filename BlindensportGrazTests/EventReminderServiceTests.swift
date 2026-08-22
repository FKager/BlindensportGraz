import XCTest
import UserNotifications
@testable import BlindensportGraz

/// Records calls instead of touching the real `UNUserNotificationCenter` —
/// this environment cannot reliably exercise it under an unsigned test host
/// (see EventReminderService.swift's doc comment), and the phase spec asks
/// for tests that "don't require a real device/notification to actually
/// fire" anyway.
final class FakeNotificationScheduling: NotificationScheduling {
    private(set) var calls: [String] = []
    private(set) var removedIdentifiers: [[String]] = []
    private(set) var addedRequests: [UNNotificationRequest] = []

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        calls.append("remove")
        removedIdentifiers.append(identifiers)
    }

    func add(_ request: UNNotificationRequest, withCompletionHandler completionHandler: (@Sendable (Error?) -> Void)?) {
        calls.append("add")
        addedRequests.append(request)
    }
}

final class EventReminderServiceTests: XCTestCase {

    private let referenceNow = ISO8601DateFormatter().date(from: "2026-08-22T10:00:00Z")!

    // MARK: - fireDate / buildRequest (pure computation)

    func testFireDateIsExactlyLeadTimeBeforeStartDate() {
        let start = referenceNow.addingTimeInterval(3 * 60 * 60) // 3h from now
        let fireDate = EventReminderService.fireDate(for: start, now: referenceNow)
        XCTAssertEqual(fireDate, start.addingTimeInterval(-EventReminderService.leadTime))
        XCTAssertEqual(fireDate, referenceNow.addingTimeInterval(60 * 60)) // 1h from now
    }

    func testFireDateIsNilWhenLeadTimeAdjustedDateIsInThePast() {
        // Starts in 1h — lead time (2h) pushes the fire date into the past.
        let start = referenceNow.addingTimeInterval(60 * 60)
        XCTAssertNil(EventReminderService.fireDate(for: start, now: referenceNow))
    }

    func testFireDateIsNilForAStartDateAlreadyInThePast() {
        let start = referenceNow.addingTimeInterval(-60 * 60)
        XCTAssertNil(EventReminderService.fireDate(for: start, now: referenceNow))
    }

    func testBuildRequestComputesExpectedTriggerDate() throws {
        let eventID = UUID()
        let start = referenceNow.addingTimeInterval(5 * 60 * 60) // 5h from now
        let request = EventReminderService.buildRequest(eventID: eventID, title: "Torball-Training",
                                                          sportLabel: "Torball", startDate: start, now: referenceNow)
        let request2 = try XCTUnwrap(request)
        XCTAssertEqual(request2.identifier, EventReminderService.identifier(for: eventID))
        let trigger = try XCTUnwrap(request2.trigger as? UNCalendarNotificationTrigger)
        let expectedFireDate = start.addingTimeInterval(-EventReminderService.leadTime)
        let expectedComponents = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second], from: expectedFireDate)
        XCTAssertEqual(trigger.dateComponents, expectedComponents)
    }

    func testBuildRequestReturnsNilWhenFireDateAlreadyPassed() {
        let start = referenceNow.addingTimeInterval(-60 * 60)
        let request = EventReminderService.buildRequest(eventID: UUID(), title: "x", sportLabel: "x",
                                                          startDate: start, now: referenceNow)
        XCTAssertNil(request)
    }

    // MARK: - reschedule / cancel (center interaction, via fake)

    func testRescheduleForFutureStartDateSchedulesExactlyOneRequest() {
        let center = FakeNotificationScheduling()
        let eventID = UUID()
        let start = referenceNow.addingTimeInterval(4 * 60 * 60)

        EventReminderService.reschedule(eventID: eventID, title: "Test", sportLabel: "Torball",
                                         startDate: start, now: referenceNow, center: center)

        XCTAssertEqual(center.addedRequests.count, 1)
        XCTAssertEqual(center.addedRequests[0].identifier, EventReminderService.identifier(for: eventID))
    }

    func testRescheduleRemovesOldRequestBeforeAddingNewOne() throws {
        let center = FakeNotificationScheduling()
        let eventID = UUID()
        let firstStart = referenceNow.addingTimeInterval(4 * 60 * 60)
        let secondStart = referenceNow.addingTimeInterval(8 * 60 * 60)

        EventReminderService.reschedule(eventID: eventID, title: "Test", sportLabel: "Torball",
                                         startDate: firstStart, now: referenceNow, center: center)
        EventReminderService.reschedule(eventID: eventID, title: "Test", sportLabel: "Torball",
                                         startDate: secondStart, now: referenceNow, center: center)

        // remove must happen before each add, and always target the same
        // deterministic identifier — no duplicate, no stale request left
        // pointing at the old time.
        XCTAssertEqual(center.calls, ["remove", "add", "remove", "add"])
        XCTAssertEqual(center.removedIdentifiers, [[EventReminderService.identifier(for: eventID)],
                                                    [EventReminderService.identifier(for: eventID)]])
        XCTAssertEqual(center.addedRequests.count, 2)
        let secondTrigger = try XCTUnwrap(center.addedRequests[1].trigger as? UNCalendarNotificationTrigger)
        let expectedComponents = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: secondStart.addingTimeInterval(-EventReminderService.leadTime))
        XCTAssertEqual(secondTrigger.dateComponents, expectedComponents)
    }

    func testRescheduleForPastStartDateRemovesOldButAddsNothing() {
        let center = FakeNotificationScheduling()
        let eventID = UUID()

        EventReminderService.reschedule(eventID: eventID, title: "Test", sportLabel: "Torball",
                                         startDate: referenceNow.addingTimeInterval(-60 * 60),
                                         now: referenceNow, center: center)

        XCTAssertEqual(center.calls, ["remove"])
        XCTAssertTrue(center.addedRequests.isEmpty)
    }

    func testCancelRemovesPendingRequestAndAddsNothing() {
        let center = FakeNotificationScheduling()
        let eventID = UUID()

        EventReminderService.cancel(eventID: eventID, center: center)

        XCTAssertEqual(center.calls, ["remove"])
        XCTAssertEqual(center.removedIdentifiers, [[EventReminderService.identifier(for: eventID)]])
        XCTAssertTrue(center.addedRequests.isEmpty)
    }
}
