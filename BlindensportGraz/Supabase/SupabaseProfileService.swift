import Foundation
import Supabase
import SwiftData

// Wire shape for the Supabase `profiles` table.
// nonisolated so JSONDecoder can call init(from:) from any executor
// (same pattern as Models/*.swift under SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor).
nonisolated struct SupabaseProfile: Codable {
    let id: UUID
    let supabaseUID: UUID?
    let email: String
    let firstName: String
    let lastName: String
    let role: String
    let isRoot: Bool
    let isGVSCMember: Bool
    let calendarToken: String
    let legacyMigrated: Bool

    enum CodingKeys: String, CodingKey {
        case id, email, role
        case supabaseUID    = "supabase_uid"
        case firstName      = "first_name"
        case lastName       = "last_name"
        case isRoot         = "is_root"
        case isGVSCMember   = "is_gvsc_member"
        case calendarToken  = "calendar_token"
        case legacyMigrated = "legacy_migrated"
    }
}

@MainActor
enum SupabaseProfileService {

    // Called right after signUp — inserts via the SECURITY DEFINER
    // `create_profile` RPC so the insert-forbidden RLS policy is bypassed
    // only through trusted server-side SQL. First account gets role=admin
    // and is_root=true (handled inside the function).
    static func createProfile(
        userID: UUID,
        email: String,
        firstName: String,
        lastName: String
    ) async throws {
        nonisolated struct Params: Encodable {
            let p_id: String
            let p_email: String
            let p_first_name: String
            let p_last_name: String
        }
        try await SupabaseClientSingleton.shared.client
            .rpc("create_profile", params: Params(
                p_id: userID.uuidString,
                p_email: email,
                p_first_name: firstName,
                p_last_name: lastName
            ))
            .execute()
    }

    static func fetchProfile(userID: UUID) async throws -> SupabaseProfile? {
        try? await SupabaseClientSingleton.shared.client
            .from("profiles")
            .select()
            .eq("id", value: userID.uuidString)
            .limit(1)
            .single()
            .execute()
            .value
    }

    static func fetchAllProfiles() async throws -> [SupabaseProfile] {
        try await SupabaseClientSingleton.shared.client
            .from("profiles")
            .select()
            .execute()
            .value
    }

    // Updates non-privileged profile fields. Role / isRoot changes go only
    // through SupabaseRoleService (RLS prevents self-promotion).
    static func upsertProfile(_ user: User) async throws {
        // Read all model properties on @MainActor before the await so we
        // never cross an actor boundary with a live @Model reference.
        let profile = SupabaseProfile(
            id: user.id,
            supabaseUID: nil,
            email: user.email,
            firstName: user.firstName,
            lastName: user.lastName,
            role: user.role.rawValue,
            isRoot: user.isRoot,
            isGVSCMember: user.isGrazerVSCMember,
            calendarToken: user.calendarToken,
            legacyMigrated: true
        )
        try await SupabaseClientSingleton.shared.client
            .from("profiles")
            .upsert(profile, onConflict: "id")
            .execute()
    }

    // Writes a remote profile into the local SwiftData store.
    // Called during syncAll. Never touches role/isRoot — those come from
    // SupabaseRoleService after profiles are applied.
    static func applyToLocalUser(_ profile: SupabaseProfile, modelContext: ModelContext) {
        var descriptor = FetchDescriptor<User>(
            predicate: #Predicate { $0.id == profile.id })
        descriptor.fetchLimit = 1
        if let existing = try? modelContext.fetch(descriptor).first {
            existing.firstName         = profile.firstName
            existing.lastName          = profile.lastName
            existing.email             = profile.email
            existing.isGrazerVSCMember = profile.isGVSCMember
            existing.calendarToken     = profile.calendarToken
        } else {
            let user = User(
                id: profile.id,
                email: profile.email,
                firstName: profile.firstName,
                lastName: profile.lastName,
                role: AppRole.normalize(profile.role),
                isGrazerVSCMember: profile.isGVSCMember,
                isRoot: profile.isRoot
            )
            user.calendarToken = profile.calendarToken
            modelContext.insert(user)
        }
    }
}
