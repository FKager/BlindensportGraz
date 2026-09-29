import XCTest
@testable import BlindensportGraz

/// Full app only for admins, root and accounts an admin approved for a
/// Benutzerverwaltung entry. A matching name or email alone must NOT grant
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

    func testApprovalByNonAdminIsIgnored() {
        let account = user()
        let approval = AccountApproval(userID: account.id, memberID: member.id, approvedBy: account.id.uuidString)
        XCTAssertFalse(AccessPolicy.hasFullAccess(account, roster: [member], approvals: [approval], users: [admin, account]))
    }

    func testApprovalForDeletedRosterEntryGivesNoAccess() {
        let account = user()
        let approval = AccountApproval(userID: account.id, memberID: member.id, approvedBy: admin.id.uuidString)
        XCTAssertFalse(AccessPolicy.hasFullAccess(account, roster: [], approvals: [approval], users: [admin, account]))
    }

    func testAdminAndRootAlwaysHaveFullAccess() {
        XCTAssertTrue(AccessPolicy.hasFullAccess(admin, roster: [], approvals: [], users: [admin]))
        let root = User(email: "root@example.at", firstName: "R", lastName: "Oot", isRoot: true)
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

    // MARK: Path 2 — activation codes

    func testActivationCodeFormatAndNormalisation() {
        let code = ActivationCode.generate()
        XCTAssertEqual(code.count, 9)
        XCTAssertEqual(Array(code)[4], "-")
        XCTAssertEqual(ActivationCode.normalized(" abcd-efgh "), "ABCDEFGH")
    }

    func testActivationCodeMatchesOnlyTheIssuedCodeFromAnAdmin() {
        let account = user()
        let code = ActivationCode.generate()
        let salt = PasswordHashing.makeSalt()
        let hash = PasswordHashing.hash(password: ActivationCode.normalized(code), salt: salt)
        let byAdmin = AccountApproval(userID: account.id, memberID: nil, approvedBy: admin.id.uuidString,
                                      activationCodeHash: hash, activationCodeSalt: salt)
        XCTAssertTrue(ActivationCode.matches(code.lowercased(), for: account, approvals: [byAdmin], users: [admin, account]))
        XCTAssertFalse(ActivationCode.matches("AAAA-BBBB", for: account, approvals: [byAdmin], users: [admin, account]))

        let selfIssued = AccountApproval(userID: account.id, memberID: nil, approvedBy: account.id.uuidString,
                                         activationCodeHash: hash, activationCodeSalt: salt)
        XCTAssertFalse(ActivationCode.matches(code, for: account, approvals: [selfIssued], users: [admin, account]))

        let otherAccount = user(email: "other@example.at")
        XCTAssertFalse(ActivationCode.matches(code, for: otherAccount, approvals: [byAdmin], users: [admin, otherAccount]))
    }
}
