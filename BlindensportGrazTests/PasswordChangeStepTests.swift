import XCTest
import Supabase
@testable import BlindensportGraz

/// A password change the server wants confirmed asks for the emailed code;
/// a wrong code says so; everything else is shown as an error.
final class PasswordChangeStepTests: XCTestCase {
    private func authError(_ code: ErrorCode) -> AuthError {
        let response = HTTPURLResponse(url: URL(string: "https://example.invalid/auth/v1/user")!, statusCode: 401,
                                       httpVersion: nil, headerFields: nil)!
        return .api(message: "x", errorCode: code, underlyingData: Data(), underlyingResponse: response)
    }

    func testTheServerAskingForConfirmationMailsACode() {
        XCTAssertEqual(PasswordChangeStep.after(authError(.reauthenticationNeeded)), .askForCode)
    }

    func testAWrongOrExpiredCodeIsRejected() {
        XCTAssertEqual(PasswordChangeStep.after(authError(.reauthenticationNotValid)), .codeRejected)
    }

    func testOtherErrorsAreShown() {
        XCTAssertEqual(PasswordChangeStep.after(authError(.weakPassword)), .failed)
        XCTAssertEqual(PasswordChangeStep.after(URLError(.notConnectedToInternet)), .failed)
    }

    func testCodesIgnoreSpacesAndOtherCharacters() {
        XCTAssertEqual(PasswordChangeStep.cleanedCode(" 123 456 "), "123456")
    }

    func testTheRejectedCodeHasItsOwnMessage() {
        XCTAssertTrue(AuthErrorMessage.text(for: authError(.reauthenticationNotValid)).contains("Bestätigungscode"))
    }
}
