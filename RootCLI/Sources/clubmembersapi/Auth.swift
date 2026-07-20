import Vapor
import CryptoKit

struct APIUser: Authenticatable {}

/// Single shared username/password (API_USERNAME/API_PASSWORD env vars) —
/// intentionally not per-user accounts. This tool is operator/admin tooling
/// like RootCLI, not a member-facing login system; see Configure.swift for
/// why authentication is mandatory rather than optional here.
struct ClubMembersAuthenticator: AsyncBasicAuthenticator {
    let username: String
    let password: String

    func authenticate(basic: BasicAuthorization, for request: Request) async throws {
        guard constantTimeEquals(basic.username, username),
              constantTimeEquals(basic.password, password) else { return }
        request.auth.login(APIUser())
    }

    /// Plain `==` on the raw strings short-circuits on the first mismatched
    /// byte, leaking credential length/prefix via response timing. Hashing
    /// both sides first makes the final comparison constant-time regardless.
    private func constantTimeEquals(_ a: String, _ b: String) -> Bool {
        let hashA = SHA256.hash(data: Data(a.utf8))
        let hashB = SHA256.hash(data: Data(b.utf8))
        return hashA == hashB
    }
}
