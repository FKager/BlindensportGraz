import Foundation
import SwiftData

/// JSON shape for one roster member, shared by export and import. Field names
/// intentionally match RootCLI's `MemberBulkInput`/`members.example.json` and
/// `clubmembersapi`'s REST payloads exactly, so a file exported here can be
/// fed to `rootcli import-members` (or vice versa) with no conversion.
/// `joinedAt`/`birthDate`/`lastMedicalExamination` are plain strings (not
/// native JSON dates) accepting ISO8601, "yyyy-MM-dd", or "dd.MM.yyyy" —
/// see `MemberImportExport.parseFlexibleDate`. `zip` also accepts the
/// German "plz" (Postleitzahl) as an alias key, since the club's source
/// roster files (data/Person-*.json) use that spelling in a few places.
struct MemberIO: Codable {
    var id: String?
    var firstName: String?
    var lastName: String?
    var street: String?
    var zip: String?
    var city: String?
    var country: String?
    var email: String?
    var phone: String?
    var memberNumber: String?
    var joinedAt: String?
    var notes: String?
    var gender: String?
    var title: String?
    var birthDate: String?
    var sportId: String?
    var svnr: String?
    var iban: String?
    var lastMedicalExamination: String?
    var defaultFunction: String?
    var memberOfGVSC: Bool?

    private enum CodingKeys: String, CodingKey {
        case id, firstName, lastName, street, zip, plz, city, country, email, phone, memberNumber, joinedAt, notes,
             gender, title, birthDate, sportId, svnr, iban, lastMedicalExamination, defaultFunction, memberOfGVSC
    }

    init(id: String? = nil, firstName: String? = nil, lastName: String? = nil, street: String? = nil,
         zip: String? = nil, city: String? = nil, country: String? = nil, email: String? = nil, phone: String? = nil,
         memberNumber: String? = nil, joinedAt: String? = nil, notes: String? = nil,
         gender: String? = nil, title: String? = nil, birthDate: String? = nil, sportId: String? = nil,
         svnr: String? = nil, iban: String? = nil, lastMedicalExamination: String? = nil,
         defaultFunction: String? = nil, memberOfGVSC: Bool? = nil) {
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

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        firstName = try container.decodeIfPresent(String.self, forKey: .firstName)
        lastName = try container.decodeIfPresent(String.self, forKey: .lastName)
        street = try container.decodeIfPresent(String.self, forKey: .street)
        zip = try container.decodeIfPresent(String.self, forKey: .zip)
            ?? container.decodeIfPresent(String.self, forKey: .plz)
        city = try container.decodeIfPresent(String.self, forKey: .city)
        country = try container.decodeIfPresent(String.self, forKey: .country)
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

    // Written explicitly (rather than relying on synthesis) because the
    // `plz` alias case in CodingKeys has no backing stored property, which
    // blocks Swift's automatic Encodable synthesis for this type. Always
    // writes `zip`, never `plz` — the alias only matters for decoding.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encodeIfPresent(firstName, forKey: .firstName)
        try container.encodeIfPresent(lastName, forKey: .lastName)
        try container.encodeIfPresent(street, forKey: .street)
        try container.encodeIfPresent(zip, forKey: .zip)
        try container.encodeIfPresent(city, forKey: .city)
        try container.encodeIfPresent(country, forKey: .country)
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

enum MemberImportExport {
    private static let isoFormatter = ISO8601DateFormatter()

    // MARK: - Export

    /// Encodes the given roster to pretty-printed, sorted-key JSON and writes
    /// it to a fresh temp file, ready for `ShareLink`.
    static func exportFile(members: [Member]) throws -> URL {
        let data = try encodedJSON(for: members)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("grazer-vsc-mitglieder-\(dateStamp()).json")
        try data.write(to: url, options: .atomic)
        return url
    }

    /// Same pretty-printed, sorted-key JSON `MemberIO` encoding used by
    /// `exportFile` — pulled out so `MemberBackup`'s automatic snapshots use
    /// the exact same serialization instead of a second, hand-maintained copy
    /// of the field-by-field `MemberIO` construction that could silently
    /// drift out of sync with it.
    static func encodedJSON(for members: [Member]) throws -> Data {
        let rows = members
            .sorted { ($0.lastName, $0.firstName) < ($1.lastName, $1.firstName) }
            .map { member in
                MemberIO(
                    id: member.id.uuidString,
                    firstName: member.firstName,
                    lastName: member.lastName,
                    street: member.street,
                    zip: member.zip,
                    city: member.city,
                    country: member.country,
                    email: member.email,
                    phone: member.phone,
                    memberNumber: member.memberNumber,
                    joinedAt: isoFormatter.string(from: member.joinedAt),
                    notes: member.notes,
                    gender: member.gender,
                    title: member.title,
                    birthDate: member.birthDate.map(isoFormatter.string(from:)),
                    sportId: member.sportId,
                    svnr: member.svnr,
                    iban: member.iban,
                    lastMedicalExamination: member.lastMedicalExamination.map(isoFormatter.string(from:)),
                    defaultFunction: member.defaultFunction,
                    memberOfGVSC: member.memberOfGVSC
                )
            }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(rows)
    }

    private static func dateStamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: Date())
    }

    // MARK: - Import

    struct ImportResult {
        var created = 0
        var updated = 0
        var skipped = 0
        var skippedDetails: [String] = []

        var summary: String {
            var lines = ["\(created) neu angelegt, \(updated) aktualisiert, \(skipped) übersprungen."]
            if !skippedDetails.isEmpty {
                lines.append("")
                lines.append(contentsOf: skippedDetails)
            }
            return lines.joined(separator: "\n")
        }
    }

    /// Parses `data` as a JSON array of `MemberIO`, then for each entry:
    /// matches an existing roster entry by `id` first (if given and valid —
    /// this is what makes re-importing a previously exported file idempotent),
    /// falling back to email or first+last name (same rule as
    /// `Member.checkMembership`'s account matching), and either updates
    /// that entry in place or inserts a new `Member`. Entries missing
    /// firstName/lastName are skipped, matching RootCLI's import-members
    /// behavior, so one bad row doesn't abort the whole file.
    ///
    /// Updating an existing entry is non-destructive: a field is only filled
    /// in when it's currently blank on the existing record AND the incoming
    /// row has a non-empty value for it — existing data is never overwritten
    /// or blanked out by an empty/absent value in the file. This mirrors
    /// RootCLI's `MemberFillUpdate` (see cerebrum.md 2026-08-01), so
    /// re-importing an updated/extended roster export in-app behaves the same
    /// way the CLI's `update-members` does. `memberOfGVSC` is a Bool with no
    /// "blank" state, so it's only set on creation (defaulting true), never
    /// touched by an update to an existing entry — flip it explicitly via the
    /// admin UI instead.
    @MainActor
    static func importMembers(from data: Data, into roster: [Member], modelContext: ModelContext) -> ImportResult {
        var result = ImportResult()
        let rows: [MemberIO]
        do {
            rows = try JSONDecoder().decode([MemberIO].self, from: data)
        } catch {
            result.skipped = 1
            result.skippedDetails = ["Datei konnte nicht gelesen werden: \(error.localizedDescription)"]
            return result
        }

        var touched: [Member] = []
        var workingRoster = roster

        for row in rows {
            let firstName = (row.firstName ?? "").trimmingCharacters(in: .whitespaces)
            let lastName = (row.lastName ?? "").trimmingCharacters(in: .whitespaces)
            guard !firstName.isEmpty, !lastName.isEmpty else {
                result.skipped += 1
                result.skippedDetails.append("Übersprungen: Eintrag ohne Vor-/Nachnamen.")
                continue
            }

            let joinedAt = parseJoinedAt(row.joinedAt) ?? Date()
            let existing = findExisting(row: row, firstName: firstName, lastName: lastName, in: workingRoster)

            let birthDate = parseFlexibleDate(row.birthDate)
            let lastMedicalExamination = parseFlexibleDate(row.lastMedicalExamination)

            if let existing {
                existing.firstName = firstName
                existing.lastName = lastName
                fillIfBlank(&existing.street, row.street)
                fillIfBlank(&existing.zip, row.zip)
                fillIfBlank(&existing.city, row.city)
                fillIfBlank(&existing.country, row.country)
                fillIfBlank(&existing.email, row.email)
                fillIfBlank(&existing.phone, row.phone)
                fillIfBlank(&existing.memberNumber, row.memberNumber)
                fillIfBlank(&existing.notes, row.notes)
                fillIfBlank(&existing.gender, row.gender)
                fillIfBlank(&existing.title, row.title)
                fillIfBlank(&existing.sportId, row.sportId)
                fillIfBlank(&existing.svnr, row.svnr)
                fillIfBlank(&existing.iban, row.iban)
                fillIfBlank(&existing.defaultFunction, row.defaultFunction)
                if existing.birthDate == nil, let birthDate { existing.birthDate = birthDate }
                if existing.lastMedicalExamination == nil, let lastMedicalExamination {
                    existing.lastMedicalExamination = lastMedicalExamination
                }
                touched.append(existing)
                result.updated += 1
            } else {
                let id = row.id.flatMap(UUID.init) ?? UUID()
                let member = Member(
                    id: id,
                    firstName: firstName,
                    lastName: lastName,
                    street: row.street ?? "",
                    zip: row.zip ?? "",
                    city: row.city ?? "",
                    country: row.country ?? "",
                    email: row.email ?? "",
                    phone: row.phone ?? "",
                    memberNumber: row.memberNumber ?? "",
                    joinedAt: joinedAt,
                    notes: row.notes ?? "",
                    gender: row.gender ?? "",
                    title: row.title ?? "",
                    birthDate: birthDate,
                    sportId: row.sportId ?? "",
                    svnr: row.svnr ?? "",
                    iban: row.iban ?? "",
                    lastMedicalExamination: lastMedicalExamination,
                    defaultFunction: row.defaultFunction ?? "",
                    memberOfGVSC: row.memberOfGVSC ?? true
                )
                modelContext.insert(member)
                workingRoster.append(member)
                touched.append(member)
                result.created += 1
            }
        }

        MemberService.saveBatch(touched, modelContext: modelContext)
        // One snapshot for the whole batch, not per row — importing a real
        // club spreadsheet can create dozens of entries at once.
        if result.created > 0 {
            MemberBackup.snapshot(members: workingRoster)
        }
        return result
    }

    /// Sets `existing` to `newValue` only if `existing` is currently blank
    /// and `newValue` is non-empty — leaves already-set data untouched rather
    /// than overwriting or blanking it, per the "only fill what wasn't set
    /// before" import semantics (see cerebrum.md 2026-08-01).
    private static func fillIfBlank(_ existing: inout String, _ newValue: String?) {
        guard existing.trimmingCharacters(in: .whitespaces).isEmpty,
              let newValue, !newValue.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        existing = newValue
    }

    private static func findExisting(row: MemberIO, firstName: String, lastName: String, in roster: [Member]) -> Member? {
        if let idString = row.id, let id = UUID(uuidString: idString),
           let byID = roster.first(where: { $0.id == id }) {
            return byID
        }
        let normalizedEmail = (row.email ?? "").trimmingCharacters(in: .whitespaces).lowercased()
        if !normalizedEmail.isEmpty,
           let byEmail = roster.first(where: { $0.email.trimmingCharacters(in: .whitespaces).lowercased() == normalizedEmail }) {
            return byEmail
        }
        let normalizedFirst = firstName.lowercased()
        let normalizedLast = lastName.lowercased()
        return roster.first {
            $0.firstName.trimmingCharacters(in: .whitespaces).lowercased() == normalizedFirst &&
            $0.lastName.trimmingCharacters(in: .whitespaces).lowercased() == normalizedLast
        }
    }

    /// Accepts "yyyy-MM-dd" or full ISO8601; mirrors RootCLI's
    /// `MemberImport.parseJoinedAt` exactly so both tools parse the same
    /// files identically.
    private static func parseJoinedAt(_ raw: String?) -> Date? {
        guard let raw, !raw.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        if let date = isoFormatter.date(from: raw) { return date }
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "yyyy-MM-dd"
        dayFormatter.timeZone = TimeZone(identifier: "UTC")
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        return dayFormatter.date(from: raw)
    }

    /// Accepts ISO8601, "yyyy-MM-dd", or "dd.MM.yyyy" — used for
    /// `birthDate`/`lastMedicalExamination`, which (unlike `joinedAt`) show
    /// up in the club's real-world source roster files (data/Person-*.json)
    /// in the German "dd.MM.yyyy" convention, mixed with a few ISO dates.
    static func parseFlexibleDate(_ raw: String?) -> Date? {
        guard let raw, !raw.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        if let date = parseJoinedAt(raw) { return date }
        let dotFormatter = DateFormatter()
        dotFormatter.dateFormat = "dd.MM.yyyy"
        dotFormatter.timeZone = TimeZone(identifier: "UTC")
        dotFormatter.locale = Locale(identifier: "en_US_POSIX")
        return dotFormatter.date(from: raw)
    }
}
