import Foundation
import Supabase
import SwiftData

// Sensitive roster fields that no longer travel through the CloudKit public
// database. Readable with members.private.read, writable with
// members.private.write (admin/root) — enforced by RLS.
nonisolated struct MemberPrivateData: Codable, Hashable {
    var memberID: UUID
    var svnr: String = ""
    var iban: String = ""
    var birthDate: Date?
    var lastMedicalExamination: Date?

    enum CodingKeys: String, CodingKey {
        case svnr, iban
        case memberID               = "member_id"
        case birthDate              = "birth_date"
        case lastMedicalExamination = "last_medical_examination"
    }

    // Postgres `date` columns: send/receive plain yyyy-MM-dd so no time zone
    // shift can move a birthday by a day.
    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    init(memberID: UUID, svnr: String = "", iban: String = "",
         birthDate: Date? = nil, lastMedicalExamination: Date? = nil) {
        self.memberID = memberID
        self.svnr = svnr
        self.iban = iban
        self.birthDate = birthDate
        self.lastMedicalExamination = lastMedicalExamination
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        memberID = try c.decode(UUID.self, forKey: .memberID)
        svnr = try c.decodeIfPresent(String.self, forKey: .svnr) ?? ""
        iban = try c.decodeIfPresent(String.self, forKey: .iban) ?? ""
        birthDate = Self.day(try c.decodeIfPresent(String.self, forKey: .birthDate))
        lastMedicalExamination = Self.day(try c.decodeIfPresent(String.self, forKey: .lastMedicalExamination))
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(memberID, forKey: .memberID)
        try c.encode(svnr, forKey: .svnr)
        try c.encode(iban, forKey: .iban)
        try c.encode(birthDate.map(Self.dayString), forKey: .birthDate)
        try c.encode(lastMedicalExamination.map(Self.dayString), forKey: .lastMedicalExamination)
    }

    // Calendar-day conversion in the user's calendar <-> UTC yyyy-MM-dd.
    static func dayString(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func day(_ string: String?) -> Date? {
        guard let string, let utc = dayFormatter.date(from: string) else { return nil }
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(identifier: "UTC")!
        let parts = utcCalendar.dateComponents([.year, .month, .day], from: utc)
        return Calendar.current.date(from: parts)
    }
}

@MainActor
enum SupabaseMemberPrivateService {

    private static var client: SupabaseClient { SupabaseClientSingleton.shared.client }

    static func fetch(memberID: UUID) async throws -> MemberPrivateData? {
        let rows: [MemberPrivateData] = try await client
            .from("member_private")
            .select()
            .eq("member_id", value: memberID.uuidString)
            .limit(1)
            .execute()
            .value
        return rows.first
    }

    static func fetchAll() async throws -> [MemberPrivateData] {
        try await client.from("member_private").select().execute().value
    }

    static func upsert(_ data: MemberPrivateData) async throws {
        try await client
            .from("member_private")
            .upsert(data, onConflict: "member_id")
            .execute()
    }

    static func delete(memberID: UUID) async throws {
        try await client
            .from("member_private")
            .delete()
            .eq("member_id", value: memberID.uuidString)
            .execute()
    }

    // MARK: - Change proposals (member → admin review)

    // The member's own proposal for their approved roster entry (RLS).
    static func submitRequest(_ data: MemberPrivateData) async throws {
        try await client
            .from("member_private_requests")
            .upsert(data, onConflict: "member_id")
            .execute()
    }

    static func fetchRequest(memberID: UUID) async throws -> MemberPrivateData? {
        let rows: [MemberPrivateData] = try await client
            .from("member_private_requests")
            .select("member_id, svnr, iban, birth_date, last_medical_examination")
            .eq("member_id", value: memberID.uuidString)
            .limit(1)
            .execute()
            .value
        return rows.first
    }

    static func applyRequest(memberID: UUID) async throws {
        nonisolated struct Params: Encodable { let p_member_id: UUID }
        try await client
            .rpc("apply_member_private_request", params: Params(p_member_id: memberID))
            .execute()
    }

    static func deleteRequest(memberID: UUID) async throws {
        try await client
            .from("member_private_requests")
            .delete()
            .eq("member_id", value: memberID.uuidString)
            .execute()
    }

    // Fills the local Member cache for permitted devices; wipes it everywhere
    // else so no device keeps sensitive data it may not read.
    static func applyToLocal(_ rows: [MemberPrivateData]?, modelContext: ModelContext) {
        let byID = Dictionary((rows ?? []).map { ($0.memberID, $0) }, uniquingKeysWith: { a, _ in a })
        let members = (try? modelContext.fetch(FetchDescriptor<Member>())) ?? []
        for member in members {
            let data = byID[member.id]
            member.svnr = data?.svnr ?? ""
            member.iban = data?.iban ?? ""
            member.birthDate = data?.birthDate
            member.lastMedicalExamination = data?.lastMedicalExamination
        }
        try? modelContext.save()
    }

    static func data(from member: Member) -> MemberPrivateData {
        MemberPrivateData(memberID: member.id, svnr: member.svnr, iban: member.iban,
                          birthDate: member.birthDate,
                          lastMedicalExamination: member.lastMedicalExamination)
    }
}
