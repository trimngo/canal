import XCTest

final class WatchQuickLogUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws {
        if testRun?.hasSucceeded == false {
            let app = XCUIApplication()
            record("WatchQuickLogFailure", app)
            // These tests run only synthetic capture data on unsigned simulators.
            print("WATCH QUICK LOG FAILURE: \(app.debugDescription)")
        }
    }

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

    func testWatchCanAuthorizeAndQueueItsOwnCheckInsAndTurnThemOff() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-empty-ledger", "--ui-watch-notification-ledger"]
        app.launch()
        let alerts = app.buttons["watch.notifications"]
        XCTAssertTrue(alerts.waitForExistence(timeout: 15)); alerts.tap()
        let enable = app.buttons["watch.notifications.enable"]
        XCTAssertTrue(enable.waitForExistence(timeout: 10)); enable.tap()
        if app.alerts.buttons["Allow"].waitForExistence(timeout: 3) { app.alerts.buttons["Allow"].tap() }
        let carousel = XCUIApplication(bundleIdentifier: "com.apple.Carousel")
        if carousel.alerts.buttons["Allow"].waitForExistence(timeout: 3) { carousel.alerts.buttons["Allow"].tap() }
        let status = app.staticTexts["watch.notifications.status"]
        let queued = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "Scheduled through"), object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [queued], timeout: 20), .completed)
        record("WatchLocalNotificationsQueued", app)
        app.terminate(); app.launchArguments = []; app.launch()
        XCTAssertTrue(alerts.waitForExistence(timeout: 15)); alerts.tap()
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        XCTAssertTrue(status.label.contains("Scheduled through"))
        let off = app.buttons["watch.notifications.off"]
        for _ in 0..<6 { if off.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(off.exists); off.tap()
        let stopped = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "Check-ins are off"), object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [stopped], timeout: 10), .completed)
    }

    private func assertCount(_ expected: String, _ app: XCUIApplication) {
        let count = app.descendants(matching: .any).matching(identifier: "watch.debug.sample-count").firstMatch
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
