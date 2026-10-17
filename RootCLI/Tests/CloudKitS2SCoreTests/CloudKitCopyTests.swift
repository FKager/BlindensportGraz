import XCTest
@testable import CloudKitS2SCore

/// `CloudKitCopy` (CloudKit → Supabase club data): ids, references, the
/// event-kind mapping and the `since` filter.
final class CloudKitCopyTests: XCTestCase {
    private let team = "0DDEC828-DC21-43CE-B11C-DF0A746D355D"
    private let member = "11111111-2222-3333-4444-555555555555"
    private let membership = "4875AA05-253C-468E-B285-3C94CB0EB70F"
    private let tournament = "D7FFB97A-D7B1-40F5-ACDE-D1A832D020E2"
    private let account = "578BD9C0-55F7-442E-A0B7-FD5609B5EF2F"

    private func record(_ type: String, _ name: String, _ fields: [String: Any], modified: Date? = nil) -> CKRecordDTO {
        CKRecordDTO(recordName: name, recordType: type,
                    fields: fields.mapValues { ["value": $0] }, modifiedAt: modified)
    }

    private var fixture: [String: [CKRecordDTO]] {
        [
            "ClubMember": [record("ClubMember", member, ["firstName": "Mia", "lastName": "M", "street": "Gasse 1"])],
            "Team": [record("Team", team, ["name": "Grazer VSC Damen", "sport": "Torball"])],
            "TeamMembership": [
                record("TeamMembership", membership, ["teamID": team, "clubMemberID": member,
                                                      "userID": account, "role": "player"]),
                record("TeamMembership", UUID().uuidString, ["teamID": UUID().uuidString])
            ],
            "Tournament": [record("Tournament", tournament, [
                "name": "3-Länderturnier", "venue": "Neumarkt", "maxTeams": 8, "status": "finished",
                "startDate": 1_774_120_440_000, "teamIDs": [team, UUID().uuidString]
            ])],
            "TournamentAttendance": [record("TournamentAttendance", UUID().uuidString, [
                "tournamentID": tournament, "membershipID": membership, "attended": 1, "praeAmount": 200
            ])]
        ]
    }

    private func rows(_ result: CloudKitCopy.Result, _ table: String) -> [[String: Any]] {
        result.batches.first { $0.table == table }?.rows ?? []
    }

    func testRosterSplitsNamesAndContactsWithLowercasedIDs() throws {
        let result = try CloudKitCopy.map(fixture, existingUserIDs: [])
        XCTAssertEqual(rows(result, "members").first?["id"] as? String, member.lowercased())
        XCTAssertNil(rows(result, "members").first?["street"])
        XCTAssertEqual(rows(result, "member_contacts").first?["street"] as? String, "Gasse 1")
    }

    func testMembershipWithMissingTeamIsSkippedAndUnknownAccountIsNulled() throws {
        let result = try CloudKitCopy.map(fixture, existingUserIDs: [])
        XCTAssertEqual(rows(result, "team_memberships").count, 1)
        XCTAssertTrue(rows(result, "team_memberships")[0]["user_id"] is NSNull)
        XCTAssertEqual(result.skipped.count, 1)

        let withAccount = try CloudKitCopy.map(fixture, existingUserIDs: [account.lowercased()])
        XCTAssertEqual(rows(withAccount, "team_memberships")[0]["user_id"] as? String, account.lowercased())
    }

    func testTournamentUsesLegacyNameAndVenueAndKeepsOnlyExistingTeams() throws {
        let result = try CloudKitCopy.map(fixture, existingUserIDs: [])
        let event = try XCTUnwrap(rows(result, "events").first)
        XCTAssertEqual(event["kind"] as? String, "tournament")
        XCTAssertEqual(event["title"] as? String, "3-Länderturnier")
        XCTAssertEqual(event["location"] as? String, "Neumarkt")
        XCTAssertEqual(event["max_teams"] as? Int, 8)
        XCTAssertTrue(event["duration_minutes"] is NSNull)
        XCTAssertEqual(event["team_ids"] as? [String], [team.lowercased()])
        XCTAssertEqual(Set(rows(result, "events").map { Set($0.keys) }).count, 1, "uniform keys for bulk insert")
    }

    func testAttendanceMapsTournamentAndPrae() throws {
        let row = try XCTUnwrap(rows(try CloudKitCopy.map(fixture, existingUserIDs: []), "attendances").first)
        XCTAssertEqual(row["event_id"] as? String, tournament.lowercased())
        XCTAssertEqual(row["attended"] as? Bool, true)
        XCTAssertEqual(row["prae_amount"] as? Double, 200)
    }

    func testSinceCopiesOnlyNewerRecords() throws {
        var records = fixture
        let cutoff = Date(timeIntervalSince1970: 1_800_000_000)
        records["Team"] = [record("Team", team, ["name": "Old"], modified: cutoff.addingTimeInterval(-60))]
        let result = try CloudKitCopy.map(records, existingUserIDs: [], since: cutoff)
        XCTAssertTrue(rows(result, "teams").isEmpty)
        // Still referenced by the unfiltered membership set:
        XCTAssertEqual(rows(result, "team_memberships").count, 1)
    }

    func testRecordsWithFilesStopTheCopy() {
        var records = fixture
        records["EventImage"] = [record("EventImage", UUID().uuidString, [:])]
        XCTAssertThrowsError(try CloudKitCopy.map(records, existingUserIDs: []))
    }
}
