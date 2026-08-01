import Foundation

/// Loose, per-row-tolerant input shape for bulk Member import — shared by
/// `rootcli import-members` and clubmembersapi's `POST /api/members/import`,
/// so both accept exactly the same file/body shape (a JSON array, same as
/// what the app's own export produces) and apply exactly the same per-row
/// rules. Fields other than the required firstName/lastName are optional so a
/// missing key decodes as nil instead of aborting the whole array's decode —
/// see the 2026-07-17 cerebrum.md entry on why a non-optional Decodable
/// property is the wrong choice for a bulk importer.
///
/// Also accepts every attribute found in the club's real-world source roster
/// files (BlindensportGraz/../data/Person-Sport.json, Person-Others.json):
/// gender/title/birthDate/sportId/svnr/iban/lastMedicalExamination/
/// defaultFunction, plus `plz` as an alias for `zip` (German Postleitzahl,
/// used inconsistently in that source data) — decoded via a custom
/// `init(from:)` since `Codable` synthesis has no built-in alias-key support.
public struct MemberBulkInput: Codable, Sendable {
    public var id: String?
    public var firstName: String?
    public var lastName: String?
    public var street: String?
    public var zip: String?
    public var city: String?
    public var email: String?
    public var phone: String?
    public var memberNumber: String?
    public var joinedAt: String?
    public var notes: String?
    public var gender: String?
    public var title: String?
    public var birthDate: String?
    public var sportId: String?
    public var svnr: String?
    public var iban: String?
    public var lastMedicalExamination: String?
    public var defaultFunction: String?
    public var memberOfGVSC: Bool?

    private enum CodingKeys: String, CodingKey {
        case id, firstName, lastName, street, zip, plz, city, email, phone, memberNumber, joinedAt, notes,
             gender, title, birthDate, sportId, svnr, iban, lastMedicalExamination, defaultFunction, memberOfGVSC
    }

    public init(
        id: String? = nil, firstName: String? = nil, lastName: String? = nil,
        street: String? = nil, zip: String? = nil, city: String? = nil,
        email: String? = nil, phone: String? = nil, memberNumber: String? = nil,
        joinedAt: String? = nil, notes: String? = nil,
        gender: String? = nil, title: String? = nil, birthDate: String? = nil,
        sportId: String? = nil, svnr: String? = nil, iban: String? = nil,
        lastMedicalExamination: String? = nil, defaultFunction: String? = nil,
        memberOfGVSC: Bool? = nil
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

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        firstName = try container.decodeIfPresent(String.self, forKey: .firstName)
        lastName = try container.decodeIfPresent(String.self, forKey: .lastName)
        street = try container.decodeIfPresent(String.self, forKey: .street)
        zip = try container.decodeIfPresent(String.self, forKey: .zip)
            ?? container.decodeIfPresent(String.self, forKey: .plz)
        city = try container.decodeIfPresent(String.self, forKey: .city)
        email = try container.decodeIfPresent(String.self, forKey: .email)
        phone = try container.decodeIfPresent(String.self, forKey: .phone)
        memberNumber = try container.decodeIfPresent(String.self, forKey: .memberNumber)
        joinedAt = try container.decodeIfPresent(String.self, forKey: .joinedAt)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        gender = try container.decodeIfPresent(String.self, forKey: .gender)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        birthDate = try container.decodeIfPresent(String.self, forKey: .birthDate)
        sportId = try container.decodeIfPresent(String.self, forKey: .sportId)
        svnr = try container.decodeIfPresent(String.self, forKey: .svnr)
        iban = try container.decodeIfPresent(String.self, forKey: .iban)
        lastMedicalExamination = try container.decodeIfPresent(String.self, forKey: .lastMedicalExamination)
        defaultFunction = try container.decodeIfPresent(String.self, forKey: .defaultFunction)
        memberOfGVSC = try container.decodeIfPresent(Bool.self, forKey: .memberOfGVSC)
    }

    // Written explicitly because the `plz` alias case in CodingKeys has no
    // backing stored property, which blocks Encodable synthesis — same
    // reasoning as MemberIO in the app target. Always writes `zip`, never
    // `plz`.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encodeIfPresent(firstName, forKey: .firstName)
        try container.encodeIfPresent(lastName, forKey: .lastName)
        try container.encodeIfPresent(street, forKey: .street)
        try container.encodeIfPresent(zip, forKey: .zip)
        try container.encodeIfPresent(city, forKey: .city)
        try container.encodeIfPresent(email, forKey: .email)
        try container.encodeIfPresent(phone, forKey: .phone)
        try container.encodeIfPresent(memberNumber, forKey: .memberNumber)
        try container.encodeIfPresent(joinedAt, forKey: .joinedAt)
        try container.encodeIfPresent(notes, forKey: .notes)
        try container.encodeIfPresent(gender, forKey: .gender)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(birthDate, forKey: .birthDate)
        try container.encodeIfPresent(sportId, forKey: .sportId)
        try container.encodeIfPresent(svnr, forKey: .svnr)
        try container.encodeIfPresent(iban, forKey: .iban)
        try container.encodeIfPresent(lastMedicalExamination, forKey: .lastMedicalExamination)
        try container.encodeIfPresent(defaultFunction, forKey: .defaultFunction)
        try container.encodeIfPresent(memberOfGVSC, forKey: .memberOfGVSC)
    }
}

public struct MemberBulkImportResult: Sendable {
    public var succeeded = 0
    public var failed = 0
    public var messages: [String] = []
    public var total: Int { succeeded + failed }
}

public enum MemberBulkImport {
    /// Creates-or-replaces (via `createOrReplaceRecord`, no change-tag needed)
    /// one `Member` per input. A provided `id` must be a valid UUID string
    /// (it becomes the CKRecord name) — re-running with the same `id`s updates
    /// those records in place; omitting `id` mints a fresh UUID each time, so
    /// re-importing an id-less file duplicates rather than updates. Bad rows
    /// (empty name, non-UUID id) are skipped individually, never abort the batch.
    public static func run(_ inputs: [MemberBulkInput], client: CloudKitS2SClient) async -> MemberBulkImportResult {
        var result = MemberBulkImportResult()
        for input in inputs {
            let firstName = (input.firstName ?? "").trimmingCharacters(in: .whitespaces)
            let lastName = (input.lastName ?? "").trimmingCharacters(in: .whitespaces)
            let fullName = [firstName, lastName].filter { !$0.isEmpty }.joined(separator: " ")
            guard !firstName.isEmpty, !lastName.isEmpty else {
                result.failed += 1
                result.messages.append("Skipped an entry with an empty firstName or lastName.")
                continue
            }

            let recordName: String
            if let providedID = input.id {
                guard UUID(uuidString: providedID) != nil else {
                    result.failed += 1
                    result.messages.append("Skipped \(fullName): id '\(providedID)' is not a valid UUID.")
                    continue
                }
                recordName = providedID
            } else {
                recordName = UUID().uuidString
            }

            let record = MemberRecord(
                id: recordName,
                firstName: firstName,
                lastName: lastName,
                street: input.street ?? "",
                zip: input.zip ?? "",
                city: input.city ?? "",
                email: input.email ?? "",
                phone: input.phone ?? "",
                memberNumber: input.memberNumber ?? "",
                joinedAt: parseJoinedAt(input.joinedAt) ?? Date(),
                notes: input.notes ?? "",
                gender: input.gender ?? "",
                title: input.title ?? "",
                birthDate: parseFlexibleDate(input.birthDate),
                sportId: input.sportId ?? "",
                svnr: input.svnr ?? "",
                iban: input.iban ?? "",
                lastMedicalExamination: parseFlexibleDate(input.lastMedicalExamination),
                defaultFunction: input.defaultFunction ?? "",
                memberOfGVSC: input.memberOfGVSC ?? true
            )

            do {
                try await client.createOrReplaceRecord(recordType: "ClubMember", recordName: recordName, fields: record.ckFields)
                result.succeeded += 1
                result.messages.append("Imported \(fullName) (\(recordName))")
            } catch {
                result.failed += 1
                result.messages.append("Failed to import \(fullName): \(error)")
            }
        }
        return result
    }

    /// Accepts "yyyy-MM-dd" or full ISO8601; nil (caller defaults to "now")
    /// rather than throwing, so one malformed date doesn't sink the batch.
    public static func parseJoinedAt(_ raw: String?) -> Date? {
        guard let raw, !raw.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        if let date = ISO8601DateFormatter().date(from: raw) { return date }
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "yyyy-MM-dd"
        dayFormatter.timeZone = TimeZone(identifier: "UTC")
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        return dayFormatter.date(from: raw)
    }

    /// Accepts ISO8601, "yyyy-MM-dd", or "dd.MM.yyyy" — used for
    /// `birthDate`/`lastMedicalExamination`, which show up in the club's real
    /// source roster files in the German "dd.MM.yyyy" convention, mixed with
    /// a few ISO dates.
    public static func parseFlexibleDate(_ raw: String?) -> Date? {
        guard let raw, !raw.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        if let date = parseJoinedAt(raw) { return date }
        let dotFormatter = DateFormatter()
        dotFormatter.dateFormat = "dd.MM.yyyy"
        dotFormatter.timeZone = TimeZone(identifier: "UTC")
        dotFormatter.locale = Locale(identifier: "en_US_POSIX")
        return dotFormatter.date(from: raw)
    }
}
