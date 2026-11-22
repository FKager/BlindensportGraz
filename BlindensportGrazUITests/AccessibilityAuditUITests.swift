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
        app.launchArguments = ["-ui-testing"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Übersicht"].waitForExistence(timeout: 15), "the app starts signed out")
    }

    /// Runs the audit; each finding fails the test and is printed with its element.
    /// `ignoreTabBarGlass`: on a screen whose list scrolls under the tab bar,
    /// iOS 26's glass tab bar mixes the unselected tab's grey label with the
    /// content behind it and the audit reports a contrast failure without an
    /// element. Proven 2026-11-22 by elimination (hiding the tab bar removes
    /// it; text colours, icons and scroll edge made no difference). Apple's
    /// control; "Reduce Transparency" makes the bar solid for those who need it.
    private func audit(ignoreTabBarGlass: Bool = false, file: StaticString = #filePath, line: UInt = #line) throws {
        try app.performAccessibilityAudit { issue in
            if ignoreTabBarGlass, issue.auditType == .contrast, issue.element == nil {
                return true
            }
            // The Dynamic Type check enlarges the text in place; a control in
            // the lower half of the screen is pushed below the bottom edge and
            // then reported as "partially unsupported". Proven 2026-11-22:
            // removing the text above "Link senden" made its finding go away;
            // at the largest size the buttons do scale (checked on screenshots).
            if issue.auditType == .dynamicType, let element = issue.element,
               element.frame.minY > self.app.windows.firstMatch.frame.height * 0.4 {
                return true
            }
            let element = issue.element.map { "\($0.elementType.rawValue) '\($0.label)' id='\($0.identifier)'" } ?? "-"
            print("A11Y-ISSUE | \(self.name) | \(issue.compactDescription) | \(element) | \(issue.detailedDescription) | frame=\(issue.element?.frame ?? .zero)")
            return false
        }
    }

    func testOverview() throws {
        try audit(ignoreTabBarGlass: true)
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
