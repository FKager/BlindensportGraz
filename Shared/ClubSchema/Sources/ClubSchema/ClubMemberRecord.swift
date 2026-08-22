import Foundation

/// Plain data shape for one Member/ClubMember record — the shared source of
/// truth for `RootCLI`'s `MemberRecord` (see
/// `RootCLI/Sources/CloudKitS2SCore/MemberRecord.swift`, now a thin
/// `typealias` + CKRecordDTO-conversion extension over this type) and for
/// the field list the app's `Member` model (BlindensportGraz/Member.swift)
/// and `CKSchema.ClubMember` are expected to stay in lockstep with.
///
/// Deliberately holds no CloudKit/SwiftData/Vapor-specific conversion logic
/// itself — those stay local to whichever side needs them (RootCLI's
/// `CKRecordDTO` conversion, the app's `@Model` `Member` class), since this
/// package only depends on Foundation and must stay usable from both an iOS
/// app target and a macOS SPM executable.
public struct ClubMemberRecord: Codable, Equatable, Sendable {
    /// The CKRecord type string — stays the historical "ClubMember" (not
    /// renamed to match the app-side `Member` rename, 2026-08-01) since
    /// that's what already-synced production data is stored under.
    public static let recordType = "ClubMember"

    public var id: String
    public var firstName: String
    public var lastName: String
    public var street: String
    public var zip: String
    public var city: String
    public var country: String
    public var email: String
    public var phone: String
    public var memberNumber: String
    public var joinedAt: Date
    public var notes: String
    public var gender: String
    public var title: String
    public var birthDate: Date?
    public var sportId: String
    public var svnr: String
    public var iban: String
    public var lastMedicalExamination: Date?
    public var defaultFunction: String
    public var memberOfGVSC: Bool

    public init(
        id: String = UUID().uuidString,
        firstName: String,
        lastName: String,
        street: String = "",
        zip: String = "",
        city: String = "",
        country: String = "",
        email: String = "",
        phone: String = "",
        memberNumber: String = "",
        joinedAt: Date = Date(),
        notes: String = "",
        gender: String = "",
        title: String = "",
        birthDate: Date? = nil,
        sportId: String = "",
        svnr: String = "",
        iban: String = "",
        lastMedicalExamination: Date? = nil,
        defaultFunction: String = "",
        memberOfGVSC: Bool = true
    ) {
        self.id = id
        self.firstName = firstName
        self.lastName = lastName
        self.street = street
        self.zip = zip
        self.city = city
        self.country = country
        self.email = email
        self.phone = phone
        self.memberNumber = memberNumber
        self.joinedAt = joinedAt
        self.notes = notes
        self.gender = gender
        self.title = title
        self.birthDate = birthDate
        self.sportId = sportId
        self.svnr = svnr
        self.iban = iban
        self.lastMedicalExamination = lastMedicalExamination
        self.defaultFunction = defaultFunction
        self.memberOfGVSC = memberOfGVSC
    }
}
