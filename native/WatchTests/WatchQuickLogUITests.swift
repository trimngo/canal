import XCTest

final class WatchQuickLogUITests: XCTestCase {
    func testTimerExpiryHasDirectDoneAndRestartAndKeepsQueueAfterRelaunch() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-empty-ledger", "--ui-timer-fixture", "--ui-quiet-timer-alerts"]
        app.launch()
        XCTAssertTrue(app.buttons["timers.restart"].waitForExistence(timeout: 30))
        allowTimerNotifications(app)
        XCTAssertEqual(app.staticTexts["timers.current"].label, "Practice guitar")
        record("WatchTimerExpired", app)
        app.buttons["timers.restart"].tap()
        XCTAssertTrue(app.staticTexts["timers.countdown"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["timers.waiting.timer-email"].isHittable)
        XCTAssertEqual(app.staticTexts["timers.current"].label, "Practice guitar")
        app.buttons["timers.done"].tap()
        let email = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Answer email"), object: app.staticTexts["timers.current"])
        XCTAssertEqual(XCTWaiter.wait(for: [email], timeout: 10), .completed)
        record("WatchTimerNextTask", app)
        app.terminate(); app.launchArguments = ["--ui-timer-open", "--ui-quiet-timer-alerts"]; app.launch()
        XCTAssertTrue(app.staticTexts["timers.current"].waitForExistence(timeout: 20))
        XCTAssertEqual(app.staticTexts["timers.current"].label, "Answer email")
        XCTAssertTrue(app.buttons["timers.pause-resume"].waitForExistence(timeout: 5))
        app.buttons["timers.pause-resume"].tap()
        XCTAssertTrue(app.staticTexts["timers.paused"].waitForExistence(timeout: 10))
    }
    func testTimerComplicationRouteQueuesDictatedTaskWithoutAnotherSave() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-empty-ledger", "--ui-timer-open", "--ui-timer-dictation"]
        app.launch()
        XCTAssertTrue(app.staticTexts["timers.current"].waitForExistence(timeout: 30))
        allowTimerNotifications(app)
        XCTAssertEqual(app.staticTexts["timers.current"].label, "Practice guitar")
        record("WatchTimerDictationSaved", app)
    }
    func testMainTimerRowsOpenSystemInputWithoutAQueueSheetAndUseFiveMinutes() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-empty-ledger", "--ui-timer-fixture", "--ui-timer-system-input", "--ui-quiet-timer-alerts"]
        app.launch()
        XCTAssertTrue(app.buttons["timers.dictate"].waitForExistence(timeout: 30))
        allowTimerNotifications(app)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "timers.progress").firstMatch.exists)
        XCTAssertFalse(app.buttons["timers.queue"].exists)
        app.buttons["timers.dictate"].tap()
        let suggestion = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Stretch")).firstMatch
        XCTAssertTrue(suggestion.waitForExistence(timeout: 10))
        XCTAssertTrue(suggestion.isHittable)
        record("WatchTimerSystemInputVisible", app)
        suggestion.tap()
        allowTimerNotifications(app)
        // Advance the two existing tasks so the newly captured row is the
        // next visible item. A full swipe can overshoot a lazy, half-height list.
        XCTAssertEqual(app.staticTexts["timers.current"].label, "Practice guitar")
        app.buttons["timers.done"].tap()
        let email = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Answer email"), object: app.staticTexts["timers.current"])
        XCTAssertEqual(XCTWaiter.wait(for: [email], timeout: 10), .completed)
        app.buttons["timers.done"].tap()
        let walk = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Take a walk"), object: app.staticTexts["timers.current"])
        XCTAssertEqual(XCTWaiter.wait(for: [walk], timeout: 10), .completed)
        // A separate queue page precedes the current timer in the vertical pager.
        app.staticTexts["timers.current"].swipeDown()
        let added = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label == %@", "timers.waiting.", "Stretch")).firstMatch
        XCTAssertTrue(added.waitForExistence(timeout: 10))
        let id = added.identifier.replacingOccurrences(of: "timers.waiting.", with: "")
        XCTAssertEqual(app.staticTexts["timers.duration.\(id)"].label, "5:00")
        XCTAssertEqual(app.staticTexts["timers.queue-current"].label, "Take a walk")
        XCTAssertFalse(app.buttons["timers.delete.\(id)"].isHittable)
        record("WatchTimersSeparateQueue", app)
        app.staticTexts["timers.queue-current"].swipeUp()
        XCTAssertTrue(app.staticTexts["timers.current"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["timers.current"].label, "Take a walk")
        let add = app.buttons["timers.dictate"]
        XCTAssertTrue(add.isHittable)
        XCTAssertLessThan(add.frame.midY, app.staticTexts["timers.current"].frame.midY)
        XCTAssertGreaterThan(add.frame.midX, app.frame.midX)
        record("WatchSingleTimerUpperRightAdd", app)
    }
    func testQueueCanDeleteAnyTimerAndDeletingCurrentWaitsForStart() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-empty-ledger", "--ui-timer-fixture", "--ui-quiet-timer-alerts"]
        app.launch()
        XCTAssertTrue(app.staticTexts["timers.current"].waitForExistence(timeout: 30))
        app.staticTexts["timers.current"].swipeDown()
        let email = app.staticTexts["timers.waiting.timer-email"]
        XCTAssertTrue(email.waitForExistence(timeout: 5))
        // Returning must work before scrolling to the end of a longer queue.
        app.staticTexts["timers.queue-current"].swipeUp()
        XCTAssertTrue(app.staticTexts["timers.current"].waitForExistence(timeout: 5))
        app.staticTexts["timers.current"].swipeDown()
        XCTAssertTrue(email.waitForExistence(timeout: 5)); email.swipeLeft()
        let deleteEmail = app.buttons["timers.delete.timer-email"]
        XCTAssertTrue(deleteEmail.waitForExistence(timeout: 5)); deleteEmail.tap()
        XCTAssertFalse(email.exists)
        let current = app.staticTexts["timers.queue-current"]
        current.swipeLeft()
        let deleteCurrent = app.buttons["timers.delete.timer-guitar"]
        XCTAssertTrue(deleteCurrent.waitForExistence(timeout: 5)); deleteCurrent.tap()
        XCTAssertFalse(current.exists)
        let walk = app.staticTexts["timers.waiting.timer-walk"]
        XCTAssertTrue(walk.waitForExistence(timeout: 5))
        walk.swipeUp()
        XCTAssertTrue(app.buttons["timers.start"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["timers.countdown"].exists)
        app.buttons["timers.start"].tap()
        XCTAssertEqual(app.staticTexts["timers.current"].label, "Take a walk")
        record("WatchDeleteWaitsForStart", app)
    }
    func testWatchHomeCanAddATimerInOneTap() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-empty-ledger", "--ui-timer-system-input"]
        app.launch()
        let add = app.buttons["watch.timer-add"]
        XCTAssertTrue(add.waitForExistence(timeout: 30)); add.tap()
        let suggestion = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Stretch")).firstMatch
        XCTAssertTrue(suggestion.waitForExistence(timeout: 10)); suggestion.tap()
        allowTimerNotifications(app)
        XCTAssertTrue(app.staticTexts["timers.current"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["timers.current"].label, "Stretch")
        XCTAssertTrue(app.staticTexts["timers.countdown"].exists)
        record("WatchHomeAddedDefaultTimer", app)
    }
    override func setUpWithError() throws { continueAfterFailure = false }
    private func allowTimerNotifications(_ app: XCUIApplication) {
        let carousel = XCUIApplication(bundleIdentifier: "com.apple.Carousel")
        if carousel.alerts.buttons["Allow"].waitForExistence(timeout: 2) { carousel.alerts.buttons["Allow"].tap() }
        if app.alerts.buttons["Allow"].waitForExistence(timeout: 1) { app.alerts.buttons["Allow"].tap() }
    }
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
        waitForInputButton(done)
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
        app.launch(); waitForInputButton(done); done.tap()
        assertCount("2", app)
    }

    func testCancelCreatesNoSampleAndNormalIconDoesNotStartInput() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-empty-ledger", "--ui-watch-inspect-ledger", "--ui-watch-quick-log", "--ui-watch-dictation"]
        app.launch()
        let cancel = app.buttons["watch.fixture.cancel"]
        waitForInputButton(cancel); cancel.tap()
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
        if enable.waitForExistence(timeout: 3) { enable.tap() }
        if app.alerts.buttons["Allow"].waitForExistence(timeout: 3) { app.alerts.buttons["Allow"].tap() }
        let carousel = XCUIApplication(bundleIdentifier: "com.apple.Carousel")
        if carousel.alerts.buttons["Allow"].waitForExistence(timeout: 3) { carousel.alerts.buttons["Allow"].tap() }
        let status = app.staticTexts["watch.notifications.status"]
        let queued = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "Scheduled through"), object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [queued], timeout: 20), .completed)
        XCTAssertFalse(enable.exists)
        XCTAssertEqual(app.staticTexts["watch.notifications.delivery-mode"].label, "Delivery: Apple Watch")
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

    func testAutomaticDeliveryHasNoModeSwitchAndWatchTestKeepsItAutomatic() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-empty-ledger", "--ui-watch-automatic-notification-ledger"]
        app.launch()
        let alerts = app.buttons["watch.notifications"]
        XCTAssertTrue(alerts.waitForExistence(timeout: 15)); alerts.tap()
        let mode = app.staticTexts["watch.notifications.delivery-mode"]
        XCTAssertTrue(mode.waitForExistence(timeout: 10)); XCTAssertEqual(mode.label, "Delivery: Automatic")
        XCTAssertFalse(app.buttons["watch.notifications.enable"].exists)
        XCTAssertFalse(app.buttons["Switch to Watch delivery"].exists)
        let test = app.buttons["watch.notifications.test"]
        for _ in 0..<6 { if test.isHittable { break }; app.swipeUp() }
        test.tap()
        if app.alerts.buttons["Allow"].waitForExistence(timeout: 3) { app.alerts.buttons["Allow"].tap() }
        let carousel = XCUIApplication(bundleIdentifier: "com.apple.Carousel")
        if carousel.alerts.buttons["Allow"].waitForExistence(timeout: 3) { carousel.alerts.buttons["Allow"].tap() }
        XCTAssertTrue(app.staticTexts["Keep your iPhone unlocked, lower your wrist, and check this Watch in 15 seconds."].waitForExistence(timeout: 10))
        for _ in 0..<6 { if mode.isHittable { break }; app.swipeDown() }
        XCTAssertEqual(mode.label, "Delivery: Automatic")
        XCTAssertFalse(app.buttons["watch.notifications.enable"].exists)
        record("WatchAutomaticDeliverySettings", app)
    }

    func testWatchCanSwitchSharedDeliveryAndShowItsOwnSchedule() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-empty-ledger", "--ui-watch-automatic-notification-ledger"]; app.launch()
        let alerts = app.buttons["watch.notifications"]
        XCTAssertTrue(alerts.waitForExistence(timeout: 15)); alerts.tap()
        let useWatch = app.buttons["watch.notifications.use-watch"]
        for _ in 0..<5 { if useWatch.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(useWatch.exists); useWatch.tap()
        if app.alerts.buttons["Allow"].waitForExistence(timeout: 3) { app.alerts.buttons["Allow"].tap() }
        let carousel = XCUIApplication(bundleIdentifier: "com.apple.Carousel")
        if carousel.alerts.buttons["Allow"].waitForExistence(timeout: 3) { carousel.alerts.buttons["Allow"].tap() }
        let mode = app.staticTexts["watch.notifications.delivery-mode"]
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Delivery: Apple Watch"), object: mode)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 15), .completed)
        let next = app.staticTexts["watch.notifications.next"]
        for _ in 0..<8 { if next.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(next.exists)
        XCTAssertTrue(app.staticTexts["watch.notifications.pending"].exists)
        record("WatchDirectDeliverySchedule", app)
    }

    private func waitForInputButton(_ button: XCUIElement) {
        XCTAssertTrue(button.waitForExistence(timeout: 15))
        // A cold simulator can publish the button before its window accepts
        // taps; XCTest then computes {-1, -1} and never presses the control.
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: button)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 15), .completed)
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
