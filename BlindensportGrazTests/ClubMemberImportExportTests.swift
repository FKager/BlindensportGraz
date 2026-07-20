import XCTest
import SwiftData
@testable import BlindensportGraz

@MainActor
final class ClubMemberImportExportTests: XCTestCase {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            User.self, SportEvent.self, Tournament.self, Training.self, Team.self,
            TeamMembership.self, EventParticipation.self, ClubMember.self,
            EventImage.self, Attendance.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [config])
    }

    /// A freshly-exported file, re-imported into the same roster, should
    /// update the existing entries in place (matched by `id`) rather than
    /// creating duplicates — this is what makes "export, edit externally,
    /// re-import" a safe round trip.
    func testExportThenReimportIsIdempotent() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let member = ClubMember(firstName: "Anna", lastName: "Muster", street: "Hauptstraße 1",
                                 zip: "8010", city: "Graz", email: "anna@example.com")
        context.insert(member)
        try context.save()

        let url = try ClubMemberImportExport.exportFile(members: [member])
        defer { try? FileManager.default.removeItem(at: url) }
        let data = try Data(contentsOf: url)

        let result = ClubMemberImportExport.importMembers(from: data, into: [member], modelContext: context)

        XCTAssertEqual(result.created, 0)
        XCTAssertEqual(result.updated, 1)
        let all = try context.fetch(FetchDescriptor<ClubMember>())
        XCTAssertEqual(all.count, 1, "re-importing the same exported file must not duplicate the entry")
        XCTAssertEqual(all.first?.city, "Graz")
    }

    /// A row with no matching `id` and no matching existing entry (by id,
    /// email, or first+last name) is a new member.
    func testImportCreatesNewMember() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let json = """
        [{"firstName":"Peter","lastName":"Huber","email":"peter@example.com"}]
        """
        let result = ClubMemberImportExport.importMembers(from: Data(json.utf8), into: [], modelContext: context)

        XCTAssertEqual(result.created, 1)
        XCTAssertEqual(result.updated, 0)
        XCTAssertEqual(result.skipped, 0)
        let all = try context.fetch(FetchDescriptor<ClubMember>())
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.email, "peter@example.com")
    }

    /// No `id` in the row, but the email matches an existing roster entry —
    /// should update that entry, not create a duplicate. Covers importing a
    /// file that was hand-written or exported from RootCLI (which doesn't
    /// necessarily assign the same ids as the app).
    func testImportMatchesExistingByEmailWhenNoID() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let existing = ClubMember(firstName: "Anna", lastName: "Muster", email: "anna@example.com")
        context.insert(existing)
        try context.save()

        let json = """
        [{"firstName":"Anna","lastName":"Muster","email":"anna@example.com","city":"Graz"}]
        """
        let result = ClubMemberImportExport.importMembers(from: Data(json.utf8), into: [existing], modelContext: context)

        XCTAssertEqual(result.created, 0)
        XCTAssertEqual(result.updated, 1)
        let all = try context.fetch(FetchDescriptor<ClubMember>())
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.city, "Graz")
    }

    /// Entries missing firstName/lastName are skipped individually rather
    /// than aborting the whole import — matches RootCLI's import-members
    /// behavior for the same file format.
    func testImportSkipsEntriesMissingRequiredFields() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let json = """
        [
          {"firstName":"","lastName":"Muster"},
          {"firstName":"Peter","lastName":"Huber"}
        ]
        """
        let result = ClubMemberImportExport.importMembers(from: Data(json.utf8), into: [], modelContext: context)

        XCTAssertEqual(result.created, 1)
        XCTAssertEqual(result.skipped, 1)
        let all = try context.fetch(FetchDescriptor<ClubMember>())
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.firstName, "Peter")
    }

    /// "yyyy-MM-dd" is the format used in RootCLI/members.example.json —
    /// files without a full ISO8601 joinedAt must still import correctly.
    func testImportAcceptsPlainDateJoinedAt() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let json = """
        [{"firstName":"Anna","lastName":"Muster","joinedAt":"2020-05-01"}]
        """
        let result = ClubMemberImportExport.importMembers(from: Data(json.utf8), into: [], modelContext: context)

        XCTAssertEqual(result.created, 1)
        let all = try context.fetch(FetchDescriptor<ClubMember>())
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        XCTAssertEqual(all.first.map { formatter.string(from: $0.joinedAt) }, "2020-05-01")
    }

    func testImportRejectsMalformedJSON() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let result = ClubMemberImportExport.importMembers(from: Data("not json".utf8), into: [], modelContext: context)

        XCTAssertEqual(result.created, 0)
        XCTAssertEqual(result.updated, 0)
        XCTAssertEqual(result.skipped, 1)
        XCTAssertFalse(result.skippedDetails.isEmpty)
    }
}
