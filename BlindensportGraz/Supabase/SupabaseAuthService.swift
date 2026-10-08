import CryptoKit
import Foundation
import Supabase

@MainActor
enum SupabaseAuthService {

    private static var auth: AuthClient { SupabaseClientSingleton.shared.client.auth }

    // MARK: - Session

    static var currentSession: Session? { auth.currentSession }

    // Drives AuthContext. Emits .initialSession first, then sign-in/out,
    // token refreshes and password-recovery events.
    static var authStateChanges: AsyncStream<(event: AuthChangeEvent, session: Session?)> {
        auth.authStateChanges
    }

    static func refreshSession() async throws {
        _ = try await auth.refreshSession()
    }

    // MARK: - Email + password

    // First/last name travel as user metadata; the `on_auth_user_created`
    // trigger copies them into `profiles`. Returns nil session while the
    // email address is still unconfirmed.
    @discardableResult
    static func signUp(email: String, password: String,
                       firstName: String, lastName: String) async throws -> AuthResponse {
        try await auth.signUp(
            email: email,
            password: password,
            data: ["first_name": .string(firstName), "last_name": .string(lastName)]
        )
    }

    @discardableResult
    static func signIn(email: String, password: String) async throws -> Session {
        try await auth.signIn(email: email, password: password)
    }

    static func resetPassword(email: String) async throws {
        try await auth.resetPasswordForEmail(email)
    }

    static func updatePassword(_ newPassword: String) async throws {
        _ = try await auth.update(user: UserAttributes(password: newPassword))
    }

    // Confirmation and recovery links open blindensportgraz://auth-callback.
    static func handleDeepLink(_ url: URL) async throws {
        _ = try await auth.session(from: url)
    }

    // MARK: - Sign in with Apple (OIDC nonce flow)

    @discardableResult
    static func signInWithApple(idToken: String, nonce: String) async throws -> Session {
        try await auth.signInWithIdToken(
            credentials: OpenIDConnectCredentials(provider: .apple, idToken: idToken, nonce: nonce)
        )
    }

    // Apple sends the name only on the very first authorization.
    static func saveName(firstName: String, lastName: String, userID: UUID) async throws {
        nonisolated struct Row: Encodable { let first_name: String; let last_name: String }
        try await SupabaseClientSingleton.shared.client
            .from("profiles")
            .update(Row(first_name: firstName, last_name: lastName))
            .eq("id", value: userID.uuidString)
            .execute()
    }

    // MARK: - Lifecycle

    static func signOut() async throws {
        try await auth.signOut()
    }

    // Edge Function `delete-account` deletes the caller's auth user; all
    // public.* rows cascade. Fails with 409 for the last root account.
    static func deleteAccount() async throws {
        try await SupabaseClientSingleton.shared.client.functions.invoke(
            "delete-account", options: FunctionInvokeOptions(method: .post))
        try? await auth.signOut()
    }

    // MARK: - Nonce helpers for Apple OIDC

    // Pass `hashed` to ASAuthorizationAppleIDRequest.nonce and `raw` to
    // signInWithApple(idToken:nonce:).
    static func generateNonce() -> (raw: String, hashed: String) {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let raw = bytes.map { String(format: "%02x", $0) }.joined()
        let hashed = SHA256.hash(data: Data(raw.utf8))
            .map { String(format: "%02x", $0) }.joined()
        return (raw, hashed)
    }
}
