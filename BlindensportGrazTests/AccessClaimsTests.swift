import XCTest
@testable import BlindensportGraz

/// Decoding of the `custom_access_token_hook` claims and the offline
/// permission fallback (must match role_permissions in
/// supabase/migrations/20261008000001_rbac.sql).
@MainActor
final class AccessClaimsTests: XCTestCase {

    private func jwt(_ payload: [String: Any]) -> String {
        let data = try! JSONSerialization.data(withJSONObject: payload)
        let body = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "eyJhbGciOiJIUzI1NiJ9.\(body).signature"
    }

    override func tearDown() async throws {
        Permission.serverTable = [:]
    }

    func testDecodesRoleAndApproval() throws {
        let id = UUID()
        let claims = try XCTUnwrap(AccessClaims.decode(jwt: jwt(
            ["sub": id.uuidString, "email": "a@b.at", "user_role": "coach", "approved": true])))
        XCTAssertEqual(claims.userID, id)
        XCTAssertEqual(claims.role, .coach)
        XCTAssertTrue(claims.approved)
        XCTAssertEqual(claims.email, "a@b.at")
    }

    func testPendingAccountHasNoRoleAndIsNotApproved() throws {
        let claims = try XCTUnwrap(AccessClaims.decode(jwt: jwt(
            ["sub": UUID().uuidString, "user_role": NSNull(), "approved": false])))
        XCTAssertNil(claims.role)
        XCTAssertFalse(claims.approved)
    }

    func testMissingClaimsDefaultToLeastPrivilege() throws {
        let claims = try XCTUnwrap(AccessClaims.decode(jwt: jwt(["sub": UUID().uuidString])))
        XCTAssertNil(claims.role)
        XCTAssertFalse(claims.approved)
    }

    func testRejectsMalformedTokens() {
        XCTAssertNil(AccessClaims.decode(jwt: "not-a-jwt"))
        XCTAssertNil(AccessClaims.decode(jwt: jwt(["sub": "not-a-uuid"])))
    }

    func testUnknownRoleGrantsNothing() throws {
        let claims = try XCTUnwrap(AccessClaims.decode(jwt: jwt(
            ["sub": UUID().uuidString, "user_role": "superuser"])))
        XCTAssertEqual(claims.role, .other("superuser"))
        XCTAssertTrue(Permission.granted(to: claims.role).isEmpty)
    }

    func testDefaultPermissionsPerRole() {
        XCTAssertTrue(Permission.defaults(for: .member).isEmpty)
        XCTAssertTrue(Permission.defaults(for: nil).isEmpty)
        XCTAssertEqual(Permission.defaults(for: .coach), [.eventsManage, .teamsManage])
        XCTAssertFalse(Permission.defaults(for: .admin).contains(.rolesAssign))
        XCTAssertTrue(Permission.defaults(for: .admin).contains(.membersPrivateRead))
        XCTAssertEqual(Permission.defaults(for: .root),
                       Permission.defaults(for: .admin).union([.rolesAssign]))
    }

    func testServerTableOverridesDefaults() {
        Permission.serverTable = [.coach: [.eventsManage]]
        let coach = User(email: "c@b.at", firstName: "C", lastName: "Oach", role: .coach)
        XCTAssertTrue(coach.can(.eventsManage))
        XCTAssertFalse(coach.can(.teamsManage))
        // Roles missing from the server table fall back to the defaults.
        let admin = User(email: "a@b.at", firstName: "A", lastName: "Dmin", role: .admin)
        XCTAssertTrue(admin.can(.usersApprove))
    }

    func testRootRoleRoundTrips() {
        XCTAssertEqual(AppRole.normalize("root"), .root)
        XCTAssertEqual(AppRole.root.rawValue, "root")
    }
}
