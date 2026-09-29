import XCTest
import SwiftData
@testable import BlindensportGraz

/// Roles come from root-owned `RoleAssignment` records: the latest trusted one
/// wins, untrusted ones are ignored, and accounts without one keep the role
/// stored in their own record.
@MainActor
final class RoleAssignmentResolverTests: XCTestCase {
    private let root = User(email: "root@example.at", firstName: "Ro", lastName: "Ot", isRoot: true)
    private let anna = User(email: "anna@example.at", firstName: "Anna", lastName: "Muster")

    func testLatestTrustedAssignmentWins() {
        let older = RoleAssignment(userID: anna.id, role: "coach", assignedBy: root.id.uuidString,
                                   assignedAt: Date(timeIntervalSince1970: 1_000))
        let newer = RoleAssignment(userID: anna.id, role: "admin", assignedBy: root.id.uuidString,
                                   assignedAt: Date(timeIntervalSince1970: 2_000))
        XCTAssertEqual(RoleAssignmentResolver.effectiveRole(for: anna, assignments: [newer, older], users: [root, anna]), .admin)
    }

    func testAssignmentByNonRootIsIgnored() {
        let selfPromotion = RoleAssignment(userID: anna.id, role: "admin", assignedBy: anna.id.uuidString)
        XCTAssertNil(RoleAssignmentResolver.effectiveRole(for: anna, assignments: [selfPromotion], users: [root, anna]))
    }

    func testRootCLIAssignmentIsTrusted() {
        let cli = RoleAssignment(userID: anna.id, role: "coach", assignedBy: RoleAssignmentResolver.rootCLIAssigner)
        XCTAssertEqual(RoleAssignmentResolver.effectiveRole(for: anna, assignments: [cli], users: [anna]), .coach)
    }

    func testApplyUpdatesLocalRolesAndKeepsOthers() throws {
        let container = try ModelContainer(for: AppModelSchema.schema,
                                           configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let context = container.mainContext
        let bernd = User(email: "bernd@example.at", firstName: "Bernd", lastName: "B", role: .coach)
        context.insert(root)
        context.insert(anna)
        context.insert(bernd)
        context.insert(RoleAssignment(userID: anna.id, role: "admin", assignedBy: root.id.uuidString))
        RoleAssignmentResolver.apply(in: context)
        XCTAssertEqual(anna.role, .admin)
        XCTAssertEqual(bernd.role, .coach)
    }
}
