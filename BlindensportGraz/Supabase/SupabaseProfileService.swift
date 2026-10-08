import Foundation
import Supabase
import SwiftData

// Wire shape of `profiles` joined with the caller-visible role/approval.
// nonisolated so JSONDecoder can call init(from:) from any executor.
nonisolated struct SupabaseProfile: Codable, Identifiable, Hashable {
    let id: UUID
    let email: String
    let firstName: String
    let lastName: String
    let isGVSCMember: Bool
    let calendarToken: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, email
        case firstName     = "first_name"
        case lastName      = "last_name"
        case isGVSCMember  = "is_gvsc_member"
        case calendarToken = "calendar_token"
        case createdAt     = "created_at"
    }

    var displayName: String {
        let name = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? email : name
    }
}

@MainActor
enum SupabaseProfileService {

    private static var client: SupabaseClient { SupabaseClientSingleton.shared.client }

    // Own profile for every user; all profiles for users.approve (RLS).
    static func fetchProfile(userID: UUID) async throws -> SupabaseProfile? {
        let rows: [SupabaseProfile] = try await client
            .from("profiles")
            .select()
            .eq("id", value: userID.uuidString)
            .limit(1)
            .execute()
            .value
        return rows.first
    }

    static func fetchAllProfiles() async throws -> [SupabaseProfile] {
        try await client
            .from("profiles")
            .select()
            .order("last_name")
            .execute()
            .value
    }

    nonisolated struct DirectoryEntry: Decodable {
        let id: UUID
        let first_name: String
        let last_name: String
        let created_at: Date
    }

    // Names of all accounts, for approved users (RPC `account_directory`).
    static func fetchDirectory() async throws -> [DirectoryEntry] {
        try await client.rpc("account_directory").execute().value
    }

    // Name-only local User rows so participations / team memberships of
    // other accounts resolve. Never overwrites an existing email.
    static func applyDirectory(_ entries: [DirectoryEntry], modelContext: ModelContext) {
        let users = (try? modelContext.fetch(FetchDescriptor<User>())) ?? []
        let byID = Dictionary(users.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for entry in entries {
            if let user = byID[entry.id] {
                user.firstName = entry.first_name
                user.lastName = entry.last_name
            } else {
                let user = User(id: entry.id, email: "", firstName: entry.first_name, lastName: entry.last_name)
                user.createdAt = entry.created_at
                modelContext.insert(user)
            }
        }
        try? modelContext.save()
    }

    // Only first/last name are client-writable (column grants).
    static func updateName(userID: UUID, firstName: String, lastName: String) async throws {
        try await SupabaseAuthService.saveName(firstName: firstName, lastName: lastName, userID: userID)
    }

    static func rotateCalendarToken() async throws -> String {
        try await client.rpc("rotate_calendar_token").execute().value
    }

    // Keeps the local SwiftData `User` as a cache keyed by the auth uid, so
    // team memberships / participations (CloudKit) keep resolving.
    // Role and approval are not stored here — AuthContext owns them.
    @discardableResult
    static func applyToLocalUser(_ profile: SupabaseProfile, role: AppRole?,
                                 modelContext: ModelContext) -> User {
        let id = profile.id
        var descriptor = FetchDescriptor<User>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        let user: User
        if let existing = try? modelContext.fetch(descriptor).first {
            user = existing
        } else {
            user = User(id: profile.id, email: profile.email,
                        firstName: profile.firstName, lastName: profile.lastName)
            modelContext.insert(user)
        }
        user.email             = profile.email
        user.firstName         = profile.firstName
        user.lastName          = profile.lastName
        user.isGrazerVSCMember = profile.isGVSCMember
        user.calendarToken     = profile.calendarToken
        user.role              = role ?? .member
        user.isRoot            = role == .root
        user.passwordHash      = ""
        user.passwordSalt      = ""
        try? modelContext.save()
        return user
    }
}
