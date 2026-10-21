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

    /// Every row, keyed by uppercased member id (CloudKit record names are
    /// uppercase UUIDs, Postgres returns lowercase).
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

    /// Puts back what was stored before a write whose CloudKit half then
    /// failed (`previous` nil = there was no row). Best effort: the CloudKit
    /// error is what the caller reports.
    public func restore(memberID: String, previous: MemberPrivate?) async {
        if let previous {
            try? await save(memberID: memberID, previous)
        } else {
            try? await delete(memberID: memberID)
        }
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

/// Guard for the generic record tool (`rootcli record set`): protected member fields and the account record types
/// moved to Supabase in v0.2.0 and must not be written to CloudKit again.
public enum CloudKitWriteGuard {
    static let memberTypes: Set<String> = ["ClubMember", "MemberChangeRequest"]
    static let retiredTypes: Set<String> = ["UserIdentity", "RoleAssignment", "AccountApproval", "RoleChangeLog"]

    /// Throws if writing `fieldNames` to `recordType` would put data back
    /// into CloudKit that now lives in Supabase.
    public static func check(recordType: String, fieldNames: some Sequence<String>) throws {
        if retiredTypes.contains(recordType) {
            throw CLIError.message("\(recordType) is no longer stored in CloudKit — accounts, roles and approvals live in Supabase.")
        }
        if memberTypes.contains(recordType) {
            let blocked = Set(fieldNames).intersection(MemberPrivate.fieldNames)
            if !blocked.isEmpty {
                throw CLIError.message("\(blocked.sorted().joined(separator: ", ")) must not be stored in CloudKit — protected member data lives in Supabase (member_private).")
            }
        }
    }
}
