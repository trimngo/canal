import XCTest

final class WatchRestartReceiptUITests: XCTestCase {
    func testWatchOwnedRestartReceiptSurvivesDuplicatesAndPhoneRelaunch() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-empty-ledger", "--ui-timer-fixture", "--ui-watch-owned-timer", "--ui-quiet-timer-alerts", "--ui-watch-restart-repro"]
        app.launch()
        let state = app.staticTexts["repro.timer-state"]
        XCTAssertTrue(state.waitForExistence(timeout: 30))
        XCTAssertEqual(state.label, "Expired Watch timer")
        XCTAssertEqual(app.staticTexts["repro.owner"].label, "Watch alerts")
        for count in 1...3 {
            app.buttons["repro.restart"].tap()
            let result = app.staticTexts["repro.result"]
            let saved = NSPredicate(format: "label == %@", "Saved receipt \(count)")
            expectation(for: saved, evaluatedWith: result)
            waitForExpectations(timeout: 30)
            XCTAssertEqual(state.label, "Running Watch timer")
            XCTAssertEqual(app.staticTexts["repro.owner"].label, "Watch alerts")
        }
        app.terminate()
        app.launchArguments = ["--ui-timer-open", "--ui-quiet-timer-alerts", "--ui-watch-restart-repro"]
        app.launch()
        XCTAssertTrue(state.waitForExistence(timeout: 30))
        XCTAssertEqual(state.label, "Running Watch timer")
        XCTAssertEqual(app.staticTexts["repro.owner"].label, "Watch alerts")
    }
}
