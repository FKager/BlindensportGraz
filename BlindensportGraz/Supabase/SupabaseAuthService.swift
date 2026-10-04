import CryptoKit
import Foundation
import Supabase

@MainActor
enum SupabaseAuthService {

    // MARK: - Session

    static var currentSession: Session? {
        get async { try? await SupabaseClientSingleton.shared.client.auth.session }
    }

    // Async stream of auth state changes. Consume with:
    //   for await (event, session) in SupabaseAuthService.authStateChanges { … }
    // Drive RootView's session logic from here (replaces @AppStorage restore).
    static var authStateChanges: AsyncStream<(AuthChangeEvent, Session?)> {
        SupabaseClientSingleton.shared.client.auth.authStateChanges
    }

    // MARK: - Email + password

    @discardableResult
    static func signUp(email: String, password: String) async throws -> AuthResponse {
        try await SupabaseClientSingleton.shared.client.auth.signUp(
            email: email, password: password
        )
    }

    static func signIn(email: String, password: String) async throws -> Session {
        try await SupabaseClientSingleton.shared.client.auth.signIn(
            email: email, password: password
        )
    }

    static func resetPassword(email: String) async throws {
        try await SupabaseClientSingleton.shared.client.auth
            .resetPasswordForEmail(email)
    }

    // Updates the signed-in user's password via Supabase Auth.
    // Requires an active session (call from SetPasswordView for migrated users).
    static func updatePassword(_ newPassword: String) async throws {
        try await SupabaseClientSingleton.shared.client.auth
            .update(user: UserAttributes(password: newPassword))
    }

    // MARK: - Sign in with Apple (OIDC nonce flow)

    static func signInWithApple(idToken: String, nonce: String) async throws -> Session {
        try await SupabaseClientSingleton.shared.client.auth.signInWithIdToken(
            credentials: OpenIDConnectCredentials(
                provider: .apple,
                idToken: idToken,
                nonce: nonce
            )
        )
    }

    // MARK: - Lifecycle

    static func signOut() async throws {
        try await SupabaseClientSingleton.shared.client.auth.signOut()
    }

    // Calls the `delete-account` Edge Function which invokes admin.deleteUser().
    // The function must be deployed to the Supabase project separately.
    static func deleteAccount() async throws {
        try await SupabaseClientSingleton.shared.client.functions
            .invoke("delete-account")
    }

    // MARK: - Nonce helpers for Apple OIDC

    // Generates (rawNonce, hashedNonce) for the Apple OIDC flow.
    // Pass `hashedNonce` as the nonce in the Apple ASAuthorizationRequest;
    // pass `rawNonce` to signInWithApple(idToken:nonce:).
    static func generateNonce() -> (raw: String, hashed: String) {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let raw = bytes.map { String(format: "%02x", $0) }.joined()
        let hashed = SHA256.hash(data: Data(raw.utf8))
            .map { String(format: "%02x", $0) }.joined()
        return (raw, hashed)
    }
}
