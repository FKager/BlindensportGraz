import XCTest
import SwiftData
@testable import BlindensportGraz

/// Coverage for `User.elevateIfDesignatedRoot()` (audit.md Security Finding
/// 3) — this exact mechanism has a documented multi-session bug history
/// (bug-173: an earlier Apple-Sign-In-gated version could never fire for
/// the designated account, since that account has no real Apple ID and is
/// always created via RegisterView's manual form; cerebrum.md's
/// 2026-07-19/2026-08-02 entries). Each test below maps to a real failure
/// mode from that history or a documented edge case in the current
/// firstName+lastName+email match, not a generic happy-path check.
final class DesignatedRootTests: XCTestCase {

    // No ModelContainer needed for these tests — elevateIfDesignatedRoot()
    // only mutates the User instance's own scalar properties, which works
    // fine on a standalone (uninserted, unattached) @Model object.

    func testFullMatchGrantsRootAndAdmin() {
        let user = User(email: User.designatedRootEmail,
                         firstName: User.designatedRootFirstName,
                         lastName: User.designatedRootLastName)
        XCTAssertTrue(user.elevateIfDesignatedRoot())
        XCTAssertTrue(user.isRoot)
        XCTAssertEqual(user.role, .admin)
    }

    /// bug-173's actual root cause was structural (an Apple-Sign-In gate
    /// that could never be satisfied), but the fixed replacement's own
    /// three-field match must still fail closed on ANY single mismatch —
    /// this is the guard that keeps "type your way to root" from being
    /// trivially easy, per Models.swift's own doc comment.
    func testWrongLastNameDoesNotGrant() {
        let user = User(email: User.designatedRootEmail,
                         firstName: User.designatedRootFirstName,
                         lastName: "NotGraz")
        XCTAssertFalse(user.elevateIfDesignatedRoot())
        XCTAssertFalse(user.isRoot)
        XCTAssertEqual(user.role, .member)
    }

    func testWrongEmailDoesNotGrant() {
        let user = User(email: "someone-else@example.com",
                         firstName: User.designatedRootFirstName,
                         lastName: User.designatedRootLastName)
        XCTAssertFalse(user.elevateIfDesignatedRoot())
        XCTAssertFalse(user.isRoot)
    }

    func testWrongFirstNameDoesNotGrant() {
        let user = User(email: User.designatedRootEmail,
                         firstName: "NotBlindensport",
                         lastName: User.designatedRootLastName)
        XCTAssertFalse(user.elevateIfDesignatedRoot())
        XCTAssertFalse(user.isRoot)
    }

    /// The designated account is always created manually (RegisterView),
    /// so a user could plausibly type the club name in any casing.
    func testCaseInsensitiveMatchStillGrants() {
        let user = User(email: "BLINDENSPORT.GVSC@GMAIL.COM",
                         firstName: "blindensport",
                         lastName: "GRAZ")
        XCTAssertTrue(user.elevateIfDesignatedRoot())
        XCTAssertTrue(user.isRoot)
    }

    /// Autocorrect/autocapitalize on a phone keyboard can leave stray
    /// leading/trailing whitespace in a manually-typed form field.
    func testWhitespacePaddedMatchStillGrants() {
        let user = User(email: "  blindensport.gvsc@gmail.com  ",
                         firstName: " Blindensport ",
                         lastName: " Graz ")
        XCTAssertTrue(user.elevateIfDesignatedRoot())
        XCTAssertTrue(user.isRoot)
    }

    /// Guards against the Phase 2 audit log growing a duplicate
    /// `RoleChangeLog` entry every time an already-root account happens to
    /// pass through one of the 4 elevateIfDesignatedRoot call sites again
    /// (e.g. re-opening EditAccountView without changing anything).
    func testAlreadyRootDoesNotReGrantOrReturnTrue() {
        let user = User(email: User.designatedRootEmail,
                         firstName: User.designatedRootFirstName,
                         lastName: User.designatedRootLastName,
                         role: .admin,
                         isRoot: true)
        XCTAssertFalse(user.elevateIfDesignatedRoot(),
                        "an already-root account must not re-grant (and every call site only logs when this returns true)")
    }

    /// Regression guard for audit.md Security Finding 1: the removed
    /// TEST-ONLY backdoor (Phase 1) must never reappear. Reads the actual
    /// source files (Simulator processes share the host Mac's filesystem,
    /// unlike a sandboxed device build) rather than asserting against a
    /// symbol that, if reintroduced, would just make this test file itself
    /// fail to compile instead of fail at runtime.
    func testTestAdminBackdoorSymbolsAreGoneFromSource() throws {
        let thisFile = URL(fileURLWithPath: #filePath)
        let sourceDir = thisFile
            .deletingLastPathComponent() // BlindensportGrazTests/
            .deletingLastPathComponent() // repo root
            .appendingPathComponent("BlindensportGraz")
        let swiftFiles = try FileManager.default.contentsOfDirectory(at: sourceDir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        XCTAssertFalse(swiftFiles.isEmpty, "sanity check: expected to find BlindensportGraz/*.swift source files at \(sourceDir.path)")

        for file in swiftFiles {
            let contents = try String(contentsOf: file, encoding: .utf8)
            XCTAssertFalse(contents.contains("testAdminEmail"),
                            "\(file.lastPathComponent) still references the removed testAdminEmail backdoor")
            XCTAssertFalse(contents.contains("elevateIfTestAdmin"),
                            "\(file.lastPathComponent) still references the removed elevateIfTestAdmin() backdoor")
        }
    }
}
