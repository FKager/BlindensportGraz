import XCTest
import SwiftData
@testable import BlindensportGraz

/// Covers `Member.resolveMembershipRequest` — the pure decision logic behind
/// AccountView's "Mitgliedschaft beantragen" button (reuse an existing
/// roster match vs. propose a new entry). Deliberately doesn't exercise
/// `MemberService.save`/the actual insert — that goes through
/// `CloudKitSync.shared.pushMember`, which crash-loops under this sandboxed
/// environment's unsigned test runs (same documented limitation as
/// MemberImportExportTests) — this suite only checks the decision itself.
@MainActor
final class MemberMembershipRequestTests: XCTestCase {

    func testResolveReturnsExistingMemberWhenEmailMatches() {
        let member = Member(firstName: "Anna", lastName: "Muster", email: "anna@example.com")
        let user = User(email: "Anna@Example.com", firstName: "Anna", lastName: "M.", role: .member)

        let outcome = Member.resolveMembershipRequest(for: user, in: [member])

        guard case .existing(let matched) = outcome else {
            return XCTFail("Expected .existing, got \(outcome)")
        }
        XCTAssertEqual(matched.id, member.id)
    }

    func testResolveReturnsExistingMemberWhenNameMatchesAndNoEmail() {
        let member = Member(firstName: "Bernd", lastName: "Helfer")
        let user = User(email: "bernd@example.com", firstName: "Bernd", lastName: "Helfer", role: .member)

        let outcome = Member.resolveMembershipRequest(for: user, in: [member])

        guard case .existing(let matched) = outcome else {
            return XCTFail("Expected .existing, got \(outcome)")
        }
        XCTAssertEqual(matched.id, member.id)
    }

    /// The core "request" path: no roster match at all -> a brand-new,
    /// not-yet-inserted Member, pre-filled from the user's account data and
    /// NOT auto-confirmed as an actual club member (memberOfGVSC: false) --
    /// an admin reviews and confirms it in Benutzerverwaltung.
    func testResolveProposesNewUnconfirmedMemberWhenNoMatch() {
        let user = User(email: "clara@example.com", firstName: "Clara", lastName: "Neu", role: .member)

        let outcome = Member.resolveMembershipRequest(for: user, in: [])

        guard case .new(let proposed) = outcome else {
            return XCTFail("Expected .new, got \(outcome)")
        }
        XCTAssertEqual(proposed.firstName, "Clara")
        XCTAssertEqual(proposed.lastName, "Neu")
        XCTAssertEqual(proposed.email, "clara@example.com")
        XCTAssertFalse(proposed.memberOfGVSC)
    }

    /// Same "no match" case even when the roster is non-empty, as long as
    /// none of its entries match this specific user by email or name.
    func testResolveProposesNewMemberWhenRosterHasOnlyUnrelatedEntries() {
        let unrelated = Member(firstName: "Someone", lastName: "Else", email: "someone@example.com")
        let user = User(email: "dora@example.com", firstName: "Dora", lastName: "Fremd", role: .member)

        let outcome = Member.resolveMembershipRequest(for: user, in: [unrelated])

        guard case .new = outcome else {
            return XCTFail("Expected .new, got \(outcome)")
        }
    }

    /// The Sportler/Helfer selection (AccountView's confirmationDialog) maps
    /// straight onto MembershipRole's own raw values ("player"/"coach"), so
    /// a new self-requested entry's defaultFunction stays directly usable as
    /// a MembershipRole.normalize(...) input later, not a separate ad-hoc
    /// vocabulary.
    func testResolveNewMemberUsesPlayerDefaultFunctionForSportlerChoice() {
        let user = User(email: "erik@example.com", firstName: "Erik", lastName: "Sportler", role: .member)

        let outcome = Member.resolveMembershipRequest(for: user, in: [], defaultFunction: MembershipRole.player.rawValue)

        guard case .new(let proposed) = outcome else {
            return XCTFail("Expected .new, got \(outcome)")
        }
        XCTAssertEqual(proposed.defaultFunction, "player")
    }

    func testResolveNewMemberUsesCoachDefaultFunctionForHelferChoice() {
        let user = User(email: "frieda@example.com", firstName: "Frieda", lastName: "Helferin", role: .member)

        let outcome = Member.resolveMembershipRequest(for: user, in: [], defaultFunction: MembershipRole.coach.rawValue)

        guard case .new(let proposed) = outcome else {
            return XCTFail("Expected .new, got \(outcome)")
        }
        XCTAssertEqual(proposed.defaultFunction, "coach")
    }

    /// An existing matched entry is admin-managed data — the Sportler/Helfer
    /// choice must never overwrite it, only apply to a freshly-created one.
    func testResolveIgnoresDefaultFunctionWhenReusingExistingMember() {
        let member = Member(firstName: "Greta", lastName: "Bestand", email: "greta@example.com",
                             defaultFunction: "assistant")
        let user = User(email: "greta@example.com", firstName: "Greta", lastName: "Bestand", role: .member)

        let outcome = Member.resolveMembershipRequest(for: user, in: [member], defaultFunction: MembershipRole.player.rawValue)

        guard case .existing(let matched) = outcome else {
            return XCTFail("Expected .existing, got \(outcome)")
        }
        XCTAssertEqual(matched.defaultFunction, "assistant")
    }

    // MARK: - Member.preferredMembershipRoleRawValue
    // (AddTeamMemberView's Rolle-picker pre-fill, the other end of the same
    // defaultFunction that requestMembership(for:as:) sets above)

    func testPreferredRoleReturnsCoachDefaultFunctionAsIs() {
        let member = Member(firstName: "Hannes", lastName: "Trainer", defaultFunction: "coach")
        XCTAssertEqual(member.preferredMembershipRoleRawValue, "coach")
    }

    func testPreferredRoleReturnsAssistantDefaultFunctionAsIs() {
        let member = Member(firstName: "Ida", lastName: "Betreuerin", defaultFunction: "assistant")
        XCTAssertEqual(member.preferredMembershipRoleRawValue, "assistant")
    }

    func testPreferredRoleFallsBackToPlayerWhenDefaultFunctionIsBlank() {
        let member = Member(firstName: "Jonas", lastName: "Blank")
        XCTAssertEqual(member.preferredMembershipRoleRawValue, "player")
    }

    /// A free-text/unrecognized defaultFunction (imported roster data isn't
    /// always one of the three known MembershipRole strings, see
    /// MembershipRole's own doc comment on `.other`) must never surface as a
    /// segmented-control value the Rolle picker can't actually display.
    func testPreferredRoleFallsBackToPlayerForUnrecognizedDefaultFunction() {
        let member = Member(firstName: "Klara", lastName: "Sonderfall", defaultFunction: "Zeugwart")
        XCTAssertEqual(member.preferredMembershipRoleRawValue, "player")
    }
}
