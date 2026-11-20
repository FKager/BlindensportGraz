import CryptoKit
import XCTest
@testable import BlindensportGraz

/// The Sign in with Apple nonce: 32 random bytes as hex, a fresh value every
/// time, and the hashed form Apple receives is the SHA-256 of the raw one.
@MainActor
final class AppleSignInNonceTests: XCTestCase {
    private let hexDigits = Set("0123456789abcdef")

    func testRawNonceIs32RandomBytesAsLowercaseHex() {
        let raw = SupabaseAuthService.generateNonce().raw

        XCTAssertEqual(raw.count, 64)
        XCTAssertTrue(raw.allSatisfy(hexDigits.contains))
        XCTAssertNotEqual(raw, String(repeating: "0", count: 64))
    }

    func testEveryNonceIsDifferent() {
        let nonces = (0..<20).map { _ in SupabaseAuthService.generateNonce().raw }

        XCTAssertEqual(Set(nonces).count, 20)
    }

    func testHashedNonceIsSHA256OfTheRawNonce() {
        let nonce = SupabaseAuthService.generateNonce()
        let expected = SHA256.hash(data: Data(nonce.raw.utf8))
            .map { ($0 < 16 ? "0" : "") + String($0, radix: 16) }.joined()

        XCTAssertEqual(nonce.hashed, expected)
        XCTAssertEqual(nonce.hashed.count, 64)
    }
}
