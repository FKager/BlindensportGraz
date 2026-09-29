import Foundation
import Security

/// One-time codes an admin hands to a member so they can set a password for
/// an account that doesn't have one yet (see `AccountApproval`).
/// Eight characters from an alphabet without look-alikes (no 0/O, 1/I/L),
/// shown as "ABCD-EFGH"; entry ignores case, spaces and dashes.
enum ActivationCode {
    private static let alphabet = Array("ABCDEFGHJKMNPQRSTUVWXYZ23456789")

    static func generate() -> String {
        var bytes = [UInt8](repeating: 0, count: 8)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let characters = bytes.map { alphabet[Int($0) % alphabet.count] }
        return String(characters[0..<4]) + "-" + String(characters[4..<8])
    }

    static func normalized(_ input: String) -> String {
        input.uppercased().filter { $0.isLetter || $0.isNumber }
    }

    /// Whether `input` matches any activation code issued for this account
    /// by an admin/root (checked against `approvers`).
    static func matches(_ input: String, for user: User, approvals: [AccountApproval], users: [User]) -> Bool {
        let code = normalized(input)
        guard code.count == 8 else { return false }
        return approvals.contains { approval in
            approval.userID == user.id
                && !approval.activationCodeHash.isEmpty
                && AccessPolicy.isTrustedApprover(approval.approvedBy, users: users)
                && PasswordHashing.verify(password: code, salt: approval.activationCodeSalt,
                                          expectedHash: approval.activationCodeHash)
        }
    }
}
