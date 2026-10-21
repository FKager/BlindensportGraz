import XCTest
@testable import CloudKitS2SCore

/// Protected member data (svnr, iban, birthDate, lastMedicalExamination)
/// lives only in Supabase `member_private` — these check the row format and
/// that a roster record exposes it only through `privateData`.
final class MemberPrivateTests: XCTestCase {

    private let birth = MemberBulkImport.parseFlexibleDate("1990-05-03")!

    func testPrivateDataCarriesTheProtectedFields() {
        let record = MemberRecord(id: UUID().uuidString, firstName: "Anna", lastName: "Muster",
                                  street: "", zip: "", city: "", country: "", email: "", phone: "",
                                  memberNumber: "", joinedAt: Date(), notes: "", gender: "", title: "",
                                  birthDate: birth, sportId: "", svnr: "1234010190", iban: "AT611904300234573201",
                                  lastMedicalExamination: birth, defaultFunction: "", memberOfGVSC: true)
        XCTAssertEqual(record.privateData.svnr, "1234010190")
        XCTAssertEqual(record.privateData.birthDate, birth)
    }

    func testImportRowPrivateDataParsesGermanDates() {
        let row = MemberBulkInput(firstName: "A", lastName: "B", birthDate: "03.05.1990", svnr: " 1234 ")
        XCTAssertEqual(row.privateData.svnr, "1234")
        XCTAssertEqual(row.privateData.birthDate, birth)
        XCTAssertTrue(MemberBulkInput(firstName: "A", lastName: "B").privateData.isEmpty)
    }

    func testSupabaseRowRoundTripKeepsTheDay() {
        let data = MemberPrivate(svnr: "1", iban: "AT", birthDate: birth, lastMedicalExamination: nil)
        let row = data.row(updatedBy: nil)
        XCTAssertEqual(row["birth_date"] as? String, "1990-05-03")
        XCTAssertTrue(row["last_medical_examination"] is NSNull)
        XCTAssertNil(row["updated_by"])
        XCTAssertEqual(MemberPrivate(row: row), data)
    }

    func testUpdatedByIsLowercaseUUID() {
        let admin = UUID()
        XCTAssertEqual(MemberPrivate().row(updatedBy: admin)["updated_by"] as? String, admin.uuidString.lowercased())
    }

    func testWriteGuardBlocksProtectedFieldsAndRetiredTypes() {
        XCTAssertThrowsError(try CloudKitWriteGuard.check(recordType: "ClubMember", fieldNames: ["firstName", "iban"]))
        XCTAssertThrowsError(try CloudKitWriteGuard.check(recordType: "UserIdentity", fieldNames: ["email"]))
        XCTAssertNoThrow(try CloudKitWriteGuard.check(recordType: "ClubMember", fieldNames: ["firstName", "city"]))
        XCTAssertNoThrow(try CloudKitWriteGuard.check(recordType: "Training", fieldNames: ["svnr"]))
    }
}
