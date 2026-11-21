import Foundation
import Supabase

/// What the password screen does after the server refused a new password.
/// The server asks for a confirmation code when the account hasn't signed
/// in for a while (Supabase `secure_password_change`), so a session left
/// signed in on a phone can't change the password on its own.
nonisolated enum PasswordChangeStep: Equatable {
    /// Mail a code and ask for it.
    case askForCode
    /// The code was wrong or expired: say so and offer a new one.
    case codeRejected
    /// Anything else: show the message.
    case failed

    static func after(_ error: Error) -> PasswordChangeStep {
        guard let auth = error as? AuthError else { return .failed }
        switch auth.errorCode {
        case .reauthenticationNeeded: return .askForCode
        case .reauthenticationNotValid: return .codeRejected
        default: return .failed
        }
    }

    /// Codes are six digits; spaces from copying are ignored.
    static func cleanedCode(_ raw: String) -> String {
        raw.filter(\.isNumber)
    }
}
