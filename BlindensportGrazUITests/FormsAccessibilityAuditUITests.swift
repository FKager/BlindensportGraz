import XCTest

/// The accessibility audit on the add forms, as the sample admin from
/// `UITestMode` (no server; nothing is saved).
@MainActor
final class FormsAccessibilityAuditUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-sample-schedule", "-ui-testing-signed-in"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Trainings"].waitForExistence(timeout: 15), "signed in as admin")
    }

    /// Opens Verein (under "Mehr" on an iPhone) and one of its entries.
    private func openClubEntry(_ entry: String) {
        app.tabBars.buttons["Mehr"].tap()
        app.cells.containing(.staticText, identifier: "Verein").firstMatch.tap()
        let link = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", entry)).firstMatch
        XCTAssertTrue(link.waitForExistence(timeout: 5))
        link.tap()
    }

    private func auditForm(titled title: String) throws {
        XCTAssertTrue(app.staticTexts[title].firstMatch.waitForExistence(timeout: 5), "form \(title) is open")
        try app.auditAccessibility(test: name)
    }

    func testNewTraining() throws {
        app.tabBars.buttons["Trainings"].tap()
        app.buttons["Neues Training"].firstMatch.tap()
        try auditForm(titled: "Neues Training")
    }

    func testNewTournament() throws {
        app.tabBars.buttons["Turniere"].tap()
        app.buttons["Turnier hinzufügen"].firstMatch.tap()
        app.buttons["Neues Turnier"].firstMatch.tap()
        try auditForm(titled: "Neues Turnier")
    }

    func testNewEvent() throws {
        app.tabBars.buttons["Events"].tap()
        app.buttons["Neues Event"].firstMatch.tap()
        try auditForm(titled: "Neues Event")
    }

    func testNewTeam() throws {
        openClubEntry("Teams")
        app.buttons["Neues Team"].firstMatch.tap()
        try auditForm(titled: "Neues Team")
    }

    func testNewMember() throws {
        openClubEntry("Benutzerverwaltung")
        app.buttons["Neues Mitglied"].firstMatch.tap()
        try auditForm(titled: "Neues Mitglied")
    }

    func testNewBudgetEntry() throws {
        openClubEntry("Vereinsbudget")
        app.buttons["Eintrag hinzufügen"].firstMatch.tap()
        try auditForm(titled: "Neuer Eintrag")
    }

    func testEditProfile() throws {
        app.tabBars.buttons["Mehr"].tap()
        app.cells.containing(.staticText, identifier: "Account").firstMatch.tap()
        let edit = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Profil bearbeiten'")).firstMatch
        if !edit.waitForExistence(timeout: 3) { app.swipeUp() }
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        edit.tap()
        try auditForm(titled: "Profil bearbeiten")
    }
}
