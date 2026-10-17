import XCTest
import Supabase
@testable import BlindensportGraz

/// Round-trips the Supabase row types through the same PostgREST
/// encoder/decoder `SupabaseSync` uses for outbox payloads and pulls,
/// without touching `SupabaseSync.shared` or the network.
@MainActor
final class SupabaseRowsTests: XCTestCase {

    private func json<Row: Encodable>(_ row: Row) throws -> [String: Any] {
        let data = try PostgrestClient.Configuration.jsonEncoder.encode(row)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func roundTrip<Row: Codable>(_ row: Row) throws -> Row {
        let data = try PostgrestClient.Configuration.jsonEncoder.encode(row)
        return try PostgrestClient.Configuration.jsonDecoder.decode(Row.self, from: data)
    }

    // MARK: - Teams / memberships

    func testTeamRowRoundTripsAndOmitsUpdatedAt() throws {
        let createdAt = Date(timeIntervalSince1970: 1_800_000_000)
        let team = Team(name: "Torball A", sport: "Torball", descriptionText: "Herren", createdAt: createdAt)
        let row = TeamDBRow(team)

        XCTAssertEqual(try roundTrip(row), row)
        let object = try json(row)
        XCTAssertEqual(object["description_text"] as? String, "Herren")
        XCTAssertNil(object["updated_at"], "updated_at is server state; pushes must leave it to the trigger")
    }

    func testTeamMembershipSendsClearedLinksAsExplicitNulls() throws {
        let team = Team(name: "Goalball", sport: "Goalball")
        let membership = TeamMembership(team: team, role: .coach)
        let object = try json(TeamMembershipDBRow(membership))

        XCTAssertEqual(object["team_id"] as? String, team.id.uuidString.lowercased())
        XCTAssertEqual(object["role"] as? String, MembershipRole.coach.rawValue)
        XCTAssertTrue(object["member_id"] is NSNull, "a cleared member link must reach the server as null")
        XCTAssertTrue(object["user_id"] is NSNull)
    }

    // MARK: - Events

    func testTrainingRowCarriesKindTrainingFieldsAndTeamIDs() throws {
        let team = Team(name: "Torball B", sport: "Torball")
        let training = Training(title: "Dienstagstraining", sport: "Torball", location: "Halle",
                                startDate: Date(timeIntervalSince1970: 1_800_000_000),
                                durationMinutes: 120, focusArea: "Abwehr")
        training.teams = [team]
        let row = EventDBRow(training)

        XCTAssertEqual(row.kind, "training")
        XCTAssertEqual(row.durationMinutes, 120)
        XCTAssertEqual(row.focusArea, "Abwehr")
        XCTAssertNil(row.maxTeams)
        XCTAssertEqual(row.teamIDs, [team.id])
        XCTAssertEqual(try roundTrip(row), row)
        XCTAssertTrue(try json(row)["max_teams"] is NSNull)
    }

    func testTournamentRowCarriesMaxTeams() throws {
        let tournament = Tournament(title: "Landesmeisterschaft", sport: "Torball", location: "Graz",
                                    startDate: .now, endDate: .now.addingTimeInterval(3600))
        tournament.maxTeams = 12
        let row = EventDBRow(tournament)

        XCTAssertEqual(row.kind, "tournament")
        XCTAssertEqual(row.maxTeams, 12)
        XCTAssertNil(row.durationMinutes)
    }

    // MARK: - Receipts

    func testMonthScopedReceiptRoundTrips() throws {
        let receipt = ExpenseReceipt(imageData: Data([0xFF, 0xD8]), uploadedBy: "user-123",
                                     uploadedAt: Date(timeIntervalSince1970: 1_800_000_000),
                                     note: "Fahrtkosten", month: 9, year: 2026)
        let row = ExpenseReceiptDBRow(receipt)

        XCTAssertEqual(try roundTrip(row), row)
        XCTAssertNil(row.tournamentID)
        XCTAssertEqual(row.storagePath, "\(receipt.id.uuidString.lowercased()).jpg")
    }

    func testTournamentScopedReceiptKeepsTournamentIDWithoutMonthYear() throws {
        let tournament = Tournament(title: "Cup", sport: "Goalball", location: "Wien",
                                    startDate: .now, endDate: .now.addingTimeInterval(3600))
        let row = ExpenseReceiptDBRow(ExpenseReceipt(imageData: Data([0x01]), uploadedBy: "u",
                                                     tournament: tournament))

        XCTAssertEqual(row.tournamentID, tournament.id)
        XCTAssertNil(row.month)
        XCTAssertNil(row.year)
        XCTAssertEqual(try roundTrip(row), row)
    }

    // MARK: - Deletions

    func testDeletionRowDecodesServerJSON() throws {
        let id = UUID()
        let payload = """
        {"table_name":"events","row_id":"\(id.uuidString.lowercased())","deleted_at":"2026-10-13T20:55:51.439+00:00"}
        """
        let row = try PostgrestClient.Configuration.jsonDecoder.decode(DeletionDBRow.self, from: Data(payload.utf8))

        XCTAssertEqual(row.tableName, "events")
        XCTAssertEqual(row.rowID, id)
    }
}
