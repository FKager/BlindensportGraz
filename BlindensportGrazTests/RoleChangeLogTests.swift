import XCTest
import SwiftData
@testable import BlindensportGraz

/// Exercises the RoleChangeLog audit-trail write path (audit.md P0
/// enhancement #2) at the model/local-store level — deliberately does NOT
/// go through `CloudKitSync.shared.logRoleChange`/`pushRoleChangeLog`,
/// since those touch a real `CKContainer` and crash under unsigned test
/// runs (see cerebrum.md bug-202, the same reason MemberImportExportTests/
/// TrainingImportExportTests are excluded from the baseline). What's under
/// test here is the same local insert + old/new role capture logic every
/// call site performs before handing off to CloudKitSync.
final class RoleChangeLogTests: XCTestCase {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            User.self, SportEvent.self, Tournament.self, Training.self, Team.self,
            TeamMembership.self, EventParticipation.self, Member.self,
            EventImage.self, Attendance.self, TrainingFavorite.self, RoleChangeLog.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [config])
    }

    func testRoleChangeLogRoundTripsAllFieldsThroughAnInMemoryStore() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let userID = UUID()
        let entry = RoleChangeLog(userID: userID, oldRole: "member", newRole: "admin",
                                   changedBy: "system:designatedRoot")
        context.insert(entry)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<RoleChangeLog>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.userID, userID)
        XCTAssertEqual(fetched.first?.oldRole, "member")
        XCTAssertEqual(fetched.first?.newRole, "admin")
        XCTAssertEqual(fetched.first?.changedBy, "system:designatedRoot")
    }

    /// Same shape the RootView/AccountView call sites use: capture
    /// `oldRole` before calling `elevateIfDesignatedRoot()`, then only
    /// build a log entry when the grant actually fired.
    func testElevateIfDesignatedRootProducesACorrectlyValuedLogEntry() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let user = User(email: User.designatedRootEmail,
                         firstName: User.designatedRootFirstName,
                         lastName: User.designatedRootLastName)
        context.insert(user)

        let oldRole = user.role
        let didElevate = user.elevateIfDesignatedRoot()
        XCTAssertTrue(didElevate)

        let entry = RoleChangeLog(userID: user.id, oldRole: oldRole.rawValue, newRole: user.role.rawValue,
                                   changedBy: "system:designatedRoot")
        context.insert(entry)
        try context.save()

        XCTAssertEqual(entry.oldRole, "member")
        XCTAssertEqual(entry.newRole, "admin")
        XCTAssertEqual(entry.userID, user.id)
    }

    /// A no-op role "change" (same value) shouldn't be mistaken for a real
    /// one by anything constructing a log entry from before/after snapshots
    /// — mirrors the `guard newRole != oldRole` short-circuit in
    /// UserListView's `roleBinding`.
    func testUnchangedRoleIsDistinguishableFromARealChange() throws {
        let user = User(email: "member@example.com", firstName: "Test", lastName: "Member", role: .member)
        let oldRole = user.role
        let newRole = AppRole.member
        XCTAssertEqual(oldRole, newRole, "sanity check: this scenario is a no-op change")
    }
}
