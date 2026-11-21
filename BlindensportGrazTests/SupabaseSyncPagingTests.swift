import XCTest
@testable import BlindensportGraz

/// `fetchChanged` pages by the last row read (`updated_at`, then `id`), not
/// by offset. With offsets, a row edited during a full pull moved to the end
/// and shifted the rest back, so one row was never read — and the full pull
/// then deleted it on the device. A fake PostgREST table, no network.
@MainActor
final class SupabaseSyncPagingTests: XCTestCase {
    private struct Row: Decodable, Equatable {
        let id: UUID
        let title: String
    }

    /// Rows as the server holds them; answers like `fetchChanged`'s query.
    private final class FakeTable {
        struct Stored { var id: UUID; var updatedAt: String; var title: String }
        var rows: [Stored]
        var requests: [SupabaseSync.PageKey?] = []
        /// Runs after the given page was served (0-based), e.g. to edit a row.
        var afterPage: [Int: (FakeTable) -> Void] = [:]

        init(count: Int, stamp: (Int) -> String) {
            rows = (0..<count).map { Stored(id: UUID(), updatedAt: stamp($0), title: "Zeile \($0)") }
        }

        private static func key(_ row: Stored) -> (String, String) { (row.updatedAt, row.id.uuidString.lowercased()) }

        func page(after: SupabaseSync.PageKey?, size: Int) throws -> Data {
            requests.append(after)
            let sorted = rows.sorted { Self.key($0) < Self.key($1) }
            let remaining = sorted.filter { row in
                guard let after else { return true }
                return Self.key(row) > (after.updatedAt, after.id.uuidString.lowercased())
            }
            let page = remaining.prefix(size).map { ["id": $0.id.uuidString.lowercased(), "updated_at": $0.updatedAt, "title": $0.title] }
            let data = try JSONSerialization.data(withJSONObject: Array(page))
            afterPage[requests.count - 1]?(self)
            return data
        }
    }

    private static func stamp(second: Int) -> String {
        String(format: "2026-11-21T10:%02d:%02d.123456+00:00", second / 60, second % 60)
    }

    private func collect(_ table: FakeTable, pageSize: Int) async throws -> [Row] {
        try await SupabaseSync.collectPages(pageSize: pageSize) { after in try table.page(after: after, size: pageSize) }
    }

    func testReadsEveryPageAndStopsAtAShortOne() async throws {
        let table = FakeTable(count: 7) { Self.stamp(second: $0) }

        let rows = try await collect(table, pageSize: 3)

        XCTAssertEqual(Set(rows.map(\.id)), Set(table.rows.map(\.id)))
        XCTAssertEqual(table.requests.count, 3)
        XCTAssertNil(table.requests[0], "the first page starts at the beginning")
    }

    func testARowEditedDuringThePullSkipsNothing() async throws {
        let table = FakeTable(count: 6) { Self.stamp(second: $0) }
        let original = table.rows.map(\.id)
        // After the first page, the first row is edited: it moves to the end.
        table.afterPage[0] = { table in
            table.rows[0].updatedAt = Self.stamp(second: 59)
            table.rows[0].title = "Zeile 0 (bearbeitet)"
        }

        let rows = try await collect(table, pageSize: 2)

        XCTAssertEqual(Set(rows.map(\.id)), Set(original), "no row may be skipped")
        XCTAssertEqual(rows.count, original.count, "a row read twice is kept once")
        XCTAssertEqual(rows.first { $0.id == original[0] }?.title, "Zeile 0 (bearbeitet)", "the newer copy wins")
    }

    /// One transaction stamps all its rows with the same `now()`; the id
    /// breaks the tie, so a page boundary inside such a batch loses nothing.
    func testRowsWithTheSameTimestampArePagedById() async throws {
        let table = FakeTable(count: 5) { _ in Self.stamp(second: 1) }

        let rows = try await collect(table, pageSize: 2)

        XCTAssertEqual(Set(rows.map(\.id)), Set(table.rows.map(\.id)))
        XCTAssertEqual(rows.count, 5)
    }

    func testAnEmptyTableNeedsOneRequest() async throws {
        let table = FakeTable(count: 0) { Self.stamp(second: $0) }

        let rows = try await collect(table, pageSize: 3)

        XCTAssertTrue(rows.isEmpty)
        XCTAssertEqual(table.requests.count, 1)
    }

    func testPageFilterKeepsTheServerTimestampExactly() {
        let id = UUID(uuidString: "9E3AC32B-E4C1-4FE7-93FB-0CA5BC63A27D")!
        let key = SupabaseSync.PageKey(id: id, updatedAt: "2026-11-21T10:00:00.123456+00:00")

        XCTAssertEqual(SupabaseSync.pageFilter(after: key),
                       #"updated_at.gt."2026-11-21T10:00:00.123456+00:00",and(updated_at.eq."2026-11-21T10:00:00.123456+00:00",id.gt.9e3ac32b-e4c1-4fe7-93fb-0ca5bc63a27d)"#)
    }
}
