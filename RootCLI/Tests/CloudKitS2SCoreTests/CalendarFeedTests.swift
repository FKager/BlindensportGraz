import XCTest
@testable import CloudKitS2SCore

/// Coverage for `CalendarFeed` (architecture-review.md §5 P2's webcal feed):
/// the visibility filter and the RFC 5545 renderer — pure Foundation, no
/// network/Vapor/CloudKit involved.
final class CalendarFeedTests: XCTestCase {

    private func event(_ uid: String, title: String = "T", teamIDs: [String] = [],
                       start: Date = Date(timeIntervalSince1970: 1_700_000_000)) -> CalendarFeed.EventFields {
        CalendarFeed.EventFields(uid: uid, title: title, location: "Graz",
                                 startDate: start, endDate: start.addingTimeInterval(3600), teamIDs: teamIDs)
    }

    // MARK: - visibleEvents

    func testAdminSeesEveryEventRegardlessOfTeamScoping() {
        let events = [event("a", teamIDs: []), event("b", teamIDs: ["team-x"])]
        let visible = CalendarFeed.visibleEvents(events, role: "admin", userTeamIDs: [])
        XCTAssertEqual(visible.map(\.uid), ["a", "b"])
    }

    func testMemberSeesUnscopedAndOwnTeamEventsOnly() {
        let unscoped = event("unscoped", teamIDs: [])
        let ownTeam = event("own", teamIDs: ["team-x", "team-y"])
        let otherTeam = event("other", teamIDs: ["team-z"])
        let visible = CalendarFeed.visibleEvents([unscoped, ownTeam, otherTeam], role: "member", userTeamIDs: ["team-x"])
        XCTAssertEqual(Set(visible.map(\.uid)), ["unscoped", "own"])
    }

    func testMemberWithNoTeamsOnlySeesUnscopedEvents() {
        let unscoped = event("unscoped", teamIDs: [])
        let scoped = event("scoped", teamIDs: ["team-x"])
        let visible = CalendarFeed.visibleEvents([unscoped, scoped], role: "member", userTeamIDs: [])
        XCTAssertEqual(visible.map(\.uid), ["unscoped"])
    }

    // MARK: - render

    func testRenderProducesOneVEventPerEventSortedByStartDate() {
        let later = event("later", title: "Später", start: Date(timeIntervalSince1970: 2_000_000_000))
        let earlier = event("earlier", title: "Früher", start: Date(timeIntervalSince1970: 1_000_000_000))
        let ics = CalendarFeed.render([later, earlier])

        XCTAssertTrue(ics.hasPrefix("BEGIN:VCALENDAR\r\n"))
        XCTAssertTrue(ics.hasSuffix("END:VCALENDAR\r\n"))
        XCTAssertEqual(ics.components(separatedBy: "BEGIN:VEVENT").count - 1, 2)
        // "Früher" (earlier start) must appear before "Später" in the output.
        let earlierRange = try! XCTUnwrap(ics.range(of: "SUMMARY:Früher"))
        let laterRange = try! XCTUnwrap(ics.range(of: "SUMMARY:Später"))
        XCTAssertLessThan(earlierRange.lowerBound, laterRange.lowerBound)
    }

    func testRenderEscapesCommasSemicolonsAndBackslashesInTextFields() {
        let e = event("x", title: "Turnier; Graz, \\Test")
        let ics = CalendarFeed.render([e])
        XCTAssertTrue(ics.contains("SUMMARY:Turnier\\; Graz\\, \\\\Test"))
    }

    func testRenderOfNoEventsIsStillAValidEmptyCalendar() {
        let ics = CalendarFeed.render([])
        XCTAssertTrue(ics.contains("BEGIN:VCALENDAR"))
        XCTAssertTrue(ics.contains("END:VCALENDAR"))
        XCTAssertFalse(ics.contains("BEGIN:VEVENT"))
    }
}
