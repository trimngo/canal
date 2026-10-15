import XCTest

final class TimeLedgerUITests: XCTestCase {
    func testDashboardCategorizesAnUnknownActivityAndSupportsUndo() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-grouping-ledger"]; app.launch()
        XCTAssertTrue(app.buttons["dashboard.group.uncategorized"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["dashboard.review.uncategorized"].exists)
        XCTAssertFalse(app.staticTexts["Unestimated"].exists)
        app.buttons["dashboard.review.uncategorized"].tap()
        XCTAssertTrue(app.staticTexts["Quokka activity fixture"].waitForExistence(timeout: 5))
        app.buttons["Choose group"].tap(); app.buttons["Socializing"].tap()
        let undo = app.buttons["Undo last categorization"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5)); undo.tap()
        XCTAssertTrue(app.staticTexts["Quokka activity fixture"].waitForExistence(timeout: 5))
        app.buttons["Choose group"].tap(); app.buttons["Socializing"].tap()
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["dashboard.group.social"].waitForExistence(timeout: 5))
    }

    func testDashboardCreatesAndRenamesANewGroup() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-grouping-ledger"]; app.launch()
        app.buttons["dashboard.group.uncategorized"].tap()
        app.buttons["Choose group"].tap(); app.buttons["Create new group…"].tap()
        let field = app.alerts.textFields["Group name"]
        XCTAssertTrue(field.waitForExistence(timeout: 5)); field.typeText("Creative Practice")
        app.alerts.buttons["Create & categorize"].tap()
        app.buttons["Done"].tap(); app.buttons["dashboard.groups"].tap()
        app.swipeUp()
        app.staticTexts["Creative Practice"].tap()
        let rename = app.alerts.textFields["Group name"]
        XCTAssertTrue(rename.waitForExistence(timeout: 5))
        rename.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        rename.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 30))
        rename.typeText("Creative Projects")
        app.alerts.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["Creative Projects"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts["Creative Projects"].waitForExistence(timeout: 5))
    }

    func testCalendarViewShowsDayGridAndNoonMarker() {
        let app = XCUIApplication(); app.launch()
        app.tabBars.buttons["My day"].tap()
        app.segmentedControls["day.mode"].buttons["Calendar"].tap()
        XCTAssertTrue(app.scrollViews["timeline.grid"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Noon"].exists)
    }

    func testExistingCheckInSurvivesUpgradeAndCanBeEdited() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-legacy-ledger"]
        app.launch()
        app.tabBars.buttons["My day"].tap(); app.swipeUp()
        let sample = app.staticTexts["Legacy sample UI fixture"]
        XCTAssertTrue(sample.waitForExistence(timeout: 10)); sample.tap()
        let activity = app.textFields["checkin.activity"].exists ? app.textFields["checkin.activity"] : app.textViews["checkin.activity"]
        XCTAssertTrue(activity.waitForExistence(timeout: 5))
        app.buttons["checkin.save"].tap()
        XCTAssertTrue(app.staticTexts["Legacy sample UI fixture"].waitForExistence(timeout: 5))
    }

    func testNotificationOpenedSampleCanBeSavedWithoutCrashing() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-notification-checkin"]
        app.launch()
        let activity = app.textFields["checkin.activity"].exists ? app.textFields["checkin.activity"] : app.textViews["checkin.activity"]
        XCTAssertTrue(activity.waitForExistence(timeout: 10))
        activity.tap(); activity.typeText("Notification sample UI test")
        if !app.buttons["checkin.save"].isHittable { app.swipeUp() }
        app.buttons["checkin.save"].tap()
        XCTAssertTrue(app.staticTexts["Saved. You can change it anytime."].waitForExistence(timeout: 5))
        app.terminate(); app.launch()
        app.tabBars.buttons["My day"].tap(); app.swipeUp()
        XCTAssertTrue(app.staticTexts["Notification sample UI test"].waitForExistence(timeout: 5))
    }

    func testSampleCanBeCategorizedAfterSaving() {
        let app = XCUIApplication(); app.launch()
        app.tabBars.buttons["Check in"].tap()
        let activity = app.textFields["checkin.activity"].exists ? app.textFields["checkin.activity"] : app.textViews["checkin.activity"]
        XCTAssertTrue(activity.waitForExistence(timeout: 10))
        activity.tap(); activity.typeText("Categorization UI test")
        if !app.buttons["checkin.save"].isHittable { app.swipeUp() }
        app.buttons["checkin.save"].tap()
        app.tabBars.buttons["My day"].tap(); app.swipeUp()
        let sample = app.staticTexts["Categorization UI test"]
        XCTAssertTrue(sample.waitForExistence(timeout: 5)); sample.tap()
        app.buttons["checkin.category"].tap()
        app.buttons["Work"].tap()
        if !app.buttons["checkin.save"].isHittable { app.swipeUp() }
        app.buttons["checkin.save"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", " · Work")).firstMatch.waitForExistence(timeout: 5))
    }

    func testCheckInCanBeSavedAndCategorizedLater() {
        let app = XCUIApplication(); app.launch()
        app.tabBars.buttons["Check in"].tap()
        let activity = app.textFields["checkin.activity"].exists ? app.textFields["checkin.activity"] : app.textViews["checkin.activity"]
        XCTAssertTrue(activity.waitForExistence(timeout: 10))
        activity.tap(); activity.typeText("Preparing classes UI test")
        if !app.buttons["checkin.save"].isHittable { app.swipeUp() }
        app.buttons["checkin.save"].tap()
        XCTAssertTrue(app.staticTexts["Saved. You can change it anytime."].waitForExistence(timeout: 5))
        app.tabBars.buttons["My day"].tap()
        XCTAssertTrue(app.buttons["dashboard.group.work"].waitForExistence(timeout: 5))
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["Preparing classes UI test"].waitForExistence(timeout: 5))
    }

    func testThoughtCanBeCapturedWithoutCalendarLogin() {
        let app = XCUIApplication(); app.launch()
        app.tabBars.buttons["Inbox"].tap()
        let field = app.textFields["inbox.text"].exists ? app.textFields["inbox.text"] : app.textViews["inbox.text"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText("Follow up with a client UI test")
        app.buttons["inbox.save"].tap()
        // Leaving the editor dismisses the system keyboard before reviewing.
        app.tabBars.buttons["My day"].tap()
        app.tabBars.buttons["Inbox"].tap()
        XCTAssertTrue(app.staticTexts["Follow up with a client UI test"].waitForExistence(timeout: 5))
    }
}
