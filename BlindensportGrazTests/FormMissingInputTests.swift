import XCTest
@testable import BlindensportGraz

/// The sign-in and registration buttons are never greyed out; they say what's missing.
@MainActor
final class FormMissingInputTests: XCTestCase {
    func testSignInNamesTheMissingField() {
        XCTAssertEqual(LoginView.missingInput(email: " ", password: "x"), "Bitte gib deine E-Mail-Adresse ein.")
        XCTAssertEqual(LoginView.missingInput(email: "a@b.at", password: ""), "Bitte gib dein Passwort ein.")
        XCTAssertNil(LoginView.missingInput(email: "a@b.at", password: "x"))
    }

    func testRegistrationNamesTheFirstMissingThing() {
        func missing(_ first: String = "Anna", _ last: String = "Muster", _ mail: String = "anna@example.org",
                     _ pass: String = "geheim12345", _ confirm: String = "geheim12345") -> String? {
            RegisterView.missingInput(firstName: first, lastName: last, email: mail, password: pass, passwordConfirm: confirm)
        }
        XCTAssertEqual(missing(""), "Bitte gib deinen Vornamen ein.")
        XCTAssertEqual(missing("Anna", " "), "Bitte gib deinen Nachnamen ein.")
        XCTAssertEqual(missing("Anna", "Muster", "anna@"), "Bitte gib eine gültige E-Mail-Adresse ein.")
        XCTAssertEqual(missing("Anna", "Muster", "anna@example.org", "kurz1"),
                       "Das Passwort braucht mindestens 10 Zeichen, mit Buchstaben und Ziffern.")
        XCTAssertEqual(missing("Anna", "Muster", "anna@example.org", "geheim12345", "geheim12346"),
                       "Die beiden Passwörter stimmen nicht überein.")
        XCTAssertNil(missing())
    }
}
