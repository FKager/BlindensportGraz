import XCTest
@testable import BlindensportGraz

/// Coverage for `FullBackup`'s pure `encode` functions (architecture-
/// review.md §5 P2's full club backup/restore) — field shape and values
/// only. `export`/`FullBackupImporter.restore` touch SwiftData fetches and
/// the `*Service.save` CloudKit-push path respectively, so per this app's
/// "no CloudKit in unit tests" rule they're exercised by hand, not here.
@MainActor
final class FullBackupTests: XCTestCase {

    func testEncodeUserOmitsEmailAndAppleIdentifier() {
        let user = User(email: "secret@example.at", firstName: "Sam", lastName: "Mahler", role: .admin,
                        isGrazerVSCMember: true, isRoot: false)
        let dict = FullBackup.encode(user)

        XCTAssertEqual(dict["id"] as? String, user.id.uuidString)
        XCTAssertEqual(dict["firstName"] as? String, "Sam")
        XCTAssertEqual(dict["role"] as? String, "admin")
        XCTAssertEqual(dict["isGrazerVSCMember"] as? Bool, true)
        XCTAssertNil(dict["email"], "email must never leave this device, not even in a backup file")
        XCTAssertNil(dict["appleUserIdentifier"])
    }

    func testEncodeMemberCapturesEveryEditableField() {
        let member = Member(firstName: "Anna", lastName: "Berger", street: "Hauptplatz 1", zip: "8010", city: "Graz",
                            country: "Österreich", svnr: "1234010180", iban: "AT611904300234573201")
        let dict = FullBackup.encode(member)

        XCTAssertEqual(dict["firstName"] as? String, "Anna")
        XCTAssertEqual(dict["street"] as? String, "Hauptplatz 1")
        XCTAssertEqual(dict["svnr"] as? String, "1234010180")
        XCTAssertEqual(dict["iban"] as? String, "AT611904300234573201")
        XCTAssertTrue(dict["birthDate"] is NSNull, "nil optional dates encode as NSNull, not absent")
    }

    func testEncodeMemberWithBirthDateProducesISO8601String() {
        let birthDate = Date(timeIntervalSince1970: 0)
        let member = Member(firstName: "Anna", lastName: "Berger", birthDate: birthDate)
        let dict = FullBackup.encode(member)

        let encoded = dict["birthDate"] as? String
        XCTAssertNotNil(encoded)
        XCTAssertEqual(FullBackup.date(["d": encoded ?? ""], "d"), birthDate)
    }

    func testEncodeTeam() {
        let team = Team(name: "Torball A", sport: "Torball", descriptionText: "Erste Mannschaft")
        let dict = FullBackup.encode(team)

        XCTAssertEqual(dict["name"] as? String, "Torball A")
        XCTAssertEqual(dict["sport"] as? String, "Torball")
    }

    func testEncodeTeamMembershipRecordsRelationshipsByID() {
        let team = Team(name: "Torball A", sport: "Torball")
        let user = User(email: "a@b.at", firstName: "Sam", lastName: "Mahler")
        let membership = TeamMembership(user: user, team: team, role: .coach)
        let dict = FullBackup.encode(membership)

        XCTAssertEqual(dict["teamID"] as? String, team.id.uuidString)
        XCTAssertEqual(dict["userID"] as? String, user.id.uuidString)
        XCTAssertTrue(dict["memberID"] is NSNull)
        XCTAssertEqual(dict["role"] as? String, "coach")
    }

    func testEncodeSportEventCapturesTeamIDs() {
        let team = Team(name: "Torball A", sport: "Torball")
        let event = SportEvent(title: "Vereinsfest", sport: "Torball", location: "Halle", startDate: .now,
                               endDate: .now.addingTimeInterval(3600), teams: [team])
        let dict = FullBackup.encode(event)

        XCTAssertEqual(dict["title"] as? String, "Vereinsfest")
        XCTAssertEqual(dict["teamIDs"] as? [String], [team.id.uuidString])
    }

    func testEncodeTrainingAddsDurationAndFocusAreaOnTopOfEventFields() {
        let training = Training(title: "Techniktraining", sport: "Torball", location: "Halle", startDate: .now,
                                durationMinutes: 60, focusArea: "Wurftechnik", status: Training.heldStatus)
        let dict = FullBackup.encode(training)

        XCTAssertEqual(dict["title"] as? String, "Techniktraining")
        XCTAssertEqual(dict["durationMinutes"] as? Int, 60)
        XCTAssertEqual(dict["focusArea"] as? String, "Wurftechnik")
        XCTAssertEqual(dict["status"] as? String, "held")
    }

    func testEncodeTournamentAddsMaxTeamsAndStatusOnTopOfEventFields() {
        let tournament = Tournament(title: "Landesmeisterschaft", sport: "Torball", location: "Halle",
                                    startDate: .now, endDate: .now.addingTimeInterval(7200), maxTeams: 12, status: "ongoing")
        let dict = FullBackup.encode(tournament)

        XCTAssertEqual(dict["maxTeams"] as? Int, 12)
        XCTAssertEqual(dict["status"] as? String, "ongoing")
    }

    func testEncodeEventParticipation() {
        let user = User(email: "a@b.at", firstName: "Sam", lastName: "Mahler")
        let event = SportEvent(title: "Vereinsfest", sport: "Torball", location: "Halle", startDate: .now, endDate: .now)
        let participation = EventParticipation(user: user, event: event, status: "confirmed")
        let dict = FullBackup.encode(participation)

        XCTAssertEqual(dict["userID"] as? String, user.id.uuidString)
        XCTAssertEqual(dict["eventID"] as? String, event.id.uuidString)
        XCTAssertEqual(dict["status"] as? String, "confirmed")
    }

    func testEncodeAttendanceHandlesNilPraeAmount() {
        let team = Team(name: "Torball A", sport: "Torball")
        let user = User(email: "a@b.at", firstName: "Sam", lastName: "Mahler")
        let membership = TeamMembership(user: user, team: team)
        let event = SportEvent(title: "Training", sport: "Torball", location: "Halle", startDate: .now, endDate: .now)
        let attendance = Attendance(event: event, membership: membership, attended: true)
        let dict = FullBackup.encode(attendance)

        XCTAssertEqual(dict["attended"] as? Bool, true)
        XCTAssertTrue(dict["praeAmount"] is NSNull)
    }

    func testEncodeAttendanceWithPraeAmount() {
        let team = Team(name: "Torball A", sport: "Torball")
        let user = User(email: "a@b.at", firstName: "Sam", lastName: "Mahler")
        let membership = TeamMembership(user: user, team: team, role: .coach)
        let event = SportEvent(title: "Training", sport: "Torball", location: "Halle", startDate: .now, endDate: .now)
        let attendance = Attendance(event: event, membership: membership, attended: true, praeAmount: 25.5)
        let dict = FullBackup.encode(attendance)

        XCTAssertEqual(dict["praeAmount"] as? Double, 25.5)
    }

    func testEncodeTrainingFavoriteCapturesTimeRangeAndTeamIDs() {
        let team = Team(name: "Torball A", sport: "Torball")
        let favorite = TrainingFavorite(title: "Montagstraining", sport: "Torball", startHour: 18, startMinute: 0,
                                        endHour: 19, endMinute: 30, weekday: 2, teams: [team])
        let dict = FullBackup.encode(favorite)

        XCTAssertEqual(dict["startHour"] as? Int, 18)
        XCTAssertEqual(dict["endMinute"] as? Int, 30)
        XCTAssertEqual(dict["teamIDs"] as? [String], [team.id.uuidString])
    }

    func testEncodeRoleChangeLog() {
        let userID = UUID()
        let entry = RoleChangeLog(userID: userID, oldRole: "member", newRole: "coach", changedBy: "admin-1")
        let dict = FullBackup.encode(entry)

        XCTAssertEqual(dict["userID"] as? String, userID.uuidString)
        XCTAssertEqual(dict["oldRole"] as? String, "member")
        XCTAssertEqual(dict["newRole"] as? String, "coach")
    }

    func testEncodeMemberChangeRequestCapturesAllProposedFields() {
        let member = Member(firstName: "Anna", lastName: "Berger")
        let request = MemberChangeRequest.snapshot(of: member, requestedBy: "user-1")
        request.phone = "0664 1234567"
        let dict = FullBackup.encode(request)

        XCTAssertEqual(dict["memberID"] as? String, member.id.uuidString)
        XCTAssertEqual(dict["requestedBy"] as? String, "user-1")
        XCTAssertEqual(dict["status"] as? String, MemberChangeRequest.pendingStatus)
        XCTAssertEqual(dict["phone"] as? String, "0664 1234567")
    }

    // MARK: - Decode helpers round-trip

    func testDecodeHelpersRoundTripEncodedValues() {
        let member = Member(firstName: "Anna", lastName: "Berger", birthDate: Date(timeIntervalSince1970: 1_000_000))
        let dict = FullBackup.encode(member)

        XCTAssertEqual(FullBackup.string(dict, "firstName"), "Anna")
        XCTAssertEqual(FullBackup.uuid(dict, "id"), member.id)
        XCTAssertEqual(FullBackup.date(dict, "birthDate"), member.birthDate)
        XCTAssertEqual(FullBackup.string(dict, "missingKey"), "", "missing string key defaults to empty, not a crash")
        XCTAssertNil(FullBackup.uuid(dict, "missingKey"))
    }

    func testStringListDefaultsToEmptyArrayWhenMissing() {
        XCTAssertEqual(FullBackup.stringList([:], "teamIDs"), [])
    }
}
