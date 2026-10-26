import XCTest

final class WatchQuickLogUITests: XCTestCase {
    func testUpcomingRowsCanBeDraggedWithoutMovingCurrentOrNavigatingAway() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-empty-ledger", "--ui-timer-fixture", "--ui-quiet-timer-alerts"]; app.launch()
        XCTAssertTrue(app.staticTexts["timers.current"].waitForExistence(timeout: 30))
        swipeTimerPage(app, toQueue: true)
        let walk = app.staticTexts["timers.waiting.timer-walk"], email = app.staticTexts["timers.waiting.timer-email"]
        XCTAssertTrue(walk.waitForExistence(timeout: 5)); XCTAssertTrue(email.exists)
        XCTAssertTrue(walk.isHittable); XCTAssertTrue(email.isHittable)
        let origin = walk.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let destination = email.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1))
        origin.press(forDuration: 0.8, thenDragTo: destination)
        let moved = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in walk.frame.minY < email.frame.minY }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [moved], timeout: 5), .completed)
        XCTAssertTrue(email.exists); XCTAssertTrue(walk.exists)
        XCTAssertFalse(app.staticTexts["timers.current"].exists)
        record("WatchReorderedUpcomingTimers", app)
        swipeTimerPage(app, toQueue: false)
        XCTAssertTrue(app.staticTexts["timers.current"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["timers.current"].label, "Practice guitar")
        app.buttons["timers.done"].tap()
        let next = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Take a walk"), object: app.staticTexts["timers.current"])
        XCTAssertEqual(XCTWaiter.wait(for: [next], timeout: 10), .completed)
        app.terminate(); app.launchArguments = ["--ui-timer-open", "--ui-quiet-timer-alerts"]; app.launch()
        XCTAssertTrue(app.staticTexts["timers.current"].waitForExistence(timeout: 20))
        XCTAssertEqual(app.staticTexts["timers.current"].label, "Take a walk")
    }
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
        XCTAssertTrue(app.staticTexts["timers.countdown"].waitForExistence(timeout: 5))
        record("WatchTimerDictationSaved", app)
    }
    func testMainTimerRowsOpenSystemInputWithoutAQueueSheetAndUseFiveMinutes() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-empty-ledger", "--ui-timer-fixture", "--ui-timer-system-input", "--ui-quiet-timer-alerts"]
        app.launch()
        XCTAssertTrue(app.buttons["timers.dictate"].firstMatch.waitForExistence(timeout: 30))
        allowTimerNotifications(app)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "timers.progress").firstMatch.exists)
        XCTAssertFalse(app.buttons["timers.queue"].exists)
        app.buttons["timers.dictate"].firstMatch.tap()
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
        // Swiping up reveals the queue below the current timer.
        swipeTimerPage(app, toQueue: true)
        let added = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label == %@", "timers.waiting.", "Stretch")).firstMatch
        XCTAssertTrue(added.waitForExistence(timeout: 10))
        let id = added.identifier.replacingOccurrences(of: "timers.waiting.", with: "")
        XCTAssertEqual(app.staticTexts["timers.duration.\(id)"].label, "5:00")
        XCTAssertEqual(app.staticTexts["timers.queue-current"].label, "Take a walk")
        XCTAssertFalse(app.buttons["timers.delete.\(id)"].isHittable)
        record("WatchTimersSeparateQueue", app)
        swipeTimerPage(app, toQueue: false)
        XCTAssertTrue(app.staticTexts["timers.current"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["timers.current"].label, "Take a walk")
        let add = app.buttons["timers.dictate"].firstMatch
        XCTAssertTrue(add.isHittable)
        XCTAssertLessThan(add.frame.midY, app.staticTexts["timers.current"].frame.midY)
        XCTAssertGreaterThan(add.frame.midX, app.frame.midX)
        record("WatchSingleTimerUpperRightAdd", app)
    }
    func testQueueShowsThreeTimersAndTouchScrollingReachesMoreWithoutChangingPages() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-empty-ledger", "--ui-timer-fixture", "--ui-timer-long-queue", "--ui-quiet-timer-alerts"]
        app.launch()
        XCTAssertTrue(app.staticTexts["timers.current"].waitForExistence(timeout: 30))
        swipeTimerPage(app, toQueue: true)
        let current = app.staticTexts["timers.queue-current"]
        let email = app.staticTexts["timers.waiting.timer-email"]
        let walk = app.staticTexts["timers.waiting.timer-walk"]
        XCTAssertTrue(current.isHittable); XCTAssertTrue(email.isHittable); XCTAssertTrue(walk.isHittable)
        XCTAssertGreaterThan(email.frame.minY, current.frame.minY)
        XCTAssertGreaterThan(walk.frame.minY, email.frame.minY)
        let lastDuration = app.staticTexts["timers.duration.timer-walk"]
        XCTAssertTrue(lastDuration.isHittable)
        XCTAssertLessThan(lastDuration.frame.maxY, app.frame.maxY)
        record("WatchThreeCompactTimerRows", app)
        let extra = app.staticTexts["timers.waiting.timer-extra-8"]
        for _ in 0..<6 {
            if extra.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(extra.isHittable)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "timers.queue-list").firstMatch.exists)
        XCTAssertFalse(app.staticTexts["timers.current"].exists)
        record("WatchQueueTouchScrolled", app)
        // Rightward navigation stays available without scrolling to the top.
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5))
        let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5))
        from.press(forDuration: 0.01, thenDragTo: to, withVelocity: .fast, thenHoldForDuration: 0)
        XCTAssertTrue(app.staticTexts["timers.current"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["timers.current"].label, "Practice guitar")
    }
    func testRunningTimerRemainsTheOpeningScreenAfterRelaunch() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-empty-ledger", "--ui-timer-fixture", "--ui-quiet-timer-alerts"]
        app.launch()
        XCTAssertTrue(app.buttons["timers.restart"].waitForExistence(timeout: 30))
        app.buttons["timers.restart"].tap()
        XCTAssertTrue(app.staticTexts["timers.countdown"].waitForExistence(timeout: 5))
        app.terminate(); app.launchArguments = ["--ui-quiet-timer-alerts"]; app.launch()
        XCTAssertTrue(app.staticTexts["timers.current"].waitForExistence(timeout: 20))
        XCTAssertEqual(app.staticTexts["timers.current"].label, "Practice guitar")
        XCTAssertFalse(app.staticTexts["timers.queue-current"].isHittable)
    }
    func testQueueCanDeleteAnyTimerAndDeletingCurrentWaitsForStart() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-empty-ledger", "--ui-timer-fixture", "--ui-quiet-timer-alerts"]
        app.launch()
        XCTAssertTrue(app.staticTexts["timers.current"].waitForExistence(timeout: 30))
        swipeTimerPage(app, toQueue: true)
        let email = app.staticTexts["timers.waiting.timer-email"]
        XCTAssertTrue(email.waitForExistence(timeout: 5))
        // Returning must work before scrolling to the end of a longer queue.
        swipeTimerPage(app, toQueue: false)
        XCTAssertTrue(app.staticTexts["timers.current"].waitForExistence(timeout: 5))
        swipeTimerPage(app, toQueue: true)
        XCTAssertTrue(email.waitForExistence(timeout: 5)); email.swipeLeft()
        let deleteEmail = app.buttons["timers.delete.timer-email"].firstMatch
        XCTAssertTrue(deleteEmail.waitForExistence(timeout: 5)); deleteEmail.tap()
        XCTAssertFalse(email.exists)
        let current = app.staticTexts["timers.queue-current"]
        current.swipeLeft()
        let deleteCurrent = app.buttons["timers.delete.timer-guitar"].firstMatch
        XCTAssertTrue(deleteCurrent.waitForExistence(timeout: 5)); deleteCurrent.tap()
        XCTAssertFalse(current.exists)
        let walk = app.staticTexts["timers.waiting.timer-walk"]
        XCTAssertTrue(walk.waitForExistence(timeout: 5))
        swipeTimerPage(app, toQueue: false)
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
    func testNewSoleTimerStartsAgainAfterFinishingThePreviousQueue() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-empty-ledger", "--ui-timer-open", "--ui-timer-dictation", "--ui-quiet-timer-alerts"]
        app.launch()
        XCTAssertTrue(app.staticTexts["timers.countdown"].waitForExistence(timeout: 30))
        app.buttons["timers.done"].tap()
        XCTAssertTrue(app.staticTexts["No timers yet"].waitForExistence(timeout: 5))
        app.buttons["timers.dictate"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["timers.countdown"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["timers.current"].label, "Practice guitar")
        XCTAssertFalse(app.buttons["timers.start"].exists)
    }
    func testMainTimerOptionsOfferHapticPatternsPreviewAndRepeatInterval() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-empty-ledger", "--ui-timer-fixture", "--ui-quiet-timer-alerts"]
        app.launch()
        let options = app.buttons["timers.options"].firstMatch
        XCTAssertTrue(options.waitForExistence(timeout: 30))
        options.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let settings = app.buttons["timers.alarm-settings"].firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 5)); settings.tap()
        let pattern = app.descendants(matching: .any).matching(identifier: "timers.haptic-pattern").firstMatch
        revealWatchControl(pattern, in: app)
        pattern.tap()
        let light = app.buttons["Light tap"].firstMatch
        XCTAssertTrue(light.waitForExistence(timeout: 5)); light.tap()
        let repeatInterval = app.descendants(matching: .any).matching(identifier: "timers.haptic-repeat").firstMatch
        revealWatchControl(repeatInterval, in: app)
        repeatInterval.tap()
        let five = app.buttons["5 seconds"].firstMatch
        XCTAssertTrue(five.waitForExistence(timeout: 5)); five.tap()
        let preview = app.buttons["timers.haptic-preview"]
        revealWatchControl(preview, in: app); preview.tap()
        record("WatchTimerHapticOptions", app)
        app.terminate(); app.launchArguments = ["--ui-timer-open", "--ui-quiet-timer-alerts"]; app.launch()
        XCTAssertTrue(options.waitForExistence(timeout: 20))
        options.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(settings.waitForExistence(timeout: 5)); settings.tap()
        revealWatchControl(pattern, in: app)
        XCTAssertTrue(app.staticTexts["Light tap"].exists)
        revealWatchControl(repeatInterval, in: app)
        XCTAssertTrue(app.staticTexts["5 seconds"].exists)
    }
    func testFullTaskTitleWrapsWhileWaitingRunningAndPaused() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-empty-ledger", "--ui-timer-open", "--ui-timer-long-title", "--ui-timer-waiting", "--ui-quiet-timer-alerts"]
        app.launch()
        let title = "Prepare the complete presentation for the project review with the design team tomorrow morning"
        let ready = app.staticTexts["timers.ready"]
        XCTAssertTrue(ready.waitForExistence(timeout: 30))
        XCTAssertEqual(ready.label, title)
        XCTAssertGreaterThan(ready.frame.height, 80, "The whole title must wrap beyond three lines.")
        record("WatchFullWaitingTaskTitle", app)
        // Scroll the title itself; it must reveal the timer without paging away.
        ready.swipeUp()
        let start = app.buttons["timers.start"]
        if !start.isHittable { scrollLongTimerTitle(in: app) }
        XCTAssertTrue(start.isHittable)
        swipeTimerPage(app, toQueue: true)
        let queuedTitle = app.staticTexts["timers.waiting.long-title"]
        XCTAssertEqual(queuedTitle.label, title)
        XCTAssertGreaterThan(queuedTitle.frame.height, 60, "Waiting rows must also show the full task title.")
        swipeTimerPage(app, toQueue: false)
        if !start.isHittable { scrollLongTimerTitle(in: app) }
        XCTAssertTrue(start.isHittable); start.tap()
        let current = app.staticTexts["timers.current"]
        XCTAssertTrue(current.waitForExistence(timeout: 5))
        XCTAssertEqual(current.label, title)
        XCTAssertGreaterThan(current.frame.height, 80)
        let pause = app.buttons["timers.pause-resume"]
        if !pause.isHittable { scrollLongTimerTitle(in: app) }
        XCTAssertTrue(pause.isHittable); pause.tap()
        XCTAssertTrue(app.staticTexts["timers.paused"].waitForExistence(timeout: 5))
        XCTAssertEqual(current.label, title)
        record("WatchFullPausedTaskTitle", app)
    }
    override func setUpWithError() throws { continueAfterFailure = false }
    private func scrollLongTimerTitle(in app: XCUIApplication) {
        // Scroll within the current page before swiping past its bottom.
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.8))
        let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.3))
        from.press(forDuration: 0.01, thenDragTo: to)
    }
    private func revealWatchControl(_ control: XCUIElement, in app: XCUIApplication) {
        for attempt in 0..<20 {
            if control.exists, control.isHittable { return }
            let frame = control.exists ? control.frame : .null
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
            let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))
            if (!frame.isNull && frame.maxY < 70) || (frame.isNull && attempt >= 10) {
                to.press(forDuration: 0.01, thenDragTo: from)
            } else { from.press(forDuration: 0.01, thenDragTo: to) }
        }
        XCTAssertTrue(control.exists); XCTAssertTrue(control.isHittable)
    }
    private func swipeTimerPage(_ app: XCUIApplication, toQueue: Bool) {
        if !toQueue {
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
            let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
            from.press(forDuration: 0.01, thenDragTo: to, withVelocity: .fast, thenHoldForDuration: 0)
            XCTAssertTrue(app.buttons["timers.restart"].waitForExistence(timeout: 5) || app.buttons["timers.start"].exists)
            return
        }
        let ring = app.descendants(matching: .any).matching(identifier: "timers.progress").firstMatch
        XCTAssertTrue(ring.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(ring.frame.width, 80)
        XCTAssertGreaterThan(ring.frame.height, 80)
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.85))
        let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.2))
        from.press(forDuration: 0.01, thenDragTo: to, withVelocity: .fast, thenHoldForDuration: 0)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "timers.queue-list").firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["timers.current"].waitForNonExistence(timeout: 5))
        XCTAssertFalse(app.buttons["timers.options"].exists)
        XCTAssertFalse(app.buttons["timers.dictate"].exists)
        XCTAssertFalse(app.buttons["timers.alarm-settings"].exists)
        XCTAssertFalse(app.buttons["timers.watch-home"].exists)
    }
    private func allowTimerNotifications(_ app: XCUIApplication) {
        let carousel = XCUIApplication(bundleIdentifier: "com.apple.Carousel")
        if carousel.alerts.buttons["Allow"].waitForExistence(timeout: 2) { carousel.alerts.buttons["Allow"].tap() }
        if app.alerts.buttons["Allow"].waitForExistence(timeout: 1) { app.alerts.buttons["Allow"].tap() }
    }
    override func tearDownWithError() throws {
        if (testRun?.totalFailureCount ?? 0) > 0 {
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
        // Consume this test's actual 15-second alert before another test opens
        // dictation. Otherwise the system notification can swallow Cancel.
        let delivered = carousel.alerts.firstMatch
        if delivered.waitForExistence(timeout: 20) {
            for _ in 0..<4 {
                if !delivered.exists { break }
                let dismiss = carousel.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Dismiss"))
                    .allElementsBoundByIndex.last(where: { $0.isHittable })
                if let dismiss { dismiss.tap() }
                else { delivered.swipeUp() }
            }
            XCTAssertTrue(delivered.waitForNonExistence(timeout: 10))
        }
        app.activate()
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
