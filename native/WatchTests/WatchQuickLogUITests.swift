import XCTest

final class WatchQuickLogUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testComplicationEntryAcceptsOneDoneSavesAndSurvivesRelaunch() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-empty-ledger", "--ui-watch-inspect-ledger", "--ui-watch-quick-log", "--ui-watch-dictation"]
        app.launch()
        let done = app.buttons["watch.fixture.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 15))
        record("WatchDirectDictation", app)
        done.tap()
        assertCount("1", app)
        XCTAssertEqual(app.staticTexts["watch.debug.last-sample"].label, "Preparing classes")
        record("WatchComplicationLogSaved", app)
        app.terminate(); app.launchArguments = ["--ui-watch-inspect-ledger"]; app.launch()
        assertCount("1", app)
        XCTAssertFalse(done.exists)
        app.terminate()
        app.launchArguments = ["--ui-watch-inspect-ledger", "--ui-watch-quick-log", "--ui-watch-dictation"]
        app.launch(); XCTAssertTrue(done.waitForExistence(timeout: 15)); done.tap()
        assertCount("2", app)
    }

    func testCancelCreatesNoSampleAndNormalIconDoesNotStartInput() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-empty-ledger", "--ui-watch-inspect-ledger", "--ui-watch-quick-log", "--ui-watch-dictation"]
        app.launch()
        let cancel = app.buttons["watch.fixture.cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 15)); cancel.tap()
        assertCount("0", app)
        app.terminate(); app.launchArguments = ["--ui-watch-inspect-ledger"]; app.launch()
        assertCount("0", app)
        XCTAssertFalse(app.buttons["watch.fixture.done"].exists)
    }

    private func assertCount(_ expected: String, _ app: XCUIApplication) {
        let count = app.staticTexts["watch.debug.sample-count"]
        // The narrow Watch screen may require scrolling below the summary.
        for _ in 0..<5 {
            if count.exists { break }
            app.swipeUp()
        }
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", expected), object: count)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed)
    }

    private func record(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Review-\(name)"; attachment.lifetime = .keepAlways; add(attachment)
    }
}
