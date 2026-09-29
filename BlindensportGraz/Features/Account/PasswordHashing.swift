import CryptoKit
import Foundation
import Security

/// Best-effort password hashing for a small trusted-club app with no backend
/// server (matches Validation.swift's own "advisory, not strict" tone) —
/// NOT production-grade auth. `email`/`passwordHash`/`passwordSalt` sync via
/// CloudKit's *public* database (see CloudKitSync.swift's doc comment),
/// technically readable by anyone holding valid API credentials for this
/// container; this only deters casual/opportunistic access. There is no
/// server-side rate limiting, no PBKDF2/scrypt/Argon2 (unavailable in
/// CryptoKit), and no email verification — see RootView's LoginView
/// "Passwort festlegen" migration path for the resulting known trust gap on
/// pre-refactor accounts.
enum PasswordHashing {
    /// 16 random bytes, base64-encoded, unique per user — used as the HMAC
    /// key below so two users with the same password never produce the same
    /// stored hash, and a precomputed table against unsalted SHA256 is
    /// useless.
    static func makeSalt() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
    }

    /// HMAC-SHA256(key: salt, message: password) — using the salt as the MAC
    /// key avoids hand-rolled byte concatenation while staying salted
    /// per-user. Deterministic and fast (not a slow/memory-hard KDF) —
    /// acceptable only under this file's top doc-comment caveat.
    static func hash(password: String, salt: String) -> String {
        let key = SymmetricKey(data: Data(salt.utf8))
        let mac = HMAC<SHA256>.authenticationCode(for: Data(password.utf8), using: key)
        return Data(mac).base64EncodedString()
    }

    static func verify(password: String, salt: String, expectedHash: String) -> Bool {
        hash(password: password, salt: salt) == expectedHash
    }
}
