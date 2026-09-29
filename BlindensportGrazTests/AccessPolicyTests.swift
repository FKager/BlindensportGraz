import XCTest
@testable import BlindensportGraz

/// Full app only for admins, root and accounts listed in the
/// Benutzerverwaltung; everyone else gets the schedule-only view.
@MainActor
final class AccessPolicyTests: XCTestCase {
    private func user(first: String = "Anna", last: String = "Muster", email: String = "anna@example.at",
                      role: AppRole = .member) -> User {
        User(email: email, firstName: first, lastName: last, role: role)
    }

    func testListedByEmailHasFullAccess() {
        let roster = [Member(firstName: "Andrea", lastName: "Anders", email: "ANNA@example.at")]
        XCTAssertTrue(AccessPolicy.hasFullAccess(user(), roster: roster))
    }

    func testListedByNameHasFullAccess() {
        let roster = [Member(firstName: "anna", lastName: "muster")]
        XCTAssertTrue(AccessPolicy.hasFullAccess(user(email: ""), roster: roster))
    }

    func testNotListedIsRestricted() {
        let roster = [Member(firstName: "Berta", lastName: "Beispiel", email: "berta@example.at")]
        XCTAssertFalse(AccessPolicy.hasFullAccess(user(), roster: roster))
        XCTAssertFalse(AccessPolicy.hasFullAccess(user(role: .coach), roster: roster))
    }

    func testAdminAlwaysHasFullAccess() {
        XCTAssertTrue(AccessPolicy.hasFullAccess(user(role: .admin), roster: []))
    }
}
