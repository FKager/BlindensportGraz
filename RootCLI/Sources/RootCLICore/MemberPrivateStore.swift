import Foundation

/// The protected part of a roster entry — SVNR, IBAN, birth date, last
/// medical examination. They live in Supabase `public.member_private`
/// (keyed by the member id), readable only with members.private.read.
public struct MemberPrivate: Equatable, Sendable {
    public var svnr: String
    public var iban: String
    public var birthDate: Date?
    public var lastMedicalExamination: Date?

    public static let fieldNames: Set<String> = ["svnr", "iban", "birthDate", "lastMedicalExamination"]

    public init(svnr: String = "", iban: String = "", birthDate: Date? = nil, lastMedicalExamination: Date? = nil) {
        self.svnr = svnr
        self.iban = iban
        self.birthDate = birthDate
        self.lastMedicalExamination = lastMedicalExamination
    }

    public var isEmpty: Bool {
        svnr.isEmpty && iban.isEmpty && birthDate == nil && lastMedicalExamination == nil
    }

    /// Supabase row (without `member_id`). Dates are calendar days as the
    /// club sees them (Europe/Vienna), matching `rootcli supabase-migrate`.
    func row(updatedBy: UUID?) -> [String: Any] {
        var row: [String: Any] = [
            "svnr": svnr, "iban": iban,
            "birth_date": birthDate.map(Self.day) ?? NSNull(),
            "last_medical_examination": lastMedicalExamination.map(Self.day) ?? NSNull()
        ]
        if let updatedBy { row["updated_by"] = updatedBy.uuidString.lowercased() }
        return row
    }

    init(row: [String: Any]) {
        self.init(svnr: row["svnr"] as? String ?? "",
                  iban: row["iban"] as? String ?? "",
                  birthDate: (row["birth_date"] as? String).flatMap(Self.date),
                  lastMedicalExamination: (row["last_medical_examination"] as? String).flatMap(Self.date))
    }

    static func day(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Vienna")!
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }

    /// "yyyy-MM-dd" → midnight UTC, the same instant `MemberBulkImport`
    /// produces for a date-only input, so a read-modify-write round trip
    /// keeps the day.
    static func date(_ day: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.date(from: day)
    }
}

/// Reads and writes `member_private` with the service key. Only trusted
/// tooling holds that key (rootcli, run by root).
public struct MemberPrivateStore: Sendable {
    let supabase: SupabaseAdminClient

    public init(supabase: SupabaseAdminClient) {
        self.supabase = supabase
    }

    /// Every row, keyed by uppercased member id (the app's UUIDs print
    /// uppercase, Postgres returns lowercase).
    public func all() async throws -> [String: MemberPrivate] {
        let rows = try await supabase.select(table: "member_private",
                                             columns: "member_id,svnr,iban,birth_date,last_medical_examination")
        return Dictionary(rows.compactMap { row in
            (row["member_id"] as? String).map { ($0.uppercased(), MemberPrivate(row: row)) }
        }, uniquingKeysWith: { first, _ in first })
    }

    public func get(memberID: String) async throws -> MemberPrivate? {
        guard let id = Self.key(memberID) else { return nil }
        return try await supabase.select(table: "member_private",
                                         columns: "svnr,iban,birth_date,last_medical_examination",
                                         filters: [("member_id", "eq.\(id)")]).first.map(MemberPrivate.init(row:))
    }

    /// Insert or overwrite the member's row. `updatedBy` is the signed-in
    /// admin (nil = system, e.g. rootcli).
    public func save(memberID: String, _ data: MemberPrivate, updatedBy: UUID? = nil) async throws {
        guard let id = Self.key(memberID) else {
            throw CLIError.message("Member id '\(memberID)' is not a UUID.")
        }
        var row = data.row(updatedBy: updatedBy)
        row["member_id"] = id
        try await supabase.upsert(table: "member_private", rows: [row], onConflict: "member_id")
    }

    public func delete(memberID: String) async throws {
        guard let id = Self.key(memberID) else { return }
        try await supabase.delete(table: "member_private", filters: [("member_id", "eq.\(id)")])
    }

    private static func key(_ memberID: String) -> String? {
        UUID(uuidString: memberID).map { $0.uuidString.lowercased() }
    }
}

extension MemberBulkInput {
    /// The protected fields of an import row, parsed like the rest of the row.
    public var privateData: MemberPrivate {
        MemberPrivate(svnr: (svnr ?? "").trimmingCharacters(in: .whitespaces),
                      iban: (iban ?? "").trimmingCharacters(in: .whitespaces),
                      birthDate: MemberBulkImport.parseFlexibleDate(birthDate),
                      lastMedicalExamination: MemberBulkImport.parseFlexibleDate(lastMedicalExamination))
    }
}
