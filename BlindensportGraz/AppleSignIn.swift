import AuthenticationServices
import UIKit

@MainActor
final class AppleSignInCoordinator: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    struct SignInResult {
        let userIdentifier: String
        let email: String?
        let fullName: PersonNameComponents?
    }

    private var continuation: CheckedContinuation<SignInResult, Error>?

    func requestSignIn() async throws -> SignInResult {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let request = ASAuthorizationAppleIDProvider().createRequest()
            request.requestedScopes = [.fullName, .email]
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }

    func authorizationController(controller: ASAuthorizationController,
                                  didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            continuation?.resume(throwing: ASAuthorizationError(.failed))
            continuation = nil
            return
        }
        continuation?.resume(returning: SignInResult(
            userIdentifier: credential.user,
            email: credential.email,
            fullName: credential.fullName
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
