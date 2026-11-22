import XCTest

/// The accessibility audit (see `XCUIApplication.auditAccessibility`) on the
/// main screens of a signed-in admin: each tab and a detail screen, with the
/// sample data from `UITestMode` (no server).
@MainActor
final class SignedInAccessibilityAuditUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-sample-schedule", "-ui-testing-signed-in"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Trainings"].waitForExistence(timeout: 15), "signed in as admin")
    }

    /// Opens a tab and audits it (all tabs scroll under the glass tab bar).
    /// On an iPhone the app's six tabs don't fit: Verein and Account are under "Mehr".
    private func auditTab(_ name: String) throws {
        if app.tabBars.buttons[name].exists {
            app.tabBars.buttons[name].tap()
        } else {
            app.tabBars.buttons["Mehr"].tap()
            let entry = app.cells.containing(.staticText, identifier: name).firstMatch
            XCTAssertTrue(entry.waitForExistence(timeout: 5))
            entry.tap()
        }
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 5))
        try app.auditAccessibility(test: self.name, ignoreTabBarGlass: true)
    }

    func testDashboard() throws { try auditTab("Übersicht") }
    func testEvents() throws { try auditTab("Events") }
    func testTournaments() throws { try auditTab("Turniere") }
    func testTrainings() throws { try auditTab("Trainings") }
    func testClub() throws { try auditTab("Verein") }
    func testAccount() throws { try auditTab("Account") }

    func testTrainingDetail() throws {
        app.tabBars.buttons["Trainings"].tap()
        let row = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Blindenfußballtraining'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        sleep(1)
        try app.auditAccessibility(test: name, ignoreTabBarGlass: true)
    }

    func testTournamentDetail() throws {
        app.tabBars.buttons["Turniere"].tap()
        let row = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Torballturnier'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        sleep(1)
        try app.auditAccessibility(test: name, ignoreTabBarGlass: true)
    }
}
