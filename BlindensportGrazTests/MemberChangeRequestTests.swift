import XCTest
import SwiftData
@testable import BlindensportGraz

/// Coverage for `MemberChangeRequest`'s pure logic (architecture-review.md
/// §5 P2's member self-service + admin approval queue): snapshot, diffing,
/// and applying. No CloudKit involved.
@MainActor
final class MemberChangeRequestTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(schema: AppModelSchema.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return ModelContext(try ModelContainer(for: AppModelSchema.schema, configurations: [config]))
    }

    private func makeMember() -> Member {
        Member(firstName: "Sam", lastName: "Mahler", street: "Alte Gasse 1", zip: "8010", city: "Graz",
              country: "Österreich", email: "sam@example.at", phone: "0664 1234567",
              svnr: "1234010180", iban: "AT611904300234573201")
    }

    func testSnapshotCopiesEveryEditableFieldFromTheMember() {
        let member = makeMember()
        let snapshot = MemberChangeRequest.snapshot(of: member, requestedBy: "user-1")

        XCTAssertEqual(snapshot.memberID, member.id)
        XCTAssertEqual(snapshot.requestedBy, "user-1")
        XCTAssertEqual(snapshot.status, MemberChangeRequest.pendingStatus)
        XCTAssertEqual(snapshot.firstName, member.firstName)
        XCTAssertEqual(snapshot.street, member.street)
        XCTAssertEqual(snapshot.svnr, member.svnr)
        XCTAssertEqual(snapshot.iban, member.iban)
        XCTAssertFalse(snapshot.differs(from: member), "an untouched snapshot must not read as changed")
    }

    func testDiffersDetectsAnyChangedField() {
        let member = makeMember()
        let draft = MemberChangeRequest.snapshot(of: member, requestedBy: "user-1")

        XCTAssertFalse(draft.differs(from: member))
        draft.phone = "0699 9998888"
        XCTAssertTrue(draft.differs(from: member))
    }

    func testDiffersComparesOptionalDatesCorrectly() {
        let member = makeMember()
        let draft = MemberChangeRequest.snapshot(of: member, requestedBy: "user-1")
        XCTAssertFalse(draft.differs(from: member), "both nil birthDate must compare equal")

        draft.birthDate = Date(timeIntervalSince1970: 0)
        XCTAssertTrue(draft.differs(from: member))
    }

    func testApplyCopiesEveryProposedFieldOntoTheMember() throws {
        let context = try makeContext()
        let member = makeMember()
        context.insert(member)
        try context.save()

        let draft = MemberChangeRequest.snapshot(of: member, requestedBy: "user-1")
        draft.street = "Neue Straße 5"
        draft.iban = "AT483200000012345864"
        draft.svnr = "9876010180"

        draft.apply(to: member)

        XCTAssertEqual(member.street, "Neue Straße 5")
        XCTAssertEqual(member.iban, "AT483200000012345864")
        XCTAssertEqual(member.svnr, "9876010180")
        // Untouched fields must survive apply() unchanged.
        XCTAssertEqual(member.firstName, "Sam")
        XCTAssertEqual(member.city, "Graz")
    }

    func testApplyDoesNotTouchAdminOnlyFieldsNotOnTheRequest() throws {
        // memberNumber/joinedAt/notes/defaultFunction/memberOfGVSC are
        // deliberately absent from MemberChangeRequest (see its doc
        // comment) — apply() must leave them exactly as they were.
        let context = try makeContext()
        let member = makeMember()
        member.memberNumber = "M-042"
        member.notes = "Vereinsintern"
        member.memberOfGVSC = true
        context.insert(member)
        try context.save()

        let draft = MemberChangeRequest.snapshot(of: member, requestedBy: "user-1")
        draft.firstName = "Samuel"
        draft.apply(to: member)

        XCTAssertEqual(member.memberNumber, "M-042")
        XCTAssertEqual(member.notes, "Vereinsintern")
        XCTAssertTrue(member.memberOfGVSC)
    }
}
