import XCTest

final class TimeLedgerUITests: XCTestCase {
    func testCheckInCanBeSavedAndCategorizedLater() {
        let app = XCUIApplication(); app.launch()
        let activity = app.textFields["checkin.activity"].exists ? app.textFields["checkin.activity"] : app.textViews["checkin.activity"]
        XCTAssertTrue(activity.waitForExistence(timeout: 10))
        activity.tap(); activity.typeText("Preparing classes UI test")
        app.buttons["checkin.save"].tap()
        XCTAssertTrue(app.staticTexts["Saved. You can change it anytime."].waitForExistence(timeout: 5))
        app.tabBars.buttons["My day"].tap()
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
