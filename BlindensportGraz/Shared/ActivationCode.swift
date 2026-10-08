import Foundation

/// One-time codes an admin hands to a member (generated, hashed and checked
/// server-side by `create_activation_code` / `redeem_activation_code`).
/// Eight characters from an alphabet without look-alikes (no 0/O, 1/I/L),
/// shown as "ABCD-EFGH"; entry ignores case, spaces and dashes.
enum ActivationCode {
    static func normalized(_ input: String) -> String {
        input.uppercased().filter { $0.isLetter || $0.isNumber }
    }
}
