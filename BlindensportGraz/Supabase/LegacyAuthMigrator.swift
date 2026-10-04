import Foundation
import Supabase
import SwiftData

// One-way migration bridge for users registered before Supabase.
//
// Strategy:
//   1. Caller already has the local User (email match from SwiftData).
//   2. Verify the supplied password against the HMAC-SHA256 hash still
//      sitting in User.passwordHash / passwordSalt (written by the old
//      CloudKit sync path).
//   3. On success, create a Supabase Auth account with the same email + password.
//   4. Create the profiles row via the SECURITY DEFINER create_profile RPC.
//   5. Clear passwordHash / passwordSalt from the local User and push the
//      updated UserIdentity to CloudKit so other devices don't keep offering
//      the legacy path for this account.
//
// If Supabase already has an account for this email (migrated on another
// device), attempt a normal signIn instead.
@MainActor
enum LegacyAuthMigrator {

    enum MigrationResult {
        case migrated(Session)
        case alreadyMigrated(Session)
        // signUp succeeded but auto-confirm is off — user must click the email link.
        case pendingEmailConfirmation
        case wrongPassword
        case networkError(Error)
    }

    static func attemptMigration(
        user: User,
        password: String,
        modelContext: ModelContext
    ) async -> MigrationResult {
        // Read all model properties on @MainActor before any await so we
        // never cross an actor boundary with a live @Model reference.
        let email     = user.email
        let hash      = user.passwordHash
        let salt      = user.passwordSalt
        let firstName = user.firstName
        let lastName  = user.lastName
        let userID    = user.id

        guard PasswordHashing.verify(password: password,
                                     salt: salt,
                                     expectedHash: hash) else {
            return .wrongPassword
        }

        do {
            let response = try await SupabaseAuthService.signUp(
                email: email, password: password)
            try await SupabaseProfileService.createProfile(
                userID: userID,
                email: email,
                firstName: firstName,
                lastName: lastName)

            user.passwordHash = ""
            user.passwordSalt = ""
            UserService.save(user, modelContext: modelContext)

            if let session = response.session {
                return .migrated(session)
            }
            return .pendingEmailConfirmation

        } catch {
            if isUserAlreadyExistsError(error) {
                do {
                    let session = try await SupabaseAuthService.signIn(
                        email: email, password: password)
                    // Also clear the stale hash so this branch never fires again.
                    user.passwordHash = ""
                    user.passwordSalt = ""
                    UserService.save(user, modelContext: modelContext)
                    return .alreadyMigrated(session)
                } catch let signInError {
                    return .networkError(signInError)
                }
            }
            return .networkError(error)
        }
    }

    // Supabase returns a 422 with "User already registered" when signUp is
    // called for an existing email address.
    private static func isUserAlreadyExistsError(_ error: Error) -> Bool {
        let msg = error.localizedDescription.lowercased()
        return msg.contains("already registered")
            || msg.contains("already exists")
            || msg.contains("email address is already taken")
    }
}
