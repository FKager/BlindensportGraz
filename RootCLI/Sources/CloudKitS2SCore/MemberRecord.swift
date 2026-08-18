import Foundation

/// Single source of truth for the `ClubMember` CKRecord field mapping,
/// shared by `rootcli import-members` and `clubmembersapi`'s REST routes so
/// the two tools can't silently drift apart the way the app's own
/// hand-mirrored `MemberInput` struct already has to be kept in lockstep
/// with `Models.swift`'s `Member` on every field change (see cerebrum.md).
/// Named `MemberRecord` after the app-side `ClubMember` -> `Member` rename
/// (2026-08-01), but `dto.recordType`/CKRecord's `recordType` stay the
/// historical "ClubMember" string, since that's what already-synced
/// production data is stored under — only the Swift-level name changed.
public struct MemberRecord: Codable, Equatable, Sendable {
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

    public init?(dto: CKRecordDTO) {
        guard dto.recordType == "ClubMember" else { return nil }
        id = dto.recordName
        firstName = dto.stringField("firstName") ?? ""
        lastName = dto.stringField("lastName") ?? ""
        street = dto.stringField("street") ?? ""
        zip = dto.stringField("zip") ?? ""
        city = dto.stringField("city") ?? ""
        country = dto.stringField("country") ?? ""
        email = dto.stringField("email") ?? ""
        phone = dto.stringField("phone") ?? ""
        memberNumber = dto.stringField("memberNumber") ?? ""
        joinedAt = dto.dateField("joinedAt") ?? Date()
        notes = dto.stringField("notes") ?? ""
        gender = dto.stringField("gender") ?? ""
        title = dto.stringField("title") ?? ""
        birthDate = dto.dateField("birthDate")
        sportId = dto.stringField("sportId") ?? ""
        svnr = dto.stringField("svnr") ?? ""
        iban = dto.stringField("iban") ?? ""
        lastMedicalExamination = dto.dateField("lastMedicalExamination")
        defaultFunction = dto.stringField("defaultFunction") ?? ""
        // Missing on records written before this flag existed — default true,
        // matching every pre-existing roster entry's implicit membership.
        // (Can't use `dto.boolField` here: it defaults absent fields to
        // `false`, which is the wrong default for this particular flag.)
        if let raw = (dto.fields["memberOfGVSC"] as? [String: Any])?["value"] as? NSNumber {
            memberOfGVSC = raw.boolValue
        } else {
            memberOfGVSC = true
        }
    }

    /// Field dict as CloudKit Web Services expects it for a create/update
    /// (`records/modify`). Excludes `id`, which is the CKRecord name, not a
    /// field. `birthDate`/`lastMedicalExamination` are omitted entirely when
    /// nil, rather than sent as a null/placeholder value — CloudKit Web
    /// Services treats an absent key as "leave unset", matching `dateField`'s
    /// read-side handling of a missing key as nil.
    public var ckFields: [String: Any] {
        var fields: [String: Any] = [
            "firstName": ["value": firstName],
            "lastName": ["value": lastName],
            "street": ["value": street],
            "zip": ["value": zip],
            "city": ["value": city],
            "country": ["value": country],
            "email": ["value": email],
            "phone": ["value": phone],
            "memberNumber": ["value": memberNumber],
            "notes": ["value": notes],
            "joinedAt": ["value": Int64(joinedAt.timeIntervalSince1970 * 1000), "type": "TIMESTAMP"],
            "gender": ["value": gender],
            "title": ["value": title],
            "sportId": ["value": sportId],
            "svnr": ["value": svnr],
            "iban": ["value": iban],
            "defaultFunction": ["value": defaultFunction],
            "memberOfGVSC": ["value": memberOfGVSC ? 1 : 0, "type": "INT64"]
        ]
        if let birthDate {
            fields["birthDate"] = ["value": Int64(birthDate.timeIntervalSince1970 * 1000), "type": "TIMESTAMP"]
        }
        if let lastMedicalExamination {
            fields["lastMedicalExamination"] = ["value": Int64(lastMedicalExamination.timeIntervalSince1970 * 1000), "type": "TIMESTAMP"]
        }
        return fields
    }
}
