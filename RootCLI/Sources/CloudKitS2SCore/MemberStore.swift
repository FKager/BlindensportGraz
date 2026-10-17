import Foundation
import ClubSchema

/// The club roster in Supabase (v0.3.0): `members` (names, readable by every
/// approved account), `member_contacts` (address/contact, members.manage)
/// and `member_private` (svnr/iban/dates, members.private.*). Uses the
/// service key, so only root-run tooling (rootcli) may call it. The web
/// admin (webadmin/, Java) has its own port that acts as the signed-in admin.
///
/// No transaction spans the three tables. A save writes `members` first
/// (the row the others reference), so a failure part-way leaves at most a
/// name without contact data, and every write is an idempotent upsert —
/// repeating the request completes it.
public struct MemberStore: Sendable {
    let supabase: SupabaseAdminClient
    public let privateStore: MemberPrivateStore

    public init(supabase: SupabaseAdminClient) {
        self.supabase = supabase
        self.privateStore = MemberPrivateStore(supabase: supabase)
    }

    /// Every roster entry, sorted by last then first name. Protected fields
    /// stay empty unless `includePrivate`.
    public func all(includePrivate: Bool) async throws -> [MemberRecord] {
        async let members = supabase.select(table: "members", columns: Self.memberColumns)
        async let contacts = supabase.select(table: "member_contacts", columns: Self.contactColumns)
        let privateData = includePrivate ? try await privateStore.all() : [:]
        let contactsByID = Dictionary(try await contacts.compactMap { row in
            (row["id"] as? String).map { ($0.lowercased(), row) }
        }, uniquingKeysWith: { first, _ in first })
        return try await members.compactMap { row -> MemberRecord? in
            guard let id = (row["id"] as? String)?.lowercased() else { return nil }
            var record = MemberRecord(member: row, contact: contactsByID[id] ?? [:])
            record.privateData = privateData[id.uppercased()] ?? MemberPrivate()
            return record
        }
        .sorted { ($0.lastName, $0.firstName) < ($1.lastName, $1.firstName) }
    }

    public func get(id: String, includePrivate: Bool) async throws -> MemberRecord? {
        guard let key = Self.key(id) else { return nil }
        let filter = [("id", "eq.\(key)")]
        guard let member = try await supabase.select(table: "members", columns: Self.memberColumns,
                                                     filters: filter).first else { return nil }
        let contact = try await supabase.select(table: "member_contacts", columns: Self.contactColumns,
                                                filters: filter).first ?? [:]
        var record = MemberRecord(member: member, contact: contact)
        if includePrivate { record.privateData = try await privateStore.get(memberID: key) ?? MemberPrivate() }
        return record
    }

    /// Insert or overwrite the entry. The protected row is written only with
    /// `writePrivate` (otherwise left as stored); `updatedBy` is the signed-in
    /// admin, nil for system tools.
    public func save(_ record: MemberRecord, writePrivate: Bool, updatedBy: UUID?) async throws {
        guard let key = Self.key(record.id) else {
            throw CLIError.message("Member id '\(record.id)' is not a UUID.")
        }
        var member = record.memberRow
        var contact = record.contactRow
        member["id"] = key
        contact["id"] = key
        if let updatedBy {
            member["updated_by"] = updatedBy.uuidString.lowercased()
            contact["updated_by"] = updatedBy.uuidString.lowercased()
        }
        try await supabase.upsert(table: "members", rows: [member], onConflict: "id")
        try await supabase.upsert(table: "member_contacts", rows: [contact], onConflict: "id")
        if writePrivate {
            try await privateStore.save(memberID: key, record.privateData, updatedBy: updatedBy)
        }
    }

    /// Removes the entry; contacts cascade, the protected row is deleted
    /// explicitly (member_private predates the members table).
    public func delete(id: String) async throws {
        guard let key = Self.key(id) else { return }
        try await supabase.delete(table: "members", filters: [("id", "eq.\(key)")])
        try await privateStore.delete(memberID: key)
    }

    static let memberColumns = "id,first_name,last_name,member_number,sport_id,default_function,member_of_gvsc,joined_at"
    static let contactColumns = "id,street,zip,city,country,email,phone,notes,gender,title"

    static func key(_ id: String) -> String? {
        UUID(uuidString: id).map { $0.uuidString.lowercased() }
    }
}

extension ClubMemberRecord {
    /// From a `members` row and its `member_contacts` row (empty if none).
    /// The id comes back uppercase, like the app's `UUID.uuidString`.
    init(member: [String: Any], contact: [String: Any]) {
        func text(_ row: [String: Any], _ key: String) -> String { row[key] as? String ?? "" }
        self.init(
            id: (member["id"] as? String ?? "").uppercased(),
            firstName: text(member, "first_name"),
            lastName: text(member, "last_name"),
            street: text(contact, "street"),
            zip: text(contact, "zip"),
            city: text(contact, "city"),
            country: text(contact, "country"),
            email: text(contact, "email"),
            phone: text(contact, "phone"),
            memberNumber: text(member, "member_number"),
            joinedAt: (member["joined_at"] as? String).flatMap(SupabaseTimestamp.parse) ?? Date(),
            notes: text(contact, "notes"),
            gender: text(contact, "gender"),
            title: text(contact, "title"),
            birthDate: nil,
            sportId: text(member, "sport_id"),
            svnr: "",
            iban: "",
            lastMedicalExamination: nil,
            defaultFunction: text(member, "default_function"),
            memberOfGVSC: member["member_of_gvsc"] as? Bool ?? true
        )
    }

    var memberRow: [String: Any] {
        ["first_name": firstName, "last_name": lastName, "member_number": memberNumber, "sport_id": sportId,
         "default_function": defaultFunction, "member_of_gvsc": memberOfGVSC,
         "joined_at": SupabaseTimestamp.format(joinedAt)]
    }

    var contactRow: [String: Any] {
        ["street": street, "zip": zip, "city": city, "country": country, "email": email, "phone": phone,
         "notes": notes, "gender": gender, "title": title]
    }
}

/// `timestamptz` as PostgREST writes it: ISO 8601 with or without
/// fractional seconds.
public enum SupabaseTimestamp {
    public static func parse(_ raw: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: raw) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: raw)
    }

    public static func format(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
