import Foundation

/// Single source of truth for the `ClubMember` CKRecord field mapping,
/// shared by `rootcli import-members` and `clubmembersapi`'s REST routes so
/// the two tools can't silently drift apart the way the app's own
/// hand-mirrored `ClubMemberInput` struct already has to be kept in lockstep
/// with `Models.swift`'s `ClubMember` on every field change (see cerebrum.md).
public struct ClubMemberRecord: Codable, Equatable, Sendable {
    public var id: String
    public var firstName: String
    public var lastName: String
    public var street: String
    public var zip: String
    public var city: String
    public var email: String
    public var phone: String
    public var memberNumber: String
    public var joinedAt: Date
    public var notes: String

    public init(
        id: String = UUID().uuidString,
        firstName: String,
        lastName: String,
        street: String = "",
        zip: String = "",
        city: String = "",
        email: String = "",
        phone: String = "",
        memberNumber: String = "",
        joinedAt: Date = Date(),
        notes: String = ""
    ) {
        self.id = id
        self.firstName = firstName
        self.lastName = lastName
        self.street = street
        self.zip = zip
        self.city = city
        self.email = email
        self.phone = phone
        self.memberNumber = memberNumber
        self.joinedAt = joinedAt
        self.notes = notes
    }

    public init?(dto: CKRecordDTO) {
        guard dto.recordType == "ClubMember" else { return nil }
        id = dto.recordName
        firstName = dto.stringField("firstName") ?? ""
        lastName = dto.stringField("lastName") ?? ""
        street = dto.stringField("street") ?? ""
        zip = dto.stringField("zip") ?? ""
        city = dto.stringField("city") ?? ""
        email = dto.stringField("email") ?? ""
        phone = dto.stringField("phone") ?? ""
        memberNumber = dto.stringField("memberNumber") ?? ""
        joinedAt = dto.dateField("joinedAt") ?? Date()
        notes = dto.stringField("notes") ?? ""
    }

    /// Field dict as CloudKit Web Services expects it for a create/update
    /// (`records/modify`). Excludes `id`, which is the CKRecord name, not a field.
    public var ckFields: [String: Any] {
        [
            "firstName": ["value": firstName],
            "lastName": ["value": lastName],
            "street": ["value": street],
            "zip": ["value": zip],
            "city": ["value": city],
            "email": ["value": email],
            "phone": ["value": phone],
            "memberNumber": ["value": memberNumber],
            "notes": ["value": notes],
            "joinedAt": ["value": Int64(joinedAt.timeIntervalSince1970 * 1000), "type": "TIMESTAMP"]
        ]
    }
}
