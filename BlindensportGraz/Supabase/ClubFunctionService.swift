import Foundation
import Supabase

/// Obmann, Obmann Stellvertreter, Kassier and Schriftführer. One holder each,
/// and one member may hold several. They record a position and give no rights.
nonisolated enum ClubFunction: String, CaseIterable, Identifiable, Sendable {
    case obmann
    case obmannStellvertreter = "obmann_stellvertreter"
    case kassier
    case schriftfuehrer

    var id: String { rawValue }

    var label: String {
        switch self {
        case .obmann: "Obmann"
        case .obmannStellvertreter: "Obmann Stellvertreter"
        case .kassier: "Kassier"
        case .schriftfuehrer: "Schriftführer"
        }
    }
}

nonisolated struct ClubFunctionRow: Decodable, Sendable {
    let functionKey: String
    let memberID: UUID

    enum CodingKeys: String, CodingKey {
        case functionKey = "function_key"
        case memberID = "member_id"
    }
}

nonisolated struct ClubFunctionLogEntry: Decodable, Identifiable, Sendable {
    let id: Int
    let functionKey: String
    let oldName: String?
    let newName: String?
    let changedBy: UUID?
    let changedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case functionKey = "function_key"
        case oldName = "old_name"
        case newName = "new_name"
        case changedBy = "changed_by"
        case changedAt = "changed_at"
    }

    var functionLabel: String { ClubFunction(rawValue: functionKey)?.label ?? functionKey }
    var oldLabel: String { oldName ?? String(localized: "nicht besetzt") }
    var newLabel: String { newName ?? String(localized: "nicht besetzt") }
}

/// Read and written directly on the server, as the Rollen screen is an online
/// one like Rollenänderungen. `set_club_function` needs club.manage, and a
/// trigger writes the log.
@MainActor
enum ClubFunctionService {
    private static var client: SupabaseClient { SupabaseClientSingleton.shared.client }

    static func fetchHolders() async throws -> [ClubFunction: UUID] {
        let rows: [ClubFunctionRow] = try await client.from("club_functions").select().execute().value
        var holders: [ClubFunction: UUID] = [:]
        for row in rows {
            if let function = ClubFunction(rawValue: row.functionKey) { holders[function] = row.memberID }
        }
        return holders
    }

    /// `memberID` nil leaves the function vacant.
    static func set(_ function: ClubFunction, memberID: UUID?) async throws {
        nonisolated struct Params: Encodable { let p_function: String; let p_member: UUID? }
        try await client.rpc("set_club_function", params: Params(p_function: function.rawValue, p_member: memberID)).execute()
    }

    static func fetchLog(limit: Int = 200) async throws -> [ClubFunctionLogEntry] {
        try await client.from("club_function_log").select()
            .order("changed_at", ascending: false).limit(limit).execute().value
    }
}
