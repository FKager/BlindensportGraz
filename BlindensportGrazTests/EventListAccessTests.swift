import XCTest
import SwiftData
@testable import BlindensportGraz

/// The Events, Trainings and Tournaments lists: who sees which event, who may
/// delete or cancel, and which event a swipe-to-delete removes.
@MainActor
final class EventListAccessTests: XCTestCase {
    private var savedServerTable: [AppRole: Set<Permission>] = [:]

    override func setUp() async throws {
        savedServerTable = Permission.serverTable
        Permission.serverTable = [:] // built-in defaults: coach/admin manage events, members don't
    }

    override func tearDown() async throws {
        Permission.serverTable = savedServerTable
    }

    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(schema: AppModelSchema.schema, isStoredInMemoryOnly: true,
                                        cloudKitDatabase: .none)
        return ModelContext(try ModelContainer(for: AppModelSchema.schema, configurations: [config]))
    }

    private func event(_ title: String, teams: [Team] = [], in context: ModelContext) -> SportEvent {
        let event = SportEvent(title: title, sport: "Torball", location: "Graz",
                               startDate: .now, endDate: .now, teams: teams)
        context.insert(event)
        return event
    }

    /// Torball team event, Goalball team event, club-wide event; the user is
    /// on the Torball team only.
    private func fixture(role: AppRole) throws -> (user: User, events: [SportEvent]) {
        let context = try makeContext()
        let torball = Team(name: "Torball", sport: "Torball")
        let goalball = Team(name: "Goalball", sport: "Goalball")
        context.insert(torball)
        context.insert(goalball)
        let user = User(email: "anna@example.at", firstName: "Anna", lastName: "Muster", role: role)
        context.insert(user)
        context.insert(TeamMembership(user: user, team: torball))
        let events = [
            event("Goalball-Training", teams: [goalball], in: context),
            event("Torball-Turnier", teams: [torball], in: context),
            event("Vereinsfeier", in: context)
        ]
        try context.save()
        return (user, events)
    }

    // MARK: - visible

    func testMemberSeesOwnTeamAndClubWideEventsOnly() throws {
        let (user, events) = try fixture(role: .member)

        XCTAssertEqual(EventListAccess.visible(events, to: user).map(\.title), ["Torball-Turnier", "Vereinsfeier"])
    }

    func testClubManagerSeesEverythingInTheGivenOrder() throws {
        let (user, events) = try fixture(role: .admin)

        XCTAssertEqual(EventListAccess.visible(events, to: user).map(\.title),
                       ["Goalball-Training", "Torball-Turnier", "Vereinsfeier"])
    }

    func testSignedOutSeesClubWideEventsOnly() throws {
        let (_, events) = try fixture(role: .member)

        XCTAssertEqual(EventListAccess.visible(events, to: nil).map(\.title), ["Vereinsfeier"])
    }

    // MARK: - rows(at:in:)

    /// The Events list bug: the member's list hides the Goalball event, so
    /// swiping the first row ("Torball-Turnier") must delete that event, not
    /// the first event of the unfiltered query ("Goalball-Training").
    func testSwipeOffsetsResolveAgainstTheShownList() throws {
        let (user, events) = try fixture(role: .member)
        let shown = EventListAccess.visible(events, to: user)

        let removed = EventListAccess.rows(at: IndexSet(integer: 0), in: shown)

        XCTAssertEqual(removed.map(\.title), ["Torball-Turnier"])
    }

    func testOffsetsOutsideTheShownListAreIgnored() throws {
        let (_, events) = try fixture(role: .member)

        XCTAssertTrue(EventListAccess.rows(at: IndexSet(integer: 7), in: events).isEmpty)
    }

    // MARK: - canManage

    func testOnlyCoachesAndAdminsMayDeleteOrCancel() {
        func user(_ role: AppRole) -> User {
            User(email: "x@example.at", firstName: "X", lastName: "Y", role: role)
        }
        XCTAssertFalse(EventListAccess.canManage(nil))
        XCTAssertFalse(EventListAccess.canManage(user(.member)))
        XCTAssertTrue(EventListAccess.canManage(user(.coach)))
        XCTAssertTrue(EventListAccess.canManage(user(.admin)))
        XCTAssertTrue(EventListAccess.canManage(user(.root)))
    }

    func testServerPermissionTableDecides() {
        Permission.serverTable = [.member: [.eventsManage]]
        let member = User(email: "x@example.at", firstName: "X", lastName: "Y", role: .member)

        XCTAssertTrue(EventListAccess.canManage(member))
    }
}
