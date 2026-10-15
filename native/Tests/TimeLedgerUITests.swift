import XCTest

final class TimeLedgerUITests: XCTestCase {
    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func reveal(_ target: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<6 {
            if target.exists && target.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(target.waitForExistence(timeout: 5))
        XCTAssertTrue(target.isHittable)
    }

    private func log(_ text: String, in app: XCUIApplication, confirmSuggestion: Bool = false) {
        let field = element(app, "checkin.activity")
        reveal(field, in: app); field.tap(); field.typeText(text)
        if confirmSuggestion {
            let use = app.buttons["checkin.confirm-suggestion"]
            reveal(use, in: app); use.tap()
        }
        let save = app.buttons["checkin.save"]
        reveal(save, in: app); save.tap()
        XCTAssertTrue(app.staticTexts["Saved. You can change it anytime."].waitForExistence(timeout: 5))
    }

    private func openLogs(_ app: XCUIApplication) {
        let logs = element(app, "today.logs"); reveal(logs, in: app); logs.tap()
    }

    func testHomePutsTimeBreakdownBeforeInlineLoggingWithoutTabs() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-grouping-ledger"]; app.launch()
        let header = element(app, "dashboard.breakdown-title")
        let field = element(app, "checkin.activity")
        XCTAssertTrue(header.waitForExistence(timeout: 10))
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertLessThan(header.frame.minY, field.frame.minY)
        XCTAssertEqual(app.tabBars.count, 0)
        XCTAssertFalse(app.segmentedControls["day.mode"].exists)
        XCTAssertFalse(app.staticTexts["Unestimated"].exists)
    }

    func testUnconfirmedSuggestionStaysUncategorizedUntilAcceptedInReview() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-empty-ledger"]; app.launch()
        log("Working on app", in: app)
        XCTAssertFalse(app.buttons["dashboard.group.work"].exists)
        let review = app.buttons["dashboard.review.uncategorized"]; reveal(review, in: app); review.tap()
        XCTAssertTrue(app.staticTexts["Suggested: Work"].waitForExistence(timeout: 5))
        let confirm = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "group.confirm.")).firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5)); confirm.tap()
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["dashboard.group.work"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["dashboard.review.uncategorized"].exists)
    }

    func testNewLogCanExplicitlyConfirmTheDisplayedSuggestion() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-empty-ledger"]; app.launch()
        log("Preparing classes", in: app, confirmSuggestion: true)
        XCTAssertTrue(app.buttons["dashboard.group.work"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["dashboard.review.uncategorized"].exists)
    }

    func testDashboardCategorizesAnUnknownActivityAndSupportsUndo() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-grouping-ledger"]; app.launch()
        app.buttons["dashboard.review.uncategorized"].tap()
        XCTAssertTrue(app.staticTexts["Quokka activity fixture"].waitForExistence(timeout: 5))
        app.buttons["Choose group"].tap(); app.buttons["Socializing"].tap()
        let undo = app.buttons["group.undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5)); undo.tap()
        XCTAssertTrue(app.staticTexts["Quokka activity fixture"].waitForExistence(timeout: 5))
        app.buttons["Choose group"].tap(); app.buttons["Socializing"].tap()
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["dashboard.group.social"].waitForExistence(timeout: 5))
    }

    func testDashboardCreatesAndRenamesANewGroup() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-grouping-ledger"]; app.launch()
        app.buttons["dashboard.review.uncategorized"].tap()
        app.buttons["Choose group"].tap(); app.buttons["Create new group…"].tap()
        let field = app.alerts.textFields["Group name"]
        XCTAssertTrue(field.waitForExistence(timeout: 5)); field.typeText("Creative Practice")
        app.alerts.buttons["Create & categorize"].tap()
        app.buttons["Done"].tap(); app.buttons["dashboard.groups"].tap()
        app.swipeUp()
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "groups.rename.", "Creative Practice")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        let groupID = String(row.identifier.dropFirst("groups.rename.".count)); row.tap()
        let rename = app.alerts.textFields["Group name"]
        XCTAssertTrue(rename.waitForExistence(timeout: 5))
        rename.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        rename.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 30))
        rename.typeText("Creative Projects")
        app.alerts.buttons["Save"].tap()
        XCTAssertTrue(app.buttons["groups.rename.\(groupID)"].staticTexts["Creative Projects"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["dashboard.group.\(groupID)"].waitForExistence(timeout: 5))
    }

    func testCalendarOpensOnASeparateScreen() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-grouping-ledger"]; app.launch()
        app.buttons["dashboard.calendar"].tap()
        XCTAssertTrue(app.scrollViews["timeline.grid"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Noon"].exists)
    }

    func testExistingConfirmedLogSurvivesUpgradeAndCanBeEdited() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-legacy-ledger"]; app.launch()
        XCTAssertTrue(app.buttons["dashboard.group.work"].waitForExistence(timeout: 10))
        openLogs(app)
        let sample = app.staticTexts["Legacy sample UI fixture"]; reveal(sample, in: app); sample.tap()
        XCTAssertTrue(element(app, "edit.activity").waitForExistence(timeout: 5))
        let save = app.buttons["edit.save"]; reveal(save, in: app); save.tap()
        XCTAssertTrue(app.staticTexts["Legacy sample UI fixture"].waitForExistence(timeout: 5))
    }

    func testNotificationOpenedLogCanBeSavedAndSurvivesRelaunch() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-empty-ledger", "--ui-notification-checkin"]; app.launch()
        log("Notification sample UI test", in: app)
        app.terminate(); app.launchArguments = []; app.launch()
        openLogs(app)
        XCTAssertTrue(app.staticTexts["Notification sample UI test"].waitForExistence(timeout: 5))
    }

    func testInboxRemainsAccessibleFromMore() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-empty-ledger"]; app.launch()
        app.buttons["dashboard.more"].tap(); app.buttons["Inbox"].tap()
        let field = element(app, "inbox.text")
        XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap(); field.typeText("Follow up with a client UI test")
        let save = app.buttons["inbox.save"]; reveal(save, in: app); save.tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["dashboard.more"].tap(); app.buttons["Inbox"].tap()
        XCTAssertTrue(app.staticTexts["Follow up with a client UI test"].waitForExistence(timeout: 5))
    }

    func testQuickNotificationReplySavesWithoutEditorConfirmationAndSurvivesRelaunch() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-empty-ledger", "--ui-quick-reply"]; app.launch()
        openLogs(app)
        XCTAssertTrue(app.staticTexts["Direct notification reply UI fixture"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["dashboard.review.uncategorized"].exists)
        app.terminate(); app.launchArguments = []; app.launch()
        openLogs(app)
        XCTAssertTrue(app.staticTexts["Direct notification reply UI fixture"].waitForExistence(timeout: 5))
    }

    func testSiriNoteHandlerSavesTitleOnlyWithoutOpeningAnEditorAndPersists() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-empty-ledger", "--ui-siri-capture"]; app.launch()
        app.buttons["dashboard.more"].tap(); app.buttons["Inbox"].tap()
        XCTAssertTrue(app.staticTexts["One sentence Siri UI fixture"].waitForExistence(timeout: 5))
        app.terminate(); app.launchArguments = []; app.launch()
        app.buttons["dashboard.more"].tap(); app.buttons["Inbox"].tap()
        XCTAssertTrue(app.staticTexts["One sentence Siri UI fixture"].waitForExistence(timeout: 5))
    }
}
