import XCTest
@testable import BlindensportGraz

/// Local mirror of the server rule: full app only for admins, root and
/// accounts an admin approved for a Benutzerverwaltung entry (approvals are
/// written only by Supabase RPCs, so every mirrored row is trusted). A matching name or email alone must NOT grant
/// access — registration verifies neither.
@MainActor
final class AccessPolicyTests: XCTestCase {
    private let admin = User(email: "vorstand@example.at", firstName: "Vera", lastName: "Vorstand", role: .admin)
    private let member = Member(firstName: "Anna", lastName: "Muster", email: "anna@example.at")

    private func user(first: String = "Anna", last: String = "Muster", email: String = "anna@example.at",
                      role: AppRole = .member) -> User {
        User(email: email, firstName: first, lastName: last, role: role)
    }

    // MARK: Path 1 — name/email matches are not enough

    func testMatchingNameAloneGivesNoAccess() {
        let spoofer = user(email: "someone-else@example.at")
        XCTAssertFalse(AccessPolicy.hasFullAccess(spoofer, roster: [member], approvals: [], users: [admin, spoofer]))
        XCTAssertNil(AccessPolicy.approvedMember(for: spoofer, roster: [member], approvals: [], users: [admin, spoofer]))
    }

    func testMatchingEmailAloneGivesNoAccess() {
        let account = user()
        XCTAssertFalse(AccessPolicy.hasFullAccess(account, roster: [member], approvals: [], users: [admin, account]))
    }

    func testAdminApprovalGivesAccessAndLinksMember() {
        let account = user()
        let approval = AccountApproval(userID: account.id, memberID: member.id, approvedBy: admin.id.uuidString)
        XCTAssertTrue(AccessPolicy.hasFullAccess(account, roster: [member], approvals: [approval], users: [admin, account]))
        XCTAssertEqual(AccessPolicy.approvedMember(for: account, roster: [member], approvals: [approval],
                                                   users: [admin, account])?.id, member.id)
    }

    func testApprovalForDeletedRosterEntryGivesNoAccess() {
        let account = user()
        let approval = AccountApproval(userID: account.id, memberID: member.id, approvedBy: admin.id.uuidString)
        XCTAssertFalse(AccessPolicy.hasFullAccess(account, roster: [], approvals: [approval], users: [admin, account]))
    }

    func testAdminAndRootAlwaysHaveFullAccess() {
        XCTAssertTrue(AccessPolicy.hasFullAccess(admin, roster: [], approvals: [], users: [admin]))
        let root = User(email: "root@example.at", firstName: "R", lastName: "Oot", role: .root)
        XCTAssertTrue(AccessPolicy.hasFullAccess(root, roster: [], approvals: [], users: [root]))
    }

    // MARK: Suggestions for admins

    func testSuggestionPrefersEmailThenName() {
        let byEmail = AccessPolicy.suggestedMember(for: user(first: "X", last: "Y", email: "ANNA@example.at"), roster: [member])
        XCTAssertEqual(byEmail?.member.id, member.id)
        XCTAssertEqual(byEmail?.byEmail, true)
        let byName = AccessPolicy.suggestedMember(for: user(email: "other@example.at"), roster: [member])
        XCTAssertEqual(byName?.byEmail, false)
    }

    // MARK: Unique emails (login + club root account)

    func testEmailTakenIsCaseInsensitiveAndIgnoresSelf() {
        let account = user()
        XCTAssertTrue(AccessPolicy.isEmailTaken(" Anna@Example.at ", by: [account]))
        XCTAssertFalse(AccessPolicy.isEmailTaken("anna@example.at", by: [account], except: account))
        XCTAssertFalse(AccessPolicy.isEmailTaken("new@example.at", by: [account]))
    }

    // MARK: Activation codes (generated/checked server-side)

    func testActivationCodeNormalisation() {
        XCTAssertEqual(ActivationCode.normalized(" abcd-efgh "), "ABCDEFGH")
    }
}
