import AuthenticationServices
import UIKit

@MainActor
final class AppleSignInCoordinator: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    struct SignInResult {
        let userIdentifier: String
        let email: String?
        let fullName: PersonNameComponents?
        /// The signed identity token, exchanged for a Supabase session.
        let identityToken: String
    }

    private var continuation: CheckedContinuation<SignInResult, Error>?

    /// `hashedNonce` is SHA-256 of the raw nonce later sent to Supabase
    /// (`SupabaseAuthService.generateNonce`).
    func requestSignIn(hashedNonce: String) async throws -> SignInResult {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let request = ASAuthorizationAppleIDProvider().createRequest()
            request.requestedScopes = [.fullName, .email]
            request.nonce = hashedNonce
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }

    func authorizationController(controller: ASAuthorizationController,
                                  didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = credential.identityToken,
              let identityToken = String(data: tokenData, encoding: .utf8) else {
            continuation?.resume(throwing: ASAuthorizationError(.failed))
            continuation = nil
            return
        }
        continuation?.resume(returning: SignInResult(
            userIdentifier: credential.user,
            email: credential.email,
            fullName: credential.fullName,
            identityToken: identityToken
        ))
        continuation = nil
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        let windowScenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        // `UIWindow()` (no scene) is deprecated in iOS 26 — prefer the app's
        // existing key window, falling back to a fresh window tied to a real
        // scene. A window scene is guaranteed to exist here: this is only
        // ever called while presenting UI in response to a user-initiated
        // sign-in request.
        return windowScenes.compactMap { $0.keyWindow }.first
            ?? UIWindow(windowScene: windowScenes.first!)
    }
}

/// Sign in with Apple → Supabase session (OIDC id-token + nonce). Apple sends
/// the name only on the first authorization, so it is saved to the profile
/// right away when present.
@MainActor
enum AppleSupabaseSignIn {
    static func run(using coordinator: AppleSignInCoordinator) async throws {
        let nonce = SupabaseAuthService.generateNonce()
        let result = try await coordinator.requestSignIn(hashedNonce: nonce.hashed)
        let session = try await SupabaseAuthService.signInWithApple(idToken: result.identityToken, nonce: nonce.raw)
        let first = result.fullName?.givenName?.trimmingCharacters(in: .whitespaces) ?? ""
        let last = result.fullName?.familyName?.trimmingCharacters(in: .whitespaces) ?? ""
        if !first.isEmpty || !last.isEmpty {
            try? await SupabaseAuthService.saveName(firstName: first, lastName: last, userID: session.user.id)
        }
    }

    /// True when the person dismissed Apple's sheet — not an error to show.
    static func isCancellation(_ error: Error) -> Bool {
        (error as? ASAuthorizationError)?.code == .canceled
    }
}
