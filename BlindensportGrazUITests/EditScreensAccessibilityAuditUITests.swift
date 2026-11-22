import XCTest

/// The accessibility audit on the edit screens (Bearbeiten), as the sample
/// admin from `UITestMode` (no server).
@MainActor
final class EditScreensAccessibilityAuditUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-sample-schedule", "-ui-testing-signed-in"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Trainings"].waitForExistence(timeout: 15), "signed in as admin")
    }

    private func tapRow(containing text: String) {
        let row = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "row \(text)")
        row.tap()
    }

    private func openClubEntry(_ entry: String) {
        app.tabBars.buttons["Mehr"].tap()
        app.cells.containing(.staticText, identifier: "Verein").firstMatch.tap()
        tapRow(containing: entry)
    }

    /// Taps "Bearbeiten" and audits; the large "Fertig" must be in the form.
    private func auditEditing() throws {
        let edit = app.navigationBars.buttons["Bearbeiten"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        edit.tap()
        XCTAssertTrue(app.buttons["Fertig"].firstMatch.waitForExistence(timeout: 5))
        try app.auditAccessibility(test: name)
    }

    func testEditTraining() throws {
        app.tabBars.buttons["Trainings"].tap()
        tapRow(containing: "Blindenfußballtraining")
        try auditEditing()
    }

    func testEditTournament() throws {
        app.tabBars.buttons["Turniere"].tap()
        tapRow(containing: "Torballturnier")
        try auditEditing()
    }

    func testEditEvent() throws {
        app.tabBars.buttons["Events"].tap()
        tapRow(containing: "Vereinsfeier")
        try auditEditing()
    }

    func testMember() throws {
        openClubEntry("Benutzerverwaltung")
        tapRow(containing: "Muster")
        XCTAssertTrue(app.buttons["Fertig"].firstMatch.waitForExistence(timeout: 5))
        try app.auditAccessibility(test: name)
    }

    func testTeam() throws {
        openClubEntry("Teams")
        tapRow(containing: "Torball Herren")
        // Wait for the push animation to end: audited mid-transition, the
        // screen reported dimmed headers (flaky contrast findings).
        XCTAssertTrue(app.buttons["Mitglied hinzufügen"].waitForExistence(timeout: 5))
        sleep(2)
        try app.auditAccessibility(test: name)
    }
}
