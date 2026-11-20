import XCTest
@testable import BlindensportGraz

/// Sends for one record must reach the server in the order they were made;
/// sends for different records must not wait for each other.
@MainActor
final class RecordPushQueueTests: XCTestCase {

    func testOperationsForTheSameRecordRunInOrderEvenWhenTheFirstIsSlow() async {
        let queue = RecordPushQueue()
        var log: [String] = []

        queue.enqueue(key: "teams/A") {
            try? await Task.sleep(for: .milliseconds(200))
            log.append("first")
        }
        let second = queue.enqueue(key: "teams/A") { log.append("second") }
        await second.value

        XCTAssertEqual(log, ["first", "second"])
    }

    func testDifferentRecordsDoNotWaitForEachOther() async {
        let queue = RecordPushQueue()
        var log: [String] = []

        let slow = queue.enqueue(key: "teams/A") {
            try? await Task.sleep(for: .milliseconds(300))
            log.append("A")
        }
        let fast = queue.enqueue(key: "teams/B") { log.append("B") }
        await fast.value
        XCTAssertEqual(log, ["B"], "B must not wait for A")
        await slow.value
        XCTAssertEqual(log, ["B", "A"])
    }

    func testIsBusyUntilTheLastOperationForTheRecordFinishes() async throws {
        let queue = RecordPushQueue()
        XCTAssertFalse(queue.isBusy("teams/A"))

        queue.enqueue(key: "teams/A") { try? await Task.sleep(for: .milliseconds(100)) }
        let last = queue.enqueue(key: "teams/A") {}
        XCTAssertTrue(queue.isBusy("teams/A"))
        XCTAssertFalse(queue.isBusy("teams/B"))

        await last.value
        // The bookkeeping task runs right after; give it a turn.
        for _ in 0..<10 where queue.isBusy("teams/A") { await Task.yield() }
        XCTAssertFalse(queue.isBusy("teams/A"))
    }
}
