import XCTest

/// iOS's own accessibility audit (missing VoiceOver labels, too-small touch
/// targets, text clipped at large Dynamic Type sizes, contrast, …) on the
/// screens reachable without signing in. Complements, never replaces, a
/// VoiceOver pass by hand.
@MainActor
final class AccessibilityAuditUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-sample-schedule"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Übersicht"].waitForExistence(timeout: 15), "the app starts signed out")
    }

    private func audit(ignoreTabBarGlass: Bool = false) throws {
        try app.auditAccessibility(test: name, ignoreTabBarGlass: ignoreTabBarGlass)
    }

    func testOverview() throws {
        XCTAssertTrue(app.staticTexts["Blindenfußballtraining"].waitForExistence(timeout: 5))
        try audit(ignoreTabBarGlass: true)
    }

    func testEmptyOverview() throws {
        app.terminate()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Noch nichts geplant"].waitForExistence(timeout: 15))
        try audit()
    }

    func testAccount() throws {
        app.tabBars.buttons["Account"].tap()
        XCTAssertTrue(app.buttons["Registrieren"].waitForExistence(timeout: 5))
        try audit()
    }

    func testRegister() throws {
        app.tabBars.buttons["Account"].tap()
        app.buttons["Registrieren"].tap()
        XCTAssertTrue(app.staticTexts["Neues Konto"].firstMatch.waitForExistence(timeout: 5))
        try audit()
    }

    func testSignIn() throws {
        app.tabBars.buttons["Account"].tap()
        app.buttons["Anmelden"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Passwort vergessen?"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Anmelden"].firstMatch.waitForExistence(timeout: 5))
        try audit()
    }

    func testForgotPassword() throws {
        app.tabBars.buttons["Account"].tap()
        app.buttons["Anmelden"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Passwort vergessen?"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Anmelden"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["Passwort vergessen?"].tap()
        XCTAssertTrue(app.staticTexts["Passwort vergessen"].firstMatch.waitForExistence(timeout: 5))
        try audit()
    }
}
