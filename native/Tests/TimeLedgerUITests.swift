import XCTest

final class TimeLedgerUITests: XCTestCase {
    func testUrgentTasksRotateInRepeatingCheckInsAndCompletedTasksDisappear() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-empty-ledger", "--ui-urgent-checkins", "--ui-inspect-checkins"]
        app.launch(); openCheckInInspector(app)
        let expected = ["Pay rent", "Reschedule the class", "Reply to Jo"]
        for (index, title) in expected.enumerated() {
            let body = element(app, "checkins.inspect.body.\(index)"); reveal(body, in: app)
            XCTAssertTrue(body.label.contains("Tap to type or dictate"))
            XCTAssertTrue(body.label.hasPrefix("Urgent: " + title))
            let payload = element(app, "checkins.inspect.task.\(index)"); reveal(payload, in: app)
            XCTAssertEqual(payload.label, title)
        }
        let kind = element(app, "checkins.inspect.kind.0"); reveal(kind, in: app)
        XCTAssertEqual(kind.label, "CHECKIN · repeating")
        let action = element(app, "checkins.inspect.action"); reveal(action, in: app)
        XCTAssertEqual(action.label, "QUICK_LOG")
        let count = element(app, "checkins.inspect.count"); reveal(count, in: app)
        XCTAssertEqual(count.label, "3 check-ins")
        let date = element(app, "checkins.inspect.date.0"); reveal(date, in: app)
        let originalDate = date.label
        refreshCheckInInspector(app)
        reveal(date, in: app); XCTAssertEqual(date.label, originalDate)
        recordScreen("UrgentTaskInScheduledCheckIn", in: app)
        app.tabBars.buttons["Today"].tap()
        for id in ["checkin-rent", "checkin-class", "checkin-reply"] {
            let done = app.buttons["today.urgent-complete.uncategorized.\(id)"]
            reveal(done, in: app); XCTAssertTrue(done.isHittable); done.tap()
        }
        app.tabBars.buttons["Settings"].tap(); refreshCheckInInspector(app)
        let body = element(app, "checkins.inspect.body.0"); reveal(body, in: app)
        let plain = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Tap to type or dictate what you’re doing now."), object: body)
        XCTAssertEqual(XCTWaiter.wait(for: [plain], timeout: 10), .completed)
        reveal(count, in: app); XCTAssertEqual(count.label, "3 check-ins")
    }

    func testUrgentCheckInRandomQueueKeepsItsTimesAndContentAfterRelaunch() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-empty-ledger", "--ui-urgent-checkins", "--ui-inspect-checkins"]
        app.launch(); openCheckInInspector(app)
        app.navigationBars.buttons.firstMatch.tap()
        let timing = element(app, "settings.notification-timing"); reveal(timing, in: app)
        timing.tap(); app.buttons["Randomized"].tap()
        let save = app.buttons["settings.save-notifications"]; reveal(save, in: app); save.tap()
        let saved = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: save)
        XCTAssertEqual(XCTWaiter.wait(for: [saved], timeout: 15), .completed)
        let inspect = app.buttons["settings.checkin-preview"]; reveal(inspect, in: app); inspect.tap()
        let count = element(app, "checkins.inspect.count")
        let queued = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "60 check-ins"), object: count)
        XCTAssertEqual(XCTWaiter.wait(for: [queued], timeout: 10), .completed)
        let kind = element(app, "checkins.inspect.kind.0"); reveal(kind, in: app)
        XCTAssertEqual(kind.label, "CHECKIN · queued")
        let body = element(app, "checkins.inspect.body.0"); reveal(body, in: app)
        XCTAssertTrue(body.label.contains("Urgent: Pay rent"))
        let originalBody = body.label
        let date = element(app, "checkins.inspect.date.0"); reveal(date, in: app)
        let originalDate = date.label
        refreshCheckInInspector(app)
        reveal(date, in: app); XCTAssertEqual(date.label, originalDate)
        app.terminate(); app.launchArguments = ["--ui-inspect-checkins"]; app.launch(); openCheckInInspector(app)
        reveal(date, in: app); XCTAssertEqual(date.label, originalDate)
        reveal(body, in: app); XCTAssertEqual(body.label, originalBody)
        recordScreen("UrgentTaskRandomQueueAfterRelaunch", in: app)
    }

    private func openCheckInInspector(_ app: XCUIApplication) {
        app.tabBars.buttons["Settings"].tap()
        let inspect = app.buttons["settings.checkin-preview"]
        reveal(inspect, in: app); inspect.tap()
        let allow = app.alerts.buttons["Allow"]
        if allow.waitForExistence(timeout: 2) { allow.tap() }
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        if springboard.alerts.buttons["Allow"].waitForExistence(timeout: 2) { springboard.alerts.buttons["Allow"].tap() }
        let count = element(app, "checkins.inspect.count")
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != %@", "0 check-ins"), object: count)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 15), .completed)
    }

    private func refreshCheckInInspector(_ app: XCUIApplication) {
        let refresh = app.buttons["checkins.inspect.refresh"]
        XCTAssertTrue(refresh.waitForExistence(timeout: 5))
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: refresh)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 15), .completed)
        refresh.tap()
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: refresh)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 15), .completed)
    }
    func testHapticsOnlySystemAlarmSettingPersistsWithoutRearmingStoppedAlarm() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-empty-ledger", "--ui-timer-fixture", "--ui-alarmkit-available", "--ui-quiet-timer-alerts"]
        app.launch()
        let status = element(app, "timers.phone-alarm-status")
        XCTAssertTrue(status.waitForExistence(timeout: 20)); XCTAssertEqual(status.label, "iPhone system alarm scheduled")
        let settings = app.buttons["Timer settings"]; reveal(settings, in: app); settings.tap()
        let toggle = app.switches["timers.system-alarm-silent"]
        reveal(toggle, in: app); XCTAssertEqual(toggle.value as? String, "0")
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        let settingsStatus = element(app, "timers.system-alarm-settings-status")
        let quiet = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "haptics only"), object: settingsStatus)
        XCTAssertEqual(XCTWaiter.wait(for: [quiet], timeout: 10), .completed)
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["timers.restart"].tap()
        XCTAssertTrue(status.label.contains("haptics only"))
        app.terminate(); app.launchArguments = ["--ui-timer-open", "--ui-alarmkit-available", "--ui-quiet-timer-alerts"]; app.launch()
        XCTAssertTrue(status.waitForExistence(timeout: 20)); XCTAssertTrue(status.label.contains("haptics only"))
        reveal(settings, in: app); settings.tap(); reveal(toggle, in: app)
        XCTAssertEqual(toggle.value as? String, "1")
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        let normal = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "iPhone system alarm scheduled"), object: settingsStatus)
        XCTAssertEqual(XCTWaiter.wait(for: [normal], timeout: 10), .completed)
        app.terminate(); app.launchArguments = ["--ui-timer-open", "--ui-alarmkit-available", "--ui-system-alarm-silence", "--ui-quiet-timer-alerts"]; app.launch()
        XCTAssertTrue(status.waitForExistence(timeout: 20))
        let silenced = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "silenced"), object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [silenced], timeout: 10), .completed)
        reveal(settings, in: app); settings.tap(); reveal(toggle, in: app)
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        XCTAssertTrue(settingsStatus.label.contains("silenced"))
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertEqual(element(app, "timers.current").label, "Practice guitar")
        app.buttons["timers.restart"].tap()
        let restarted = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "haptics only"), object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [restarted], timeout: 10), .completed)
        let email = element(app, "timers.waiting.timer-email"); reveal(email, in: app); XCTAssertTrue(email.exists)
        recordScreen("SystemAlarmHapticsOnlySetting", in: app)
    }
    func testSystemAlarmStopCanCompleteAndStartNextWithoutOpeningWatch() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-empty-ledger", "--ui-timer-fixture", "--ui-alarmkit-available", "--ui-quiet-timer-alerts"]
        app.launch()
        XCTAssertTrue(element(app, "timers.current").waitForExistence(timeout: 20))
        let settings = app.buttons["Timer settings"]; reveal(settings, in: app); settings.tap()
        let toggle = app.switches["timers.system-alarm-stop-completes"]
        reveal(toggle, in: app); XCTAssertEqual(toggle.value as? String, "0")
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "1"), object: toggle)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 5), .completed)
        app.terminate(); app.launchArguments = ["--ui-timer-open", "--ui-alarmkit-available", "--ui-system-alarm-expired", "--ui-quiet-timer-alerts"]; app.launch()
        let current = element(app, "timers.current")
        XCTAssertTrue(current.waitForExistence(timeout: 20))
        let next = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Answer email"), object: current)
        XCTAssertEqual(XCTWaiter.wait(for: [next], timeout: 10), .completed)
        XCTAssertTrue(element(app, "timers.countdown").exists)
        let status = element(app, "timers.phone-alarm-status")
        XCTAssertTrue(status.waitForExistence(timeout: 10)); XCTAssertEqual(status.label, "iPhone system alarm scheduled")
        XCTAssertFalse(element(app, "timers.waiting.timer-guitar").exists)
        let walk = element(app, "timers.waiting.timer-walk"); reveal(walk, in: app); XCTAssertTrue(walk.exists)
        app.terminate(); app.launchArguments = ["--ui-timer-open", "--ui-alarmkit-available", "--ui-quiet-timer-alerts"]; app.launch()
        XCTAssertTrue(current.waitForExistence(timeout: 20)); XCTAssertEqual(current.label, "Answer email")
        reveal(settings, in: app); settings.tap(); reveal(toggle, in: app)
        XCTAssertEqual(toggle.value as? String, "1")
        recordScreen("SystemAlarmStopStartsNext", in: app)
    }
    func testSystemAlarmTrialSchedulesRestartsAndPersistsWithoutChangingQueue() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-empty-ledger", "--ui-timer-fixture", "--ui-alarmkit-available", "--ui-live-timer-restart", "--ui-quiet-timer-alerts"]
        app.launch()
        let status = element(app, "timers.phone-alarm-status")
        XCTAssertTrue(status.waitForExistence(timeout: 20)); XCTAssertEqual(status.label, "iPhone system alarm scheduled")
        XCTAssertEqual(element(app, "timers.current").label, "Practice guitar")
        app.buttons["timers.pause-resume"].tap()
        XCTAssertTrue(element(app, "timers.paused").waitForExistence(timeout: 5))
        app.buttons["timers.pause-resume"].tap()
        XCTAssertTrue(status.waitForExistence(timeout: 5)); XCTAssertEqual(status.label, "iPhone system alarm scheduled")
        app.terminate(); app.launchArguments = ["--ui-timer-open", "--ui-alarmkit-available", "--ui-quiet-timer-alerts"]; app.launch()
        XCTAssertTrue(status.waitForExistence(timeout: 20)); XCTAssertEqual(status.label, "iPhone system alarm scheduled")
        XCTAssertEqual(element(app, "timers.current").label, "Practice guitar")
        let email = element(app, "timers.waiting.timer-email"); reveal(email, in: app); XCTAssertTrue(email.exists)
        let settings = app.buttons["Timer settings"]; reveal(settings, in: app); settings.tap()
        let toggle = app.switches["timers.system-alarms"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5)); XCTAssertEqual(toggle.value as? String, "1")
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        let disabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "0"), object: toggle)
        XCTAssertEqual(XCTWaiter.wait(for: [disabled], timeout: 5), .completed)
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "1"), object: toggle)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 5), .completed)
        recordScreen("SystemAlarmTrialSettings", in: app)
    }
    func testDeniedSystemAlarmPermissionKeepsExistingTimer() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-empty-ledger", "--ui-timer-fixture", "--ui-alarmkit-denied", "--ui-quiet-timer-alerts"]; app.launch()
        XCTAssertTrue(element(app, "timers.current").waitForExistence(timeout: 20))
        let settings = app.buttons["Timer settings"]; reveal(settings, in: app); settings.tap()
        let toggle = app.switches["timers.system-alarms"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5)); XCTAssertEqual(toggle.value as? String, "0")
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        let status = element(app, "timers.system-alarm-settings-status")
        XCTAssertTrue(status.waitForExistence(timeout: 5)); XCTAssertTrue(status.label.contains("not allowed"))
        XCTAssertEqual(toggle.value as? String, "0")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertEqual(element(app, "timers.current").label, "Practice guitar")
        XCTAssertTrue(element(app, "timers.countdown").exists)
    }
    func testSystemAlarmFailureKeepsTimerAndNotificationFallback() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-empty-ledger", "--ui-timer-fixture", "--ui-alarmkit-fail"]; app.launch()
        let status = element(app, "timers.phone-alarm-status")
        XCTAssertTrue(status.waitForExistence(timeout: 20))
        let enable = app.buttons["Enable timer notifications"]
        if enable.waitForExistence(timeout: 2) {
            reveal(enable, in: app); enable.tap()
            let allow = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.buttons["Allow"]
            if allow.waitForExistence(timeout: 3) { allow.tap() }
        }
        let fallback = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "System alarm unavailable · notification backup scheduled"), object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [fallback], timeout: 10), .completed)
        XCTAssertEqual(element(app, "timers.current").label, "Practice guitar")
        app.buttons["timers.restart"].tap()
        XCTAssertTrue(element(app, "timers.countdown").exists)
        XCTAssertEqual(element(app, "timers.current").label, "Practice guitar")
        let email = element(app, "timers.waiting.timer-email"); reveal(email, in: app); XCTAssertTrue(email.exists)
    }
    func testStoppingSystemAlarmDoesNotCompleteTask() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-empty-ledger", "--ui-timer-fixture", "--ui-alarmkit-available", "--ui-system-alarm-silence", "--ui-quiet-timer-alerts"]; app.launch()
        let status = element(app, "timers.phone-alarm-status")
        XCTAssertTrue(status.waitForExistence(timeout: 20))
        let stopped = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "silenced"), object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [stopped], timeout: 10), .completed)
        XCTAssertEqual(element(app, "timers.current").label, "Practice guitar")
        app.terminate(); app.launchArguments = ["--ui-timer-open", "--ui-alarmkit-available", "--ui-quiet-timer-alerts"]; app.launch()
        XCTAssertTrue(status.waitForExistence(timeout: 20)); XCTAssertTrue(status.label.contains("silenced"))
        XCTAssertEqual(element(app, "timers.current").label, "Practice guitar")
        app.buttons["timers.restart"].tap()
        let armed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "iPhone system alarm scheduled"), object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [armed], timeout: 10), .completed)
        recordScreen("SystemAlarmStopPreservesTask", in: app)
    }
    private static var preparedKeyboard = false
    override func setUpWithError() throws {
        guard !Self.preparedKeyboard else { return }
        // Cold simulators can put QuickPath's introduction over the keyboard
        // toolbar. Acknowledge Apple's setup before exercising Dash's controls.
        let app = XCUIApplication(); app.launchArguments = ["--ui-empty-ledger"]; app.launch()
        let log = app.buttons["today.log"]
        XCTAssertTrue(log.waitForExistence(timeout: 20)); log.tap()
        let field = app.textFields["checkin.activity"]
        XCTAssertTrue(field.waitForExistence(timeout: 10)); field.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 10))
        let introduction = app.otherElements["UIContinuousPathIntroductionView"]
        if introduction.waitForExistence(timeout: 2) { dismissKeyboardIntroduction(in: app) }
        field.typeText("Keyboard setup")
        dismissKeyboardIntroduction(in: app)
        app.terminate(); Self.preparedKeyboard = true
    }
    private func dismissKeyboardIntroduction(in app: XCUIApplication) {
        let introduction = app.otherElements["UIContinuousPathIntroductionView"]
        if introduction.exists {
            let button = introduction.buttons["Continue"]
            XCTAssertTrue(button.waitForExistence(timeout: 5)); button.tap()
            XCTAssertTrue(introduction.waitForNonExistence(timeout: 5))
        }
    }
    func testPhoneRestartRetainsWatchAlertsAndOffersExplicitPhoneTakeover() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-empty-ledger", "--ui-timer-fixture", "--ui-watch-owned-timer", "--ui-live-timer-restart", "--ui-quiet-timer-alerts"]
        app.launch()
        XCTAssertTrue(element(app, "timers.countdown").waitForExistence(timeout: 20))
        XCTAssertEqual(element(app, "timers.current").label, "Practice guitar")
        let hint = element(app, "timers.watch-rearm"); reveal(hint, in: app)
        XCTAssertTrue(hint.exists)
        XCTAssertTrue(app.staticTexts["Alerts on Apple Watch"].exists)
        let takeover = app.buttons["timers.alerts-here"]; reveal(takeover, in: app); takeover.tap()
        XCTAssertTrue(app.staticTexts["Alerts on iPhone"].waitForExistence(timeout: 5))
        XCTAssertFalse(hint.exists)
        app.terminate(); app.launchArguments = ["--ui-timer-open", "--ui-quiet-timer-alerts"]; app.launch()
        XCTAssertTrue(app.staticTexts["Alerts on iPhone"].waitForExistence(timeout: 20))
        XCTAssertEqual(element(app, "timers.current").label, "Practice guitar")
    }
    func testSpokenTimerDraftCanRunWithoutAPreexistingTask() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-empty-ledger", "--ui-siri-timers", "--ui-quiet-timer-alerts"]; app.launch()
        let current = element(app, "timers.current")
        XCTAssertTrue(current.waitForExistence(timeout: 20)); XCTAssertEqual(current.label, "Eat food")
        let food = app.staticTexts["Cook food"]; reveal(food, in: app); XCTAssertTrue(food.exists)
        XCTAssertTrue(app.staticTexts["10:00"].exists)
        recordScreen("SiriTimerTaskSlotExecuted", in: app)
        app.terminate(); app.launchArguments = ["--ui-timer-open", "--ui-quiet-timer-alerts"]; app.launch()
        XCTAssertTrue(current.waitForExistence(timeout: 20)); XCTAssertEqual(current.label, "Eat food")
    }
    func testTimersHaveOwnTabCanCreateEditReorderAndPersist() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--ui-empty-ledger", "--ui-timer-fixture", "--ui-quiet-timer-alerts"]; app.launch()
        XCTAssertTrue(app.tabBars.buttons["Timers"].waitForExistence(timeout: 20))
        XCTAssertFalse(app.tabBars.buttons["More"].exists)
        XCTAssertTrue(element(app, "timers.current").waitForExistence(timeout: 10))
        XCTAssertEqual(element(app, "timers.current").label, "Practice guitar")
        let email = element(app, "timers.waiting.timer-email"), walk = element(app, "timers.waiting.timer-walk")
        reveal(walk, in: app)
        app.buttons["timers.reorder"].tap()
        let walkCell = app.cells.containing(.any, identifier: "timers.waiting.timer-walk").firstMatch
        let emailCell = app.cells.containing(.any, identifier: "timers.waiting.timer-email").firstMatch
        let handle = walkCell.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Reorder")).firstMatch
        XCTAssertTrue(handle.waitForExistence(timeout: 5))
        recordScreen("PhoneTimerReorderHandles", in: app)
        let from = handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let to = emailCell.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1))
        from.press(forDuration: 0.5, thenDragTo: to)
        app.buttons["timers.reorder"].tap()
        XCTAssertLessThan(walk.frame.minY, email.frame.minY)
        reveal(app.buttons["timers.done"], in: app); app.buttons["timers.done"].tap()
        XCTAssertEqual(element(app, "timers.current").label, "Take a walk")
        element(app, "timers.current").tap()
        let title = element(app, "timers.edit-title"); XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        title.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 40) + "Walk outside")
        let minutes = app.textFields["timers.edit-minutes"]; minutes.tap()
        minutes.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: (minutes.value as? String ?? "").count) + "8")
        app.buttons["timers.edit-save"].tap()
        XCTAssertEqual(element(app, "timers.current").label, "Walk outside")
        let field = element(app, "timers.draft"); reveal(field, in: app); field.tap(); field.typeText("Make tea")
        app.buttons["timers.add"].tap()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        if springboard.alerts.buttons["Allow"].waitForExistence(timeout: 2) { springboard.alerts.buttons["Allow"].tap() }
        recordScreen("PhoneTimersOwnTab", in: app)
        app.terminate(); app.launchArguments = ["--ui-timer-open", "--ui-quiet-timer-alerts"]; app.launch()
        XCTAssertTrue(element(app, "timers.current").waitForExistence(timeout: 20))
        XCTAssertEqual(element(app, "timers.current").label, "Walk outside")
        reveal(email, in: app); XCTAssertTrue(email.exists)
        let tea = app.staticTexts["Make tea"]; reveal(tea, in: app); XCTAssertTrue(tea.exists)
    }
    func testInboxCaptureCanReturnToTimersTab() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--ui-empty-ledger", "--ui-timer-fixture", "--ui-quiet-timer-alerts"]; app.launch()
        XCTAssertTrue(element(app, "timers.current").waitForExistence(timeout: 20))
        openInbox(app, capture: true)
        let field = element(app, "inbox.text"); XCTAssertTrue(field.waitForExistence(timeout: 10)); field.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 10))
        app.navigationBars["Inbox"].tap()
        let hidden = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.keyboards.firstMatch)
        XCTAssertEqual(XCTWaiter.wait(for: [hidden], timeout: 5), .completed)
        let timers = app.tabBars.buttons["Timers"]
        let visible = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: timers)
        XCTAssertEqual(XCTWaiter.wait(for: [visible], timeout: 10), .completed)
        XCTAssertFalse(app.buttons["inbox.timers"].exists); timers.tap()
        XCTAssertTrue(element(app, "timers.current").waitForExistence(timeout: 10))
        XCTAssertEqual(element(app, "timers.current").label, "Practice guitar")
    }
    func testCompactInboxKeepsTitleInlineAndAllOtherEditingInDetails() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-inbox-fixture"]; app.launch()
        openInbox(app)
        editInline("inbox.details.a", adding: " updated", in: app)
        XCTAssertFalse(app.buttons["inbox.actions.a"].exists)
        XCTAssertFalse(app.buttons["inbox.timing.a"].exists)
        XCTAssertFalse(app.buttons["inbox.category.a"].exists)
        XCTAssertTrue(app.buttons["inbox.complete.a"].exists)
        openIdeaEditor("a", in: app)
        let categories = app.buttons["task-planning.categories"]
        reveal(categories, in: app); categories.tap()
        tapCategory("work", in: app); tapCategory("social", in: app)
        app.buttons["idea-categories.done"].tap()
        editInline("task-planning.notes", adding: "Details belong in the editor", in: app)
        setPlanNumber("task-planning.hours", to: "0.5", in: app)
        app.buttons["task-planning.save"].tap()
        let names = element(app, "inbox.categories.a"); reveal(names, in: app)
        XCTAssertTrue(names.label.contains("Work")); XCTAssertTrue(names.label.contains("Socializing"))
        XCTAssertTrue(element(app, "inbox.has-notes.a").exists)
        XCTAssertLessThan(names.frame.height, 30)
        recordScreen("CompactInboxSummary", in: app)
        openIdeaEditor("a", in: app)
        XCTAssertEqual(element(app, "task-planning.notes").label, "Details belong in the editor")
        XCTAssertEqual(app.textFields["task-planning.hours"].value as? String, "0.5")
        recordScreen("UnifiedInboxEditor", in: app)
        app.buttons["task-planning.save"].tap()
        swipeIdeaAction("a", action: "reference", in: app)
        let reference = element(app, "inbox.reference-title"); reveal(reference, in: app)
        XCTAssertTrue(reference.label.contains("1"))
    }

    func testDashboardArrowsBrowseDaysAndSevenDayWindows() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-allocation-fixture"]; app.launch()
        let previous = app.buttons["report.previous"], next = app.buttons["report.next"]
        XCTAssertTrue(previous.waitForExistence(timeout: 20)); XCTAssertFalse(next.isEnabled)
        previous.tap()
        XCTAssertEqual(element(app, "report.range").value as? String, "Yesterday")
        XCTAssertTrue(element(app, "report.tracked").label.contains("1 logs"))
        XCTAssertTrue(next.isEnabled)
        recordScreen("DashboardYesterdayArrows", in: app)
        next.tap()
        XCTAssertEqual(element(app, "report.range").value as? String, "Today")
        XCTAssertFalse(next.isEnabled)
        element(app, "report.range").tap(); app.buttons["Past 7 days"].tap()
        previous.tap()
        XCTAssertTrue(next.isEnabled)
        XCTAssertTrue(element(app, "report.tracked").label.contains("0 logs"))
        recordScreen("DashboardPreviousWeekArrows", in: app)
        next.tap(); XCTAssertFalse(next.isEnabled)
        element(app, "report.range").tap(); app.buttons["All time"].tap()
        XCTAssertFalse(previous.exists); XCTAssertFalse(next.exists)
        element(app, "report.range").tap(); app.buttons["Custom"].tap()
        XCTAssertTrue(element(app, "report.from").exists); XCTAssertTrue(element(app, "report.through").exists)
    }

    func testTimerAutoNextCanBeDisabledAndManualStartPersists() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-empty-ledger", "--ui-timer-fixture"]; app.launch()
        XCTAssertTrue(app.buttons["timers.done"].waitForExistence(timeout: 20))
        app.tabBars.buttons["Settings"].tap()
        app.buttons["settings.timers"].tap()
        let setting = element(app, "timers.auto-next")
        XCTAssertTrue(setting.waitForExistence(timeout: 5))
        XCTAssertEqual(setting.value as? String, "1")
        // SwiftUI's accessibility frame includes the label. Tap the actual
        // switch track, rather than the label in the middle of that frame.
        setting.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        let off = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "0"), object: setting)
        XCTAssertEqual(XCTWaiter.wait(for: [off], timeout: 5), .completed)
        app.tabBars.buttons["Timers"].tap()
        XCTAssertTrue(app.buttons["timers.done"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons["timers.done"].label, "Done")
        app.buttons["timers.done"].tap()
        XCTAssertTrue(app.buttons["timers.start"].waitForExistence(timeout: 5))
        XCTAssertFalse(element(app, "timers.current").exists)
        app.buttons["timers.start"].tap()
        XCTAssertEqual(element(app, "timers.current").label, "Answer email")
        app.terminate(); app.launchArguments = ["--ui-timer-open"]; app.launch()
        XCTAssertTrue(app.buttons["timers.done"].waitForExistence(timeout: 20))
        app.buttons["timers.done"].tap()
        XCTAssertTrue(app.buttons["timers.start"].waitForExistence(timeout: 5))
        recordScreen("TimerManualNext", in: app)
    }
    func testUrgentInboxShowsUnrankedIdeasAndCorrectionPersistsWithoutRanking() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-urgent-inbox"]; app.launch()
        openInbox(app)
        let urgent = app.staticTexts["inbox.urgent-title"]
        reveal(urgent, in: app); XCTAssertEqual(urgent.label, "Urgent (3)")
        openIdeaEditor("alan", prefix: "inbox.urgent", in: app)
        let timing = element(app, "task-planning.timing"); reveal(timing, in: app); timing.tap()
        app.buttons["No date"].tap(); app.buttons["task-planning.save"].tap()
        XCTAssertEqual(urgent.label, "Urgent (2)")
        XCTAssertFalse(app.navigationBars["Rank ideas"].exists)
        recordScreen("InboxUrgentWithoutRanking", in: app)
        app.terminate(); app.launchArguments = []; app.launch(); openInbox(app)
        reveal(urgent, in: app); XCTAssertEqual(urgent.label, "Urgent (2)")
        XCTAssertFalse(app.buttons["inbox.urgent.dismiss.alan"].exists)
        let title = app.staticTexts["inbox.ranked-title"]; reveal(title, in: app)
        XCTAssertTrue(title.label.contains("(1)"))
    }
    func testTodayShowsGroupedUrgentTasksBelowDashboardWithHelpAndTopReview() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-empty-ledger", "--ui-today-urgent"]; app.launch()
        let review = app.buttons["dashboard.review.uncategorized"]
        XCTAssertTrue(review.waitForExistence(timeout: 10)); XCTAssertTrue(review.isHittable)
        XCTAssertFalse(app.buttons["dashboard.groups"].exists)
        let help = app.buttons["dashboard.help"]
        help.tap()
        XCTAssertTrue(element(app, "dashboard.help-content").waitForExistence(timeout: 5))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap()
        XCTAssertTrue(element(app, "dashboard.help-content").waitForNonExistence(timeout: 5))
        let urgent = app.staticTexts["today.urgent-title"]
        reveal(urgent, in: app); XCTAssertEqual(urgent.label, "Urgent tasks (3)")
        XCTAssertGreaterThan(urgent.frame.minY, element(app, "dashboard.breakdown-title").frame.minY)
        XCTAssertTrue(app.staticTexts["today.urgent-category.music"].exists)
        XCTAssertEqual(app.staticTexts["today.urgent-category.teaching"].label, "Work › Teaching")
        XCTAssertTrue(app.staticTexts["today.urgent-category.uncategorized"].exists)
        XCTAssertFalse(app.buttons["today.urgent-task.music.guitar"].exists)
        let complete = app.buttons["today.urgent-complete.music.joe"]
        reveal(complete, in: app); complete.tap()
        XCTAssertEqual(urgent.label, "Urgent tasks (2)")
        XCTAssertFalse(app.buttons["today.urgent-task.music.joe"].exists)
        XCTAssertFalse(app.buttons["today.urgent-task.teaching.joe"].exists)
        XCTAssertTrue(review.isHittable)
        recordScreen("TodayGroupedUrgentTasks", in: app)
    }
    func testTodayUrgencyCorrectionPersistsAndUpdatesInbox() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-empty-ledger", "--ui-today-urgent"]; app.launch()
        let task = app.buttons["today.urgent-task.teaching.alan"]
        reveal(task, in: app); task.tap()
        let timing = element(app, "task-planning.timing"); reveal(timing, in: app); timing.tap()
        app.buttons["No date"].tap(); app.buttons["task-planning.save"].tap()
        let urgent = app.staticTexts["today.urgent-title"]
        reveal(urgent, in: app); XCTAssertEqual(urgent.label, "Urgent tasks (2)")
        app.terminate(); app.launchArguments = []; app.launch()
        reveal(urgent, in: app); XCTAssertEqual(urgent.label, "Urgent tasks (2)")
        XCTAssertFalse(task.exists)
        openInbox(app)
        let inboxUrgent = app.staticTexts["inbox.urgent-title"]
        reveal(inboxUrgent, in: app); XCTAssertEqual(inboxUrgent.label, "Urgent (2)")
    }
    func testLiveActivityRestartIntentRestartsExpiredTimerWithoutChangingQueue() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-empty-ledger", "--ui-timer-fixture", "--ui-live-timer-restart"]
        app.launch()
        XCTAssertTrue(element(app, "timers.countdown").waitForExistence(timeout: 20))
        XCTAssertEqual(element(app, "timers.current").label, "Practice guitar")
        XCTAssertTrue(element(app, "timers.waiting.timer-email").exists)
        XCTAssertTrue(element(app, "timers.waiting.timer-walk").exists)
        XCTAssertFalse(element(app, "timers.finished").exists)
        recordScreen("LiveActivityRestartIntent", in: app)
    }
    func testAutomaticMatchingSettingsCanAddPhraseAndCategoryRule() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-urgent-inbox"]; app.launch()
        app.tabBars.buttons["Settings"].tap()
        app.buttons["settings.matching"].tap()
        let test = element(app, "matching.test"); reveal(test, in: app)
        test.tap(); test.typeText("Playing piano")
        XCTAssertEqual(app.staticTexts["matching.test-categories"].label, "Music")
        if app.buttons["keyboard.done"].isHittable { app.buttons["keyboard.done"].tap() }
        let phrase = app.textFields["matching.new-rule-phrase"]; reveal(phrase, in: app)
        phrase.tap(); phrase.typeText("cello")
        if app.buttons["keyboard.done"].isHittable { app.buttons["keyboard.done"].tap() }
        let category = element(app, "matching.new-rule-category"); reveal(category, in: app); category.tap()
        let music = element(app, "matching.category-option.music")
        XCTAssertTrue(music.waitForExistence(timeout: 5)); music.tap()
        let add = app.buttons["matching.add-rule"]; reveal(add, in: app); add.tap()
        recordScreen("AutomaticMatchingSettings", in: app)
        let urgency = app.buttons["matching.urgency"]; reveal(urgency, in: app); urgency.tap()
        let newPhrase = app.textFields["matching.new-urgency-phrase"]; reveal(newPhrase, in: app)
        newPhrase.tap(); newPhrase.typeText("renew passport")
        if app.buttons["keyboard.done"].isHittable { app.buttons["keyboard.done"].tap() }
        let addPhrase = app.buttons["matching.add-urgency-phrase"]; reveal(addPhrase, in: app); addPhrase.tap()
        XCTAssertTrue(app.staticTexts["renew passport"].exists)
    }
    func testTimerQueueRestartDoneNextPauseAndPersistence() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-empty-ledger", "--ui-timer-fixture"]
        app.launch()
        XCTAssertTrue(app.buttons["timers.restart"].waitForExistence(timeout: 20))
        XCTAssertEqual(element(app, "timers.current").label, "Practice guitar")
        recordScreen("PhoneTimerExpired", in: app)
        app.buttons["timers.restart"].tap()
        XCTAssertTrue(app.buttons["timers.pause-resume"].waitForExistence(timeout: 10))
        XCTAssertEqual(element(app, "timers.current").label, "Practice guitar")
        app.buttons["timers.done"].tap()
        XCTAssertEqual(element(app, "timers.current").label, "Answer email")
        app.buttons["timers.pause-resume"].tap()
        XCTAssertTrue(app.staticTexts["timers.paused"].waitForExistence(timeout: 10))
        recordScreen("PhoneTimerPaused", in: app)
        app.terminate(); app.launchArguments = ["--ui-timer-open"]; app.launch()
        XCTAssertTrue(app.staticTexts["timers.paused"].waitForExistence(timeout: 20))
        XCTAssertEqual(element(app, "timers.current").label, "Answer email")
        app.buttons["timers.pause-resume"].tap()
        XCTAssertFalse(app.staticTexts["timers.paused"].exists)
        app.buttons["timers.done"].tap()
        XCTAssertEqual(element(app, "timers.current").label, "Take a walk")
    }
    func testTimerQueueCanRemoveWaitingTaskAndDoesNotCreateActivityLogs() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-empty-ledger", "--ui-timer-fixture"]
        app.launch()
        let removeEmail = app.buttons["timers.delete.timer-email"]
        XCTAssertTrue(app.buttons["timers.restart"].waitForExistence(timeout: 20))
        let email = element(app, "timers.waiting.timer-email"); reveal(email, in: app); email.swipeLeft()
        XCTAssertTrue(removeEmail.waitForExistence(timeout: 5)); removeEmail.tap()
        XCTAssertFalse(removeEmail.exists)
        reveal(app.buttons["timers.done"], in: app); app.buttons["timers.done"].tap()
        XCTAssertEqual(element(app, "timers.current").label, "Take a walk")
        showToday(app)
        recordScreen("PhoneTimerQueueDoesNotLogPlannedTime", in: app)
        XCTAssertFalse(app.staticTexts["Practice guitar"].exists)
    }
    private func recordScreen(_ name: String, in app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.state == .runningForeground ? app.screenshot() : XCUIScreen.main.screenshot())
        attachment.name = "Review-\(name).png"; attachment.lifetime = .keepAlways
        add(attachment)
    }
    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func reveal(_ target: XCUIElement, in app: XCUIApplication) {
        func usable(_ frame: CGRect) -> Bool {
            !frame.isNull && !frame.isInfinite && !frame.isEmpty &&
                [frame.minX, frame.minY, frame.maxX, frame.maxY].allSatisfy { $0.isFinite }
        }
        func visibleFrame(_ query: XCUIElementQuery, in bounds: CGRect) -> CGRect? {
            // Bound indices become stale when a dismissed sheet removes a bar
            // between XCTest snapshots. Resolve one fresh match instead.
            let bar = query.firstMatch
            guard bar.exists else { return nil }
            let frame = bar.frame
            return usable(frame) && frame.intersects(bounds) ? frame : nil
        }
        // Lazy lists omit offscreen rows from accessibility. Search later rows
        // first, then earlier rows if the target has not been materialized.
        for attempt in 0..<20 {
            let bounds = app.frame
            guard usable(bounds) else { XCTFail("App has no visible bounds"); return }
            // Dismissed sheets can leave offscreen bars with CGRect.null frames.
            let navigation = visibleFrame(app.navigationBars, in: bounds)
            let tabs = visibleFrame(app.tabBars, in: bounds)
            let top = max(bounds.minY, min(navigation?.maxY ?? bounds.minY, bounds.maxY))
            var bottom = min(bounds.maxY, max(tabs?.minY ?? bounds.maxY, top))
            if app.keyboards.firstMatch.exists {
                let keyboard = app.keyboards.firstMatch.frame
                if usable(keyboard) { bottom = min(bottom, keyboard.minY) }
            }
            let grouping = app.buttons["plan.group-selected"]
            if grouping.exists && grouping.isHittable && (!target.exists || (target.identifier != "plan.group-selected" && target.identifier != "plan.selection-done")) {
                let bar = grouping.frame
                if usable(bar) { bottom = min(bottom, bar.minY - 16) }
            }
            let proposed = target.exists ? target.frame : .zero
            let frame = usable(proposed) ? proposed : .zero
            if target.exists, !frame.isEmpty, frame.minY >= top, frame.maxY <= bottom - 8 { return }
            // Short drags keep lazy Form rows from being skipped by momentum.
            let height = max(100, bottom - top)
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let high = origin.withOffset(CGVector(dx: app.frame.midX, dy: top + height * 0.3))
            let low = origin.withOffset(CGVector(dx: app.frame.midX, dy: top + height * 0.75))
            if (!frame.isEmpty && frame.maxY < top) || (frame.isEmpty && attempt >= 10) { high.press(forDuration: 0.01, thenDragTo: low) }
            else { low.press(forDuration: 0.01, thenDragTo: high) }

        }
        XCTAssertTrue(target.waitForExistence(timeout: 5))
    }

    private func log(_ text: String, in app: XCUIApplication, confirmSuggestion: Bool = false) {
        openLogPage(app)
        let field = element(app, "checkin.activity")
        reveal(field, in: app); field.tap(); field.typeText(text)
        if confirmSuggestion {
            let use = app.buttons["checkin.confirm-suggestion"]
            reveal(use, in: app); use.tap()
        }
        let save = app.buttons["checkin.save"]
        reveal(save, in: app); save.tap()
        XCTAssertTrue(app.staticTexts["Saved. You can change it anytime."].waitForExistence(timeout: 5))
        showToday(app)
    }

    private func openDashboardCategories(in app: XCUIApplication) {
        app.buttons["dashboard.filter"].tap()
        let manage = app.buttons["dashboard.manage-categories"]
        XCTAssertTrue(manage.waitForExistence(timeout: 5)); manage.tap()
    }

    private func dashboardGroup(_ id: String, in app: XCUIApplication) -> XCUIElement {
        let target = app.buttons["dashboard.group.\(id)"]
        if target.exists, target.isHittable { return target }
        let header = element(app, "dashboard.breakdown-title")
        for _ in 0..<5 {
            if header.exists, header.isHittable { break }
            app.swipeDown()
        }
        reveal(target, in: app)
        return target
    }

    private func openCategoryLogs(in app: XCUIApplication) {
        let logs = app.buttons["category-detail.logs"]
        XCTAssertTrue(logs.waitForExistence(timeout: 5)); reveal(logs, in: app); logs.tap()
        XCTAssertTrue(app.buttons["group.done"].waitForExistence(timeout: 5))
    }

    private func closeCategoryLogs(in app: XCUIApplication) {
        app.buttons["group.done"].tap()
        let close = app.buttons["category-detail.close"]
        if close.waitForExistence(timeout: 1), close.isHittable { close.tap() }
    }

    private func openCategoryTargets(in app: XCUIApplication) {
        XCTAssertTrue(element(app, "goals.time-left").waitForExistence(timeout: 10))
    }

    private func openGoalEditor(in app: XCUIApplication) {
        app.tabBars.buttons["Commitments"].tap()
        let edit = app.buttons["goals.edit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5)); edit.tap()
        XCTAssertTrue(app.segmentedControls["plan.unit"].waitForExistence(timeout: 5))
    }

    private func showToday(_ app: XCUIApplication) {
        dismissKeyboardIntroduction(in: app)
        if app.keyboards.firstMatch.exists {
            app.navigationBars.firstMatch.tap()
            XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        }
        app.tabBars.buttons["Today"].tap()
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "selected == true"), object: app.tabBars.buttons["Today"])
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 5), .completed)
        // Log is now a page within Today, so return using its normal back button.
        if app.navigationBars["Log"].exists, app.navigationBars.buttons["Today"].exists {
            app.navigationBars.buttons["Today"].tap()
        }
    }

    private func openLogPage(_ app: XCUIApplication) {
        if app.navigationBars["Log"].exists { return }
        showToday(app)
        let log = app.buttons["today.log"]
        XCTAssertTrue(log.waitForExistence(timeout: 5)); log.tap()
        XCTAssertTrue(app.navigationBars["Log"].waitForExistence(timeout: 10))
    }

    private func openLogs(_ app: XCUIApplication) {
        if app.navigationBars["Edit goals"].exists { app.buttons["Close"].tap() }
        openLogPage(app)
        let logs = element(app, "today.logs"); reveal(logs, in: app); logs.tap()
    }

    func testHomeShowsDashboardAndKeepsLoggingSeparateFromTimers() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-grouping-ledger"]; app.launch()
        let header = element(app, "dashboard.breakdown-title")
        let field = element(app, "checkin.activity")
        XCTAssertTrue(header.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Show pie chart"].exists)
        XCTAssertTrue(app.tabBars.buttons["Commitments"].exists)
        XCTAssertFalse(element(app, "allocation.periods").exists)
        XCTAssertTrue(element(app, "report.range").exists)
        XCTAssertFalse(field.exists)
        XCTAssertFalse(element(app, "today.logs").exists)
        XCTAssertEqual(app.tabBars.count, 1)
        XCTAssertTrue(app.tabBars.buttons["Inbox"].exists)
        XCTAssertFalse(app.segmentedControls["day.mode"].exists)
        XCTAssertFalse(app.staticTexts["Unestimated"].exists)
        let pages = element(app, "report.pages")
        XCTAssertGreaterThan(pages.frame.height, 100)
        XCTAssertEqual(pages.frame.width, app.frame.width, accuracy: 2)
        let calendar = app.buttons["dashboard.calendar"]
        XCTAssertTrue(calendar.isHittable)
        XCTAssertLessThan(calendar.frame.maxY, header.frame.minY)
        XCTAssertFalse(app.buttons["dashboard.undo"].exists)
        let urgent = element(app, "today.urgent-title")
        XCTAssertGreaterThan(urgent.frame.minY, pages.frame.maxY)
        app.buttons["Show pie chart"].tap()
        XCTAssertTrue(element(app, "report.pie.chart").waitForExistence(timeout: 5))
        let chart = element(app, "report.pie.chart")
        XCTAssertGreaterThan(chart.frame.width, 160); XCTAssertGreaterThan(chart.frame.height, 160)
        XCTAssertTrue(pages.frame.contains(chart.frame))
        XCTAssertGreaterThan(urgent.frame.minY, pages.frame.maxY)
        XCTAssertTrue(app.buttons["today.log"].isHittable)
        app.buttons["Show breakdown"].tap()
        recordScreen("Dashboard", in: app)
        openLogPage(app)
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertFalse(header.exists)
        recordScreen("Log", in: app)
        XCUIDevice.shared.press(.home); app.activate()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertFalse(header.exists)
    }

    func testUnconfirmedSuggestionStaysUncategorizedUntilAcceptedInReview() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-empty-ledger"]; app.launch()
        log("Working on app", in: app)
        let review = app.buttons["dashboard.review.uncategorized"]; reveal(review, in: app); XCTAssertTrue(review.exists); review.tap()
        XCTAssertEqual(element(app, "category-context.activity").label, "Working on app")
        let work = app.buttons["category-select.work"]; reveal(work, in: app); work.tap()
        app.buttons["log-review.save-next"].tap()
        XCTAssertTrue(dashboardGroup("work", in: app).waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["dashboard.review.uncategorized"].exists)
    }

    func testNewLogCanExplicitlyConfirmTheDisplayedSuggestion() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-empty-ledger"]; app.launch()
        log("Preparing classes", in: app, confirmSuggestion: true)
        XCTAssertTrue(dashboardGroup("work", in: app).waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["dashboard.review.uncategorized"].exists)
    }

    func testDashboardCategorizesAnUnknownActivityAndSupportsUndo() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-grouping-ledger"]; app.launch()
        let review = dashboardGroup("uncategorized", in: app); reveal(review, in: app); review.tap()
        openCategoryLogs(in: app)
        XCTAssertTrue(app.staticTexts["Quokka activity fixture"].waitForExistence(timeout: 5))
        app.buttons["Choose group"].tap(); tapCategory("social", in: app); app.buttons["group-selection.done"].tap()
        let undo = app.buttons["group.undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5)); undo.tap()
        XCTAssertTrue(app.staticTexts["Quokka activity fixture"].waitForExistence(timeout: 5))
        app.buttons["Choose group"].tap(); tapCategory("social", in: app); app.buttons["group-selection.done"].tap()
        closeCategoryLogs(in: app)
        XCTAssertTrue(dashboardGroup("social", in: app).waitForExistence(timeout: 5))
    }

    func testGroupPickerKeepsMultipleSelectionsWhileCreatingAndCanCancel() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-grouping-ledger"]; app.launch()
        let review = dashboardGroup("uncategorized", in: app); reveal(review, in: app); review.tap()
        openCategoryLogs(in: app)
        app.buttons["Choose group"].tap()
        let context = element(app, "category-context.activity")
        XCTAssertTrue(context.waitForExistence(timeout: 5)); XCTAssertTrue(context.label.contains("Quokka activity fixture"))
        XCTAssertTrue(element(app, "category-context.timestamp").exists)
        let work = app.buttons["category-select.work"], personal = app.buttons["category-select.personal"]
        work.tap(); personal.tap()
        XCTAssertTrue(context.isHittable)
        XCTAssertEqual(work.value as? String, "Selected")
        XCTAssertEqual(personal.value as? String, "Selected")
        let create = app.buttons["category-select.create"]; reveal(create, in: app)
        XCTAssertTrue(context.isHittable); create.tap()
        app.alerts.textFields["Group name"].typeText("Creative Practice")
        app.alerts.buttons["Create"].tap()
        XCTAssertTrue(app.navigationBars["Choose groups"].waitForExistence(timeout: 5))
        XCTAssertTrue(context.isHittable)
        let created = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "category-select.", "Creative Practice")).firstMatch
        reveal(created, in: app); XCTAssertEqual(created.value as? String, "Selected")
        reveal(work, in: app); XCTAssertEqual(work.value as? String, "Selected")
        reveal(personal, in: app); XCTAssertEqual(personal.value as? String, "Selected")
        recordScreen("MultiGroupPickerWithNewGroup", in: app)
        app.buttons["group-selection.done"].tap()
        closeCategoryLogs(in: app)
        let row = dashboardGroup("work", in: app); reveal(row, in: app); row.tap()
        openCategoryLogs(in: app)
        let choose = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "group.choose.")).firstMatch
        reveal(choose, in: app); choose.tap()
        reveal(work, in: app); XCTAssertEqual(work.value as? String, "Selected")
        reveal(personal, in: app); XCTAssertEqual(personal.value as? String, "Selected")
        personal.tap(); app.navigationBars["Choose groups"].buttons["Cancel"].tap()
        reveal(choose, in: app); choose.tap()
        XCTAssertEqual(personal.value as? String, "Selected") // Cancel never changes the log.
        app.buttons["group-selection.done"].tap()
        app.terminate(); app.launchArguments = []; app.launch()
        let group = dashboardGroup("personal", in: app); reveal(group, in: app)
        XCTAssertTrue(group.exists)
    }

    func testDashboardCreatesAndRenamesANewGroup() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-grouping-ledger"]; app.launch()
        let review = dashboardGroup("uncategorized", in: app); reveal(review, in: app); review.tap()
        openCategoryLogs(in: app)
        app.buttons["Choose group"].tap(); app.buttons["Create new group…"].tap()
        let field = app.alerts.textFields["Group name"]
        XCTAssertTrue(field.waitForExistence(timeout: 5)); field.typeText("Creative Practice")
        app.alerts.buttons["Create"].tap()
        app.buttons["group-selection.done"].tap()
        closeCategoryLogs(in: app); openDashboardCategories(in: app)
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "groups.open.", "Creative Practice")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        let groupID = String(row.identifier.dropFirst("groups.open.".count))
        let edit = app.buttons["categories.edit.\(groupID)"]; reveal(edit, in: app); edit.tap()
        recordScreen("CategoryEditorAfterTap", in: app)
        let rename = app.textFields["categories.name"]
        XCTAssertTrue(rename.waitForExistence(timeout: 5)); rename.tap()
        rename.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 30))
        rename.typeText("Creative Projects")
        app.buttons["categories.save"].tap()
        XCTAssertTrue(app.buttons["groups.open.\(groupID)"].staticTexts["Creative Projects"].waitForExistence(timeout: 5))
        app.buttons["groups.done"].tap()
        XCTAssertTrue(dashboardGroup(groupID, in: app).waitForExistence(timeout: 5))
    }

    func testCalendarOpensOnASeparateScreen() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-grouping-ledger"]; app.launch()
        let calendar = app.buttons["dashboard.calendar"]; reveal(calendar, in: app); calendar.tap()
        XCTAssertTrue(app.scrollViews["timeline.grid"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Noon"].exists)
    }

    func testEarlyAndLateLogsAppearAfterRemovingLegacySleepWindows() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-legacy-sleep-windows"]; app.launch()
        XCTAssertTrue(dashboardGroup("work", in: app).waitForExistence(timeout: 10))
        let period = element(app, "report.range"); period.tap(); app.buttons["Past 7 days"].tap()
        let social = dashboardGroup("social", in: app)
        XCTAssertTrue(social.waitForExistence(timeout: 5)); social.tap()
        openCategoryLogs(in: app)
        XCTAssertTrue(app.staticTexts["After former bedtime"].waitForExistence(timeout: 5))
        closeCategoryLogs(in: app)
        recordScreen("AllClockTimesInDashboard", in: app)
        let calendar = app.buttons["dashboard.calendar"]; reveal(calendar, in: app); calendar.tap()
        XCTAssertTrue(element(app, "timeline.grid").waitForExistence(timeout: 5))
        XCTAssertTrue(element(app, "timeline.sample.early").exists)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@", "timeline.block", "Before former wake time")).firstMatch.exists)
        recordScreen("EarlyLogOnFullDayCalendar", in: app)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.tabBars.buttons["Settings"].tap()
        XCTAssertFalse(app.buttons["Waking schedule"].exists)
    }

    func testExistingConfirmedLogSurvivesUpgradeAndCanBeEdited() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-legacy-ledger"]; app.launch()
        XCTAssertTrue(dashboardGroup("work", in: app).waitForExistence(timeout: 10))
        openLogs(app)
        let sample = app.staticTexts["Legacy sample UI fixture"]; reveal(sample, in: app); sample.tap()
        let field = app.textFields.matching(NSPredicate(format: "identifier BEGINSWITH %@", "logs.entry.")).firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        field.typeText(" updated")
        XCTAssertEqual(field.value as? String, "Legacy sample UI fixture updated")
        finishInlineEditing(in: app)
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Legacy sample UI fixture updated"].waitForExistence(timeout: 5))
        app.terminate(); app.launchArguments = []; app.launch(); openLogs(app)
        XCTAssertTrue(app.staticTexts["Legacy sample UI fixture updated"].waitForExistence(timeout: 5))
    }

    func testNotificationOpenedLogCanBeSavedAndSurvivesRelaunch() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-empty-ledger", "--ui-notification-checkin"]; app.launch()
        let field = element(app, "quicklog.activity")
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Where your time went"].isHittable)
        XCTAssertFalse(app.buttons["checkin.save"].isHittable)
        recordScreen("NotificationCapture", in: app)
        field.tap(); field.typeText("Notification sample UI test")
        app.buttons["quicklog.save"].tap()
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.buttons["Close"])
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 5), .completed)
        app.terminate(); app.launchArguments = []; app.launch()
        openLogs(app)
        XCTAssertTrue(app.staticTexts["Notification sample UI test"].waitForExistence(timeout: 5))
    }

    func testInboxIsADirectTabAndCapturesPersist() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-empty-ledger"]; app.launch()
        openInbox(app)
        let field = element(app, "inbox.text")
        XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap(); field.typeText("Follow up with a client UI test")
        let save = app.buttons["inbox.save"]; reveal(save, in: app); save.tap()
        XCUIDevice.shared.press(.home); app.activate()
        XCTAssertTrue(app.navigationBars["Inbox"].waitForExistence(timeout: 5))
        openInbox(app)
        XCTAssertTrue(app.staticTexts["Follow up with a client UI test"].waitForExistence(timeout: 5))
    }

    func testQuickNotificationReplySavesWithoutEditorConfirmationAndSurvivesRelaunch() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-empty-ledger", "--ui-quick-reply"]; app.launch()
        openLogs(app)
        XCTAssertTrue(app.staticTexts["Direct notification reply UI fixture"].waitForExistence(timeout: 5))
        showToday(app)
        let pending = app.buttons["dashboard.review.uncategorized"]; reveal(pending, in: app); XCTAssertTrue(pending.exists)
        app.terminate(); app.launchArguments = []; app.launch()
        openLogs(app)
        XCTAssertTrue(app.staticTexts["Direct notification reply UI fixture"].waitForExistence(timeout: 5))
    }

    func testSiriNoteHandlerSavesTitleOnlyWithoutOpeningAnEditorAndPersists() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-empty-ledger", "--ui-siri-capture"]; app.launch()
        openInbox(app)
        XCTAssertTrue(app.staticTexts["One sentence Siri UI fixture"].waitForExistence(timeout: 5))
        app.terminate(); app.launchArguments = []; app.launch()
        openInbox(app)
        XCTAssertTrue(app.staticTexts["One sentence Siri UI fixture"].waitForExistence(timeout: 5))
    }

    func testSiriRoutesIdeasAndActivitiesSeparatelyAndPersistsBoth() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-empty-ledger", "--ui-siri-routes"]; app.launch()
        openInbox(app)
        XCTAssertTrue(app.staticTexts["Bicycle idea UI fixture"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Bicycle activity UI fixture"].exists)
        openLogs(app)
        XCTAssertTrue(app.staticTexts["Bicycle activity UI fixture"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Bicycle idea UI fixture"].exists)
        app.terminate(); app.launchArguments = []; app.launch()
        openLogs(app)
        XCTAssertTrue(app.staticTexts["Bicycle activity UI fixture"].waitForExistence(timeout: 5))
        openInbox(app)
        XCTAssertTrue(app.staticTexts["Bicycle idea UI fixture"].waitForExistence(timeout: 5))
        recordScreen("DashInbox", in: app)
    }

    func testRemindersImportUsesSelectedListAndKeepsDeletedIdeasDeletedAfterRelaunch() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-empty-ledger", "--ui-reminders-fixture"]; app.launch()
        app.tabBars.buttons["Settings"].tap(); app.buttons["settings.reminders"].tap()
        allowReminders(in: app)
        let create = app.buttons["reminders.create"]
        XCTAssertTrue(create.waitForExistence(timeout: 10)); create.tap()
        let importNow = app.buttons["reminders.import"]
        reveal(importNow, in: app)
        XCTAssertTrue(importNow.waitForExistence(timeout: 20))
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: importNow)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 25), .completed)
        assertPendingReminders(0, in: app)
        recordScreen("RemindersSetup", in: app)
        openInbox(app)
        XCTAssertTrue(app.staticTexts["Reminders bicycle idea UI fixture"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Completed source UI fixture"].exists)
        XCTAssertFalse(app.staticTexts["Other list must stay private UI fixture"].exists)
        recordScreen("RemindersInbox", in: app)
        let idea = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "inbox.edit.")).firstMatch
        idea.tap()
        let remove = app.buttons["task-planning.delete"]; reveal(remove, in: app); remove.tap()
        app.tabBars.buttons["Settings"].tap()
        reveal(importNow, in: app); importNow.tap()
        app.terminate(); app.launchArguments = []; app.launch()
        app.tabBars.buttons["Settings"].tap(); app.buttons["settings.reminders"].tap()
        reveal(importNow, in: app)
        XCTAssertTrue(importNow.waitForExistence(timeout: 20))
        let reloaded = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: importNow)
        XCTAssertEqual(XCTWaiter.wait(for: [reloaded], timeout: 25), .completed)
        openInbox(app)
        XCTAssertFalse(app.staticTexts["Reminders bicycle idea UI fixture"].exists)
        app.tabBars.buttons["Settings"].tap()
        let disconnect = app.buttons["reminders.disconnect"]; reveal(disconnect, in: app); disconnect.tap()
        XCTAssertFalse(importNow.exists)
    }

    func testCopyAllIdeasPastesFullInboxIncludingCompletedButNotDeleted() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-inbox-export-fixture"]; app.launch()
        openInbox(app)
        app.buttons["inbox.copy-all"].tap()
        XCTAssertTrue(element(app, "inbox.copy-confirmation").waitForExistence(timeout: 5))
        let field = element(app, "inbox.text")
        field.tap(); field.press(forDuration: 1.2)
        let menuPaste = app.menuItems["Paste"]
        if menuPaste.waitForExistence(timeout: 2) { menuPaste.tap() }
        else {
            let paste = app.buttons["Paste"].firstMatch
            XCTAssertTrue(paste.waitForExistence(timeout: 3)); paste.tap()
        }
        let value = field.value as? String ?? ""
        XCTAssertTrue(value.contains("Dash inbox — 2 ideas"))
        XCTAssertTrue(value.contains("Idea to analyze\n   Keep every line"))
        XCTAssertTrue(value.contains("Completed idea"))
        XCTAssertTrue(value.contains("Status: Completed"))
        XCTAssertTrue(value.contains("List: New Ideas"))
        XCTAssertTrue(value.contains("List: Completed"))
        XCTAssertTrue(value.contains("Rank: Not evaluated"))
        XCTAssertTrue(value.contains("Captured:"))
        XCTAssertFalse(value.contains("Deleted idea"))
    }

    func testStartupHelperFailureDoesNotBlockLocalLoggingOrLoseItAfterRelaunch() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-empty-ledger", "--ui-companion-unavailable"]
        app.launch()
        XCTAssertTrue(element(app, "dashboard.breakdown-title").waitForExistence(timeout: 10))
        XCTAssertEqual(app.alerts.count, 0)
        log("Saved while helper unavailable", in: app)
        app.tabBars.buttons["Settings"].tap()
        let status = element(app, "sync.companion.status"); reveal(status, in: app)
        XCTAssertEqual(status.label, "Saved on this device · sync waiting")
        XCTAssertTrue(app.staticTexts["NSCocoaErrorDomain (4099)"].exists)
        app.terminate(); app.launchArguments = ["--ui-companion-unavailable"]; app.launch()
        openLogs(app)
        XCTAssertTrue(app.staticTexts["Saved while helper unavailable"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.alerts.count, 0)
    }

    func testHistoryRangesAndSwipeablePieAndTrend() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-grouping-ledger"]; app.launch()
        openHistory(app)
        let period = element(app, "report.range")
        XCTAssertTrue(period.waitForExistence(timeout: 10)); period.tap(); app.buttons["Past 7 days"].tap()
        XCTAssertTrue(app.navigationBars["Your time"].waitForExistence(timeout: 5))
        let pages = element(app, "report.pages"); pages.swipeLeft()
        XCTAssertTrue(app.staticTexts["Pie chart"].waitForExistence(timeout: 5))
        recordScreen("Pie", in: app)
        pages.swipeLeft()
        XCTAssertTrue(app.staticTexts["Daily trend"].waitForExistence(timeout: 5))
        recordScreen("Trend", in: app)
        period.tap(); app.buttons["All time"].tap()
        XCTAssertTrue(app.staticTexts["Daily trend"].exists)
        period.tap(); app.buttons["Custom"].tap()
        XCTAssertTrue(element(app, "report.from").waitForExistence(timeout: 5))
        XCTAssertTrue(element(app, "report.through").exists)
    }

    func testDashboardRefreshesImmediatelyAfterMultipleLabelsAndKeepsPieInSync() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-grouping-ledger"]; app.launch()
        XCTAssertFalse(app.buttons["dashboard.history"].exists)
        let review = app.buttons["dashboard.review.uncategorized"]; reveal(review, in: app); review.tap()
        tapCategory("work", in: app); tapCategory("social", in: app)
        app.buttons["log-review.save-next"].tap()
        XCTAssertFalse(app.buttons["dashboard.undo"].exists)
        let social = dashboardGroup("social", in: app)
        XCTAssertTrue(social.waitForExistence(timeout: 2))
        XCTAssertFalse(app.buttons["dashboard.group.uncategorized"].exists)
        app.buttons["Show pie chart"].tap()
        XCTAssertTrue(app.buttons["report.pie.group.social"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.buttons["report.pie.group.uncategorized"].exists)
        recordScreen("DashboardAfterCategorization", in: app)
    }

    func testDashboardGroupingReviewStartsWithVisiblePeriod() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-review-range-fixture"]; app.launch()
        let review = app.buttons["dashboard.review.uncategorized"]; reveal(review, in: app); review.tap()
        XCTAssertTrue(element(app, "category-context.activity").waitForExistence(timeout: 5))
        XCTAssertEqual(element(app, "category-context.activity").label, "Quokka activity fixture")
        XCTAssertFalse(app.staticTexts["Older ungrouped observation"].exists)
        XCTAssertEqual(element(app, "log-review.position").label, "1 of 1")
        recordScreen("ReviewVisibleDatesOrAllDays", in: app)
    }

    func testLongEntryStaysVisibleAboveTheCategoryChecklist() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-long-grouping-ledger"]; app.launch()
        let review = app.buttons["dashboard.review.uncategorized"]; reveal(review, in: app); review.tap()
        let context = element(app, "category-context.activity")
        XCTAssertTrue(context.waitForExistence(timeout: 5)); XCTAssertTrue(context.label.hasPrefix("Preparing classes"))
        app.buttons["category-context.expand"].tap()
        XCTAssertEqual(app.buttons["category-context.expand"].label, "Show less")
        let create = app.buttons["category-select.create"]; reveal(create, in: app)
        XCTAssertTrue(context.isHittable)
        XCTAssertTrue(element(app, "category-context.timestamp").isHittable)
        recordScreen("PinnedLongEntryCategoryPicker", in: app)
        app.buttons["category-context.expand"].tap()
        let work = app.buttons["category-select.work"]; reveal(work, in: app); work.tap()
        let personal = app.buttons["category-select.personal"]; reveal(personal, in: app); personal.tap()
        XCTAssertTrue(context.isHittable)
        XCTAssertEqual(work.value as? String, "Selected"); XCTAssertEqual(personal.value as? String, "Selected")
        app.buttons["log-review.save-next"].tap()
    }

    func testTrendComparisonFiltersHighlightsAndRemembersCategoriesAfterRelaunch() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-many-trends-fixture"]; app.launch()
        element(app, "report.range").tap(); app.buttons["Past 7 days"].tap()
        app.buttons["Show daily trend"].tap()
        let count = element(app, "report.trend.selected-count")
        XCTAssertTrue(count.waitForExistence(timeout: 5)); XCTAssertEqual(count.label, "3 categories")
        app.buttons["report.trend.choose"].tap()
        for item in app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "trend-select.")).allElementsBoundByIndex {
            if item.value as? String == "Selected" { item.tap() }
        }
        app.buttons["trend-select.work"].tap(); app.buttons["trend-select.social"].tap()
        app.buttons["trend-select.done"].tap()
        XCTAssertEqual(count.label, "2 categories")
        app.buttons["report.trend.highlight.work"].tap()
        XCTAssertTrue(app.buttons["report.trend.highlight.work"].isSelected)
        recordScreen("SelectedTrendCategoriesHighlighted", in: app)
        app.terminate(); app.launchArguments = []; app.launch()
        element(app, "report.range").tap(); app.buttons["Past 7 days"].tap()
        app.buttons["Show daily trend"].tap()
        XCTAssertEqual(count.label, "2 categories")
        XCTAssertTrue(app.buttons["report.trend.highlight.work"].exists)
        XCTAssertTrue(app.buttons["report.trend.highlight.social"].exists)
    }

    func testTrendDayInspectionAndSeparateCategoryChartsUseBothUnits() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-many-trends-fixture"]; app.launch()
        element(app, "report.range").tap(); app.buttons["Past 7 days"].tap()
        app.buttons["Show daily trend"].tap()
        let chart = element(app, "report.trend.chart"); reveal(chart, in: app)
        let first = chart.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5))
        let last = chart.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.5))
        first.press(forDuration: 1, thenDragTo: last)
        let values = element(app, "report.trend.day-values")
        XCTAssertTrue(values.waitForExistence(timeout: 5))
        recordScreen("TrendDayInspection", in: app)
        let layout = app.segmentedControls["report.trend.layout"]; reveal(layout, in: app)
        layout.buttons["By category"].tap()
        let panel = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "report.trend.category.")).firstMatch
        XCTAssertTrue(panel.waitForExistence(timeout: 5)); recordScreen("SeparateCategoryTrendsHours", in: app)
        let units = app.segmentedControls["report.trend.units"]; reveal(units, in: app)
        units.buttons["Percentages"].tap()
        XCTAssertTrue(app.staticTexts["Share of each day’s tracked time"].exists)
        recordScreen("SeparateCategoryTrendsPercentages", in: app)
        app.terminate(); app.launchArguments = []; app.launch()
        app.buttons["Show daily trend"].tap()
        XCTAssertTrue(layout.buttons["By category"].isSelected)
        XCTAssertTrue(units.buttons["Percentages"].isSelected)
    }

    func testCategoryLineTrendsAndUnitsAreOnMainDashboard() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-trend-fixture"]; app.launch()
        let period = element(app, "report.range"); XCTAssertTrue(period.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["dashboard.history"].exists)
        period.tap(); app.buttons["Past 7 days"].tap()
        app.buttons["Show daily trend"].tap()
        let chart = element(app, "report.trend.chart"); XCTAssertTrue(chart.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Hours in each category by day"].exists)
        recordScreen("CategoryTrendHours", in: app)
        app.segmentedControls["report.trend.units"].buttons["Percentages"].tap()
        XCTAssertTrue(app.staticTexts["Share of each day’s tracked time"].exists)
        recordScreen("CategoryTrendPercentages", in: app)
        period.tap(); app.buttons["All time"].tap()
        XCTAssertTrue(chart.exists)
        app.segmentedControls["report.trend.units"].buttons["Hours"].tap()
        XCTAssertTrue(app.staticTexts["Hours in each category by day"].exists)
    }

    func testLegacySnoozeForTodayUsesEightAMInsteadOfItsOldClockTime() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-snooze-today"]; app.launch()
        openInbox(app)
        let idea = app.staticTexts["Due at beginning of today"]
        if Calendar.current.component(.hour, from: Date()) < 8 {
            let snoozed = element(app, "inbox.snoozed"); reveal(snoozed, in: app); snoozed.tap()
            reveal(idea, in: app); XCTAssertTrue(idea.exists)
            XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Returns ")).firstMatch.exists)
        } else {
            reveal(idea, in: app); XCTAssertTrue(idea.exists)
            XCTAssertTrue(element(app, "inbox.waiting-title").label.contains("1"))
        }
        recordScreen("SnoozeReturnsAtEightAM", in: app)
    }

    func testPieSlicesAndLegendSelectLabelsInsideChart() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-grouping-ledger"]; app.launch()
        openHistory(app)
        app.buttons["Show pie chart"].tap()
        let chart = element(app, "report.pie.chart")
        XCTAssertTrue(chart.waitForExistence(timeout: 5))
        // The fixture is 75% Uncategorized, starting clockwise from twelve.
        chart.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        let selection = element(app, "report.pie.selection")
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "Uncategorized"), object: selection)
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 5), .completed)
        recordScreen("SelectedPieSlice", in: app)
        let work = app.buttons["report.pie.group.work"]; reveal(work, in: app); work.tap()
        XCTAssertTrue(selection.label.contains("Work"))
        XCTAssertTrue(selection.label.contains("%"))
        chart.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertTrue(selection.label.contains("Uncategorized"))
    }

    func testHeatmapShowsAllCategoriesMissingDaysUnitsAndDetails() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-many-trends-fixture"]; app.launch()
        element(app, "report.range").tap(); app.buttons["Past 7 days"].tap()
        app.buttons["Show heatmap"].tap()
        recordScreen("FullScreenHeatmapInitial", in: app)
        let units = app.segmentedControls["report.heatmap.units"]
        XCTAssertTrue(units.waitForExistence(timeout: 5))
        units.buttons["Percentages"].tap()
        let work = app.buttons["report.heatmap.category.work"]
        XCTAssertTrue(work.exists)
        let names = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "report.heatmap.category."))
        XCTAssertGreaterThan(names.count, 3) // Includes categories hidden in the trend comparison.
        let cells = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "report.heatmap.cell.work."))
        XCTAssertEqual(cells.count, 7)
        let missing = cells.matching(NSPredicate(format: "value == %@", "No data")).firstMatch
        XCTAssertTrue(missing.exists); missing.tap()
        let selection = element(app, "report.heatmap.selection")
        XCTAssertTrue(selection.waitForExistence(timeout: 5)); XCTAssertTrue(selection.label.contains("No data"))
        let populated = cells.matching(NSPredicate(format: "value CONTAINS %@", "percent")).firstMatch
        revealHeatmapRow(populated, in: app)
        populated.tap()
        XCTAssertTrue(selection.label.contains("Work")); XCTAssertTrue(selection.label.contains("%"))
        recordScreen("FullScreenHeatmapPercentages", in: app)
        units.buttons["Hours"].tap()
        XCTAssertTrue(selection.label.contains("%")) // Details always retain both measures.
        XCTAssertTrue(app.buttons["dashboard.calendar"].isHittable)
        recordScreen("FullScreenHeatmapHours", in: app)
        revealHeatmapRow(work, in: app); work.tap()
        openCategoryLogs(in: app)
        XCTAssertTrue(app.buttons["group.done"].waitForExistence(timeout: 5)); closeCategoryLogs(in: app)
        app.buttons["dashboard.calendar"].tap()
        XCTAssertTrue(element(app, "timeline.grid").waitForExistence(timeout: 5))
    }

    private func revealHeatmapRow(_ target: XCUIElement, in app: XCUIApplication) {
        let rows = app.scrollViews["report.heatmap.rows"]
        XCTAssertTrue(rows.waitForExistence(timeout: 5))
        reveal(rows, in: app)
        for _ in 0..<8 {
            if target.exists, target.isHittable, rows.frame.contains(target.frame) { return }
            if target.exists, target.frame.maxY < rows.frame.minY { rows.swipeDown() }
            else { rows.swipeUp() }
        }
        XCTAssertTrue(target.isHittable); XCTAssertTrue(rows.frame.contains(target.frame))
    }

    func testHeatmapExpandsChildrenAndDirectTimeWithoutShiftingGridColumns() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-allocation-fixture", "--ui-category-outline", "--ui-heatmap-detail"]; app.launch()
        element(app, "report.range").tap(); app.buttons["Past 7 days"].tap()
        app.buttons["Show heatmap"].tap()
        let heading = element(app, "report.heatmap.heading.work")
        XCTAssertTrue(heading.waitForExistence(timeout: 5))
        XCTAssertTrue(element(app, "report.heatmap.heading.music").exists)
        let direct = app.buttons["report.heatmap.category.direct:work"]
        let teaching = app.buttons["report.heatmap.category.teaching"], guitar = app.buttons["report.heatmap.category.guitar"]
        XCTAssertTrue(direct.exists); XCTAssertTrue(teaching.exists); XCTAssertTrue(guitar.exists)
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "report.heatmap.cell.work.")).firstMatch.exists)
        let directCells = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "report.heatmap.cell.direct:work."))
        let teachingCells = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "report.heatmap.cell.teaching."))
        let guitarCells = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "report.heatmap.cell.guitar."))
        XCTAssertEqual(directCells.count, 7); XCTAssertEqual(teachingCells.count, 7); XCTAssertEqual(guitarCells.count, 7)
        for column in 0..<7 {
            let a = directCells.element(boundBy: column).frame, b = teachingCells.element(boundBy: column).frame, c = guitarCells.element(boundBy: column).frame
            XCTAssertEqual(a.minX, b.minX, accuracy: 1); XCTAssertEqual(a.minX, c.minX, accuracy: 1)
            XCTAssertEqual(a.width, c.width, accuracy: 1); XCTAssertEqual(a.height, c.height, accuracy: 1)
        }
        let units = app.segmentedControls["report.heatmap.units"]
        units.buttons["Percentages"].tap()
        directCells.matching(NSPredicate(format: "value CONTAINS %@", "percent")).firstMatch.tap()
        XCTAssertTrue(element(app, "report.heatmap.selection").label.contains("Work (direct)"))
        recordScreen("ExpandedHeatmapAlignedColumns", in: app)
        units.buttons["Hours"].tap()
        recordScreen("ExpandedHeatmapHours", in: app)
        revealHeatmapRow(direct, in: app); direct.tap()
        openCategoryLogs(in: app)
        XCTAssertTrue(app.buttons["group.done"].waitForExistence(timeout: 5))
        XCTAssertTrue(element(app, "group.log.today-parent-direct").exists)
        XCTAssertFalse(element(app, "group.log.today-teaching").exists)
        XCTAssertFalse(element(app, "group.log.today-guitar").exists)
        closeCategoryLogs(in: app)
        revealHeatmapRow(guitar, in: app); guitar.tap()
        openCategoryLogs(in: app)
        XCTAssertTrue(element(app, "group.log.today-guitar").waitForExistence(timeout: 5))
        XCTAssertFalse(element(app, "group.log.today-parent-direct").exists)
    }

    func testGroupCountsAndDeletionPreserveAllTimeLogsAfterRelaunch() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-group-history"]; app.launch()
        openDashboardCategories(in: app)
        let group = app.buttons["groups.open.work"]; reveal(group, in: app)
        XCTAssertTrue(group.staticTexts["0 ideas"].exists); recordScreen("CategoryCounts", in: app)
        app.buttons["categories.edit.work"].tap()
        app.buttons["View all logs (2)"].tap()
        XCTAssertTrue(app.staticTexts["Older work observation"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Recent work observation"].exists)
        closeCategoryLogs(in: app)
        app.buttons["group.delete"].tap(); app.sheets.buttons["Cancel"].firstMatch.tap()
        XCTAssertTrue(app.textFields["categories.name"].exists)
        app.buttons["group.delete"].tap()
        app.buttons.matching(NSPredicate(format: "label == %@ AND identifier != %@", "Delete category", "group.delete")).firstMatch.tap()
        XCTAssertFalse(app.buttons["groups.open.work"].exists)
        let uncategorized = app.buttons["groups.open.uncategorized"]; reveal(uncategorized, in: app); uncategorized.tap()
        openCategoryLogs(in: app)
        XCTAssertTrue(app.staticTexts["Older work observation"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Recent work observation"].exists)
        app.terminate(); app.launchArguments = []; app.launch(); openDashboardCategories(in: app)
        XCTAssertFalse(app.buttons["groups.open.work"].exists)
        reveal(uncategorized, in: app); uncategorized.tap()
        openCategoryLogs(in: app)
        XCTAssertTrue(app.staticTexts["Older work observation"].waitForExistence(timeout: 5))
    }

    func testInboxCategorizationIsIndependentAndSavesAcrossRestart() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-category-workspace"]; app.launch()
        openInbox(app)
        app.buttons["inbox.categorize"].tap()
        app.buttons["inbox.categorize-uncategorized"].tap()
        XCTAssertEqual(element(app, "category-context.activity").label, "Newest uncategorized idea")
        XCTAssertEqual(element(app, "idea-review.position").label, "1 of 1")
        XCTAssertFalse(app.navigationBars["Rank ideas"].exists)
        let search = app.textFields["category-search.field"]; search.tap(); search.typeText("teaching")
        tapCategory("teaching", in: app)
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        XCTAssertTrue(app.buttons["idea-review.save-next"].isHittable)
        XCTAssertLessThanOrEqual(app.buttons["idea-review.save-next"].frame.maxY, app.keyboards.firstMatch.frame.minY)
        XCTAssertFalse(app.buttons.matching(identifier: "keyboard.done").allElementsBoundByIndex.contains { $0.isHittable })
        recordScreen("InboxIndependentCategorization", in: app)
        app.buttons["idea-review.save-next"].tap()
        XCTAssertTrue(app.buttons["inbox.categorize"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Review complete"].exists)
        app.buttons["inbox.categorize"].tap(); app.buttons["inbox.categorize-all"].tap()
        XCTAssertEqual(element(app, "idea-review.position").label, "1 of 6")
        XCTAssertEqual(app.buttons["category-select.teaching"].value as? String, "Selected")
        app.buttons["idea-review.save-next"].tap()
        XCTAssertEqual(element(app, "category-context.activity").label, "New music idea")
        XCTAssertEqual(element(app, "idea-review.position").label, "2 of 6")
        app.buttons["idea-review.close"].tap()
        app.terminate(); app.launchArguments = []; app.launch(); openInbox(app)
        app.buttons["inbox.categories"].tap(); app.buttons["inbox.categories.teaching"].tap()
        XCTAssertEqual(element(app, "category-detail.count").label, "2 inbox items")
        recordScreen("CategorizedIdeasAfterRestart", in: app)
        reveal(element(app, "inbox.details.second"), in: app)
        XCTAssertTrue(element(app, "inbox.details.second").exists)
        reveal(element(app, "inbox.details.uncategorized"), in: app)
        XCTAssertTrue(element(app, "inbox.details.uncategorized").exists)
    }

    func testSharedCategoryPageShowsRankedAndUnrankedItemsBeforeLogs() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-category-workspace"]; app.launch()
        openInbox(app); app.buttons["inbox.categories"].tap()
        let music = app.buttons["inbox.categories.music"]
        XCTAssertTrue(music.waitForExistence(timeout: 5))
        XCTAssertTrue(music.label.contains("4")); XCTAssertTrue(music.label.contains("#1"))
        recordScreen("InboxCategoryCounts", in: app); music.tap()
        XCTAssertEqual(element(app, "category-detail.count").label, "4 inbox items")
        let ranked = element(app, "inbox.details.first"), unranked = element(app, "inbox.details.unseen")
        recordScreen("CategoryInboxFirst", in: app)
        reveal(ranked, in: app); reveal(unranked, in: app)
        XCTAssertTrue(ranked.exists); XCTAssertTrue(unranked.exists)
        XCTAssertLessThan(ranked.frame.minY, unranked.frame.minY)
        XCTAssertFalse(app.staticTexts["Playing music"].exists)
        XCTAssertFalse(app.buttons["group.done"].exists)
        recordScreen("CategoryInboxFirst", in: app)
        openCategoryLogs(in: app)
        XCTAssertTrue(element(app, "group.log.music-log").waitForExistence(timeout: 5))
        XCTAssertFalse(element(app, "group.log.teaching-log").exists)
        closeCategoryLogs(in: app)
        app.navigationBars["Inbox categories"].buttons["Close"].tap()
        showToday(app)
        dashboardGroup("music", in: app).tap()
        XCTAssertEqual(element(app, "category-detail.count").label, "4 inbox items")
        let other = element(app, "category-detail.other-lists"); reveal(other, in: app); other.tap()
        XCTAssertEqual(other.value as? String, "Expanded")
        recordScreen("CategoryOtherListsExpanded", in: app)
        reveal(element(app, "inbox.details.reference"), in: app)
        XCTAssertTrue(element(app, "inbox.details.reference").exists)
        reveal(element(app, "inbox.details.completed"), in: app)
        XCTAssertTrue(element(app, "inbox.details.completed").exists)
        swipeIdeaAction("unseen", action: "delete", in: app)
        reveal(element(app, "category-detail.count"), in: app)
        XCTAssertEqual(element(app, "category-detail.count").label, "3 inbox items")
        let undo = app.buttons["inbox.undo-delete"]; reveal(undo, in: app); undo.tap()
        reveal(element(app, "category-detail.count"), in: app)
        XCTAssertEqual(element(app, "category-detail.count").label, "4 inbox items")
    }

    func testCommitmentFavoritesIncludeChildGoalsAndPersist() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-category-workspace"]; app.launch()
        app.tabBars.buttons["Commitments"].tap(); openCategoryTargets(in: app)
        XCTAssertTrue(app.buttons["Choose favorites"].waitForExistence(timeout: 5))
        XCTAssertFalse(element(app, "goals.progress.music").exists)
        openGoalEditor(in: app)
        selectPlanCategory("music", in: app); app.buttons["plan.favorite"].tap()
        XCTAssertFalse(app.buttons["plan.selection-done"].exists)
        app.navigationBars["Edit goals"].buttons["Close"].tap(); openCategoryTargets(in: app)
        XCTAssertTrue(element(app, "goals.progress.music").waitForExistence(timeout: 5))
        XCTAssertFalse(element(app, "goals.progress.teaching").exists)
        element(app, "goals.progress.music").tap()
        XCTAssertEqual(element(app, "category-detail.count").label, "4 inbox items")
        recordScreen("CategoryFromCommitment", in: app)
        reveal(element(app, "inbox.details.first"), in: app)
        XCTAssertTrue(element(app, "inbox.details.first").exists)
        app.buttons["category-detail.close"].tap()
        openGoalEditor(in: app)
        selectPlanCategory("work", in: app); app.buttons["plan.favorite"].tap()
        app.navigationBars["Edit goals"].buttons["Close"].tap(); openCategoryTargets(in: app)
        XCTAssertTrue(element(app, "goals.progress.teaching").waitForExistence(timeout: 5))
        XCTAssertTrue(element(app, "goals.progress.admin").exists)
        XCTAssertFalse(element(app, "goals.progress.work").exists)
        recordScreen("FavoriteCommitments", in: app)
        app.terminate(); app.launchArguments = []; app.launch(); app.tabBars.buttons["Commitments"].tap(); openCategoryTargets(in: app)
        XCTAssertTrue(element(app, "goals.progress.music").waitForExistence(timeout: 5))
        XCTAssertTrue(element(app, "goals.progress.teaching").exists)
        openGoalEditor(in: app)
        let arrow = app.buttons["plan.children.work"]; reveal(arrow, in: app)
        if arrow.label.hasPrefix("Expand ") { arrow.tap() }
        selectPlanCategory("teaching", in: app)
        XCTAssertEqual(app.buttons["plan.favorite"].label, "Unfavorite")
        app.buttons["plan.favorite"].tap()
        app.navigationBars["Edit goals"].buttons["Close"].tap(); openCategoryTargets(in: app)
        XCTAssertFalse(element(app, "goals.progress.teaching").exists)
        XCTAssertTrue(element(app, "goals.progress.music").exists)
    }

    func testInboxRankingResumesAfterRelaunchAndNewIdeasWaitToBeRanked() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-inbox-fixture"]; app.launch()
        openInbox(app); openRanking(app)
        XCTAssertTrue(app.buttons["ranking.second"].waitForExistence(timeout: 5))
        recordScreen("Ranking", in: app); app.buttons["ranking.second"].tap()
        app.buttons["Done"].tap(); app.terminate(); app.launchArguments = []; app.launch()
        openInbox(app); openRanking(app)
        XCTAssertTrue(app.buttons["ranking.first"].waitForExistence(timeout: 5)); app.buttons["ranking.first"].tap()
        // First-look ordering can reuse a prior answer and finish immediately.
        for _ in 0..<10 {
            if !app.buttons["ranking.second"].exists { break }
            app.buttons["ranking.second"].tap()
        }
        XCTAssertTrue(app.staticTexts["Review complete"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        let field = element(app, "inbox.text"); field.tap(); field.typeText("New idea")
        app.buttons["inbox.save"].tap()
        XCTAssertTrue(app.buttons["inbox.new-shortcut"].label.contains("1"))
        XCTAssertFalse(app.navigationBars["Rank ideas"].exists)
    }

    func testInboxDeletionHasUndoAndPersistsAfterRelaunch() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-inbox-fixture"]; app.launch()
        openInbox(app)
        recordScreen("Inbox", in: app)
        swipeIdeaAction("a", action: "delete", in: app)
        let removed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.buttons["inbox.edit.a"])
        XCTAssertEqual(XCTWaiter.wait(for: [removed], timeout: 10), .completed)
        app.buttons["inbox.undo-delete"].tap()
        XCTAssertTrue(app.staticTexts["First idea"].waitForExistence(timeout: 5))
        let complete = app.buttons["inbox.complete.b"]; reveal(complete, in: app); complete.tap()
        XCTAssertFalse(app.navigationBars["Edit idea"].exists)
        swipeIdeaAction("a", action: "delete", in: app)
        app.terminate(); app.launchArguments = []; app.launch(); openInbox(app)
        XCTAssertFalse(app.staticTexts["First idea"].exists)
        XCTAssertTrue(app.staticTexts["Third idea"].exists)
    }

    func testBackupPreviewAndRestoreRecoverOlderLogsIntoHistory() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-corrupt-ledger", "--ui-local-backup", "--ui-backup-fixture"]; app.launch()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 10)); app.alerts.buttons["OK"].tap()
        app.tabBars.buttons["Settings"].tap()
        let restore = app.buttons["backup.restore"]; reveal(restore, in: app); restore.tap()
        let file = app.buttons.matching(identifier: "backup.file").firstMatch
        XCTAssertTrue(file.waitForExistence(timeout: 10)); file.tap()
        XCTAssertTrue(app.staticTexts["2 activity logs · 0 ideas"].waitForExistence(timeout: 5))
        recordScreen("RestorePreview", in: app)
        app.buttons["backup.confirm-restore"].tap()
        XCTAssertTrue(app.staticTexts["Restored. Your newer edits and existing logs were kept."].waitForExistence(timeout: 5))
        showToday(app)
        openHistory(app)
        element(app, "report.range").tap(); app.buttons["Past 7 days"].tap()
        openLogPage(app)
        element(app, "logs.range").tap(); app.buttons["Past 7 days"].tap()
        openLogs(app)
        XCTAssertTrue(app.staticTexts["Restored older activity"].waitForExistence(timeout: 5))
    }

    func testLogSwipeDeletionUndoAndEditorDeletionPersist() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-group-history"]; app.launch()
        openLogs(app)
        let row = element(app, "logs.entry.recent"); reveal(row, in: app); row.swipeLeft()
        if app.buttons["Delete"].exists { app.buttons["Delete"].tap() }
        let undo = app.buttons["logs.undo-delete"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5)); undo.tap()
        XCTAssertTrue(element(app, "logs.entry.recent").waitForExistence(timeout: 5))
        let trash = app.buttons["logs.delete.recent"]; reveal(trash, in: app)
        recordScreen("VisibleLogDelete", in: app); trash.tap()
        XCTAssertFalse(element(app, "logs.entry.recent").exists)
        XCTAssertFalse(app.navigationBars["Edit log"].exists)
        XCTAssertTrue(undo.waitForExistence(timeout: 5)); undo.tap()
        XCTAssertTrue(element(app, "logs.entry.recent").waitForExistence(timeout: 5))
        app.buttons["Edit time and categories"].firstMatch.tap()
        let remove = app.buttons["edit.delete"]; reveal(remove, in: app); remove.tap()
        XCTAssertTrue(app.buttons["logs.undo-delete"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Recent work observation"].exists)
        recordScreen("LogDeletedUndo", in: app)
        app.terminate(); app.launchArguments = []; app.launch(); openLogs(app)
        XCTAssertFalse(app.staticTexts["Recent work observation"].exists)
        showToday(app); openDashboardCategories(in: app)
        let work = app.buttons["categories.edit.work"]; reveal(work, in: app); work.tap()
        app.buttons["View all logs (1)"].tap()
        XCTAssertTrue(app.staticTexts["Older work observation"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Recent work observation"].exists)
    }

    func testCategoryLogDeleteButtonUpdatesDashboardAndCanUndo() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-group-history"]; app.launch()
        dashboardGroup("work", in: app).tap()
        openCategoryLogs(in: app)
        let trash = app.buttons["group.delete-log.recent"]
        XCTAssertTrue(trash.waitForExistence(timeout: 5))
        recordScreen("CategoryLogDelete", in: app); trash.tap()
        XCTAssertFalse(app.staticTexts["Recent work observation"].exists)
        XCTAssertFalse(app.navigationBars["Edit sample"].exists)
        // The app-wide Undo bar can remain in the accessibility tree behind
        // this sheet. Target the Undo control the user can actually tap.
        let undos = app.buttons.matching(identifier: "logs.undo-delete")
        XCTAssertTrue(undos.firstMatch.waitForExistence(timeout: 5))
        guard let undo = undos.allElementsBoundByIndex.first(where: { $0.isHittable }) else {
            XCTFail("No visible Undo button after deleting a category log"); return
        }
        undo.tap()
        XCTAssertTrue(app.staticTexts["Recent work observation"].waitForExistence(timeout: 5))
        trash.tap(); closeCategoryLogs(in: app)
        XCTAssertFalse(app.buttons["dashboard.group.work"].exists)
        app.terminate(); app.launchArguments = []; app.launch()
        XCTAssertFalse(app.buttons["dashboard.group.work"].exists)
        openLogs(app)
        XCTAssertFalse(element(app, "logs.entry.recent").exists)
    }

    func testRankingCanDeleteEitherIdeaUndoAndContinue() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-inbox-fixture"]; app.launch()
        openInbox(app); openRanking(app)
        let first = app.buttons["ranking.first"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        let deletedText = first.label
        app.buttons["ranking.first.delete"].tap()
        XCTAssertTrue(app.buttons["ranking.undo-delete"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["ranking.first"].label == deletedText)
        XCTAssertFalse(app.buttons["ranking.second"].label == deletedText)
        app.buttons["ranking.undo-delete"].tap()
        XCTAssertTrue(app.buttons["ranking.first"].waitForExistence(timeout: 5))
        app.buttons["ranking.second.delete"].tap()
        for _ in 0..<10 {
            if app.buttons["ranking.first"].exists { app.buttons["ranking.first"].tap() }
            else if app.buttons["ranking.more"].exists { app.buttons["ranking.more"].tap() }
            else { break }
        }
        XCTAssertTrue(app.staticTexts["Review complete"].waitForExistence(timeout: 5))
        recordScreen("RankingCleanup", in: app)
    }

    func testInboxKeyboardDismissesOutsideAndPreservesDraftAcrossTabs() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-empty-ledger"]; app.launch()
        openInbox(app, capture: true)
        let field = element(app, "inbox.text"); field.tap(); field.typeText("Keep my draft")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        app.navigationBars["Inbox"].tap()
        let hidden = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.keyboards.firstMatch)
        XCTAssertEqual(XCTWaiter.wait(for: [hidden], timeout: 5), .completed)
        XCTAssertEqual(field.value as? String, "Keep my draft")
        showToday(app); openInbox(app)
        XCTAssertEqual(field.value as? String, "Keep my draft")
        field.tap()
        let done = app.buttons["keyboard.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5)); done.tap()
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        app.buttons["inbox.save"].tap()
        XCTAssertTrue(app.staticTexts["Keep my draft"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.keyboards.firstMatch.exists)
    }

    func testAllDayNotificationSettingPersistsAndHidesWindowPickers() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-empty-ledger"]; app.launch()
        app.tabBars.buttons["Settings"].tap()
        let toggle = app.switches["settings.notifications-all-day"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        app.buttons["settings.save-notifications"].tap()
        XCTAssertFalse(app.buttons["Start"].exists)
        recordScreen("AllDayReminders", in: app)
        app.terminate(); app.launchArguments = []; app.launch(); app.tabBars.buttons["Settings"].tap()
        XCTAssertEqual(app.switches["settings.notifications-all-day"].value as? String, "1")
    }

    func testNotificationTimingModesRememberSeparateIntervalsAfterRelaunch() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-empty-ledger"]; app.launch()
        func assertPicker(_ picker: XCUIElement, contains value: String) {
            reveal(picker, in: app)
            let restored = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@ OR value == %@", value, value), object: picker)
            XCTAssertEqual(XCTWaiter.wait(for: [restored], timeout: 5), .completed)
        }
        func saveNotifications(_ button: XCUIElement) {
            reveal(button, in: app)
            button.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
            let allow = springboard.alerts.buttons["Allow"]
            if allow.waitForExistence(timeout: 3) { allow.tap() }
            let finished = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: button)
            XCTAssertEqual(XCTWaiter.wait(for: [finished], timeout: 15), .completed)
        }

        app.tabBars.buttons["Settings"].tap()
        let timing = element(app, "settings.notification-timing")
        let interval = element(app, "settings.notification-interval")
        XCTAssertTrue(timing.waitForExistence(timeout: 5))
        assertPicker(timing, contains: "Regular")
        interval.tap(); app.buttons["30 minutes"].tap()
        timing.tap(); app.buttons["Randomized"].tap()
        XCTAssertTrue(interval.label.contains("15 minutes") || interval.value as? String == "15 minutes")
        interval.tap(); app.buttons["20 minutes"].tap()
        let explanation = element(app, "settings.notification-explanation")
        XCTAssertTrue(explanation.label.contains("13.3–26.7"))
        let save = app.buttons["settings.save-notifications"]; saveNotifications(save)
        recordScreen("RandomizedNotificationSettings", in: app)
        app.terminate(); app.launchArguments = []; app.launch(); app.tabBars.buttons["Settings"].tap()
        assertPicker(timing, contains: "Randomized")
        assertPicker(interval, contains: "20 minutes")
        timing.tap(); app.buttons["Regular"].tap()
        assertPicker(interval, contains: "30 minutes")
        saveNotifications(save)
        app.terminate(); app.launch(); app.tabBars.buttons["Settings"].tap()
        assertPicker(interval, contains: "30 minutes")
        assertPicker(timing, contains: "Regular")
    }

    func testRandomNotificationsQueueAndSwitchBackToRepeating() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-empty-ledger"]; app.launch()
        app.tabBars.buttons["Settings"].tap()
        element(app, "settings.notification-timing").tap(); app.buttons["Randomized"].tap()
        let allDay = app.switches["settings.notifications-all-day"]
        reveal(allDay, in: app)
        allDay.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        let enabled = app.switches["settings.notifications-enabled"]
        reveal(enabled, in: app)
        enabled.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        let save = app.buttons["settings.save-notifications"]; reveal(save, in: app); save.tap()
        let allow = app.alerts.buttons["Allow"]
        if allow.waitForExistence(timeout: 3) { allow.tap() }
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        if springboard.alerts.buttons["Allow"].waitForExistence(timeout: 2) { springboard.alerts.buttons["Allow"].tap() }
        let status = element(app, "settings.notification-schedule-status")
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        let scheduled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "Scheduled through"), object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [scheduled], timeout: 10), .completed)
        let queued = status.label
        reveal(save, in: app); save.tap()
        XCTAssertEqual(status.label, queued) // refilling does not postpone scheduled prompts
        recordScreen("RandomNotificationQueue", in: app)
        let timing = element(app, "settings.notification-timing"); reveal(timing, in: app); timing.tap()
        app.buttons["Regular"].tap(); reveal(save, in: app); save.tap()
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        let repeating = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "Repeats automatically"), object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [repeating], timeout: 10), .completed)
        let off = app.switches["settings.notifications-enabled"]; reveal(off, in: app)
        off.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        reveal(save, in: app); save.tap()
        let disabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "Check-ins are off"), object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [disabled], timeout: 10), .completed)
    }

    func testWatchDeliveryChoicePersistsAndExplainsWatchSetup() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-empty-ledger"]; app.launch()
        app.tabBars.buttons["Settings"].tap()
        let delivery = element(app, "settings.notification-delivery")
        XCTAssertTrue(delivery.waitForExistence(timeout: 5))
        delivery.tap(); app.buttons["Apple Watch"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "allow Watch notifications once")).firstMatch.exists)
        let enabled = app.switches["settings.notifications-enabled"]; reveal(enabled, in: app)
        enabled.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        let save = app.buttons["settings.save-notifications"]; reveal(save, in: app); save.tap()
        let status = element(app, "settings.notification-schedule-status")
        let watch = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "assigned to Apple Watch"), object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [watch], timeout: 10), .completed)
        recordScreen("WatchDeliverySettings", in: app)
        app.terminate(); app.launchArguments = []; app.launch(); app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(delivery.label.contains("Apple Watch") || delivery.value as? String == "Apple Watch")
        XCTAssertEqual(app.switches["settings.notifications-enabled"].value as? String, "1")
    }

    func testTargetsAreAccessibleAndPersist() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-allocation-fixture"]; app.launch()
        openGoalEditor(in: app)
        XCTAssertFalse(app.buttons["categories.save-targets"].exists)
        setPlanNumber("categories.target.teaching", to: "90", in: app)
        setPlanNumber("categories.target.teaching", to: "80", in: app)
        setPlanNumber("categories.target.teaching", to: "85", in: app)
        app.terminate(); app.launchArguments = []; app.launch(); openGoalEditor(in: app)
        XCTAssertEqual(element(app, "categories.calculated-goal.work").value as? String, "85")
        XCTAssertEqual(app.textFields["categories.target.music"].value as? String, "15")
    }

    func testMultiCategorySelectionResolvesParentConflictExplicitly() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-allocation-fixture"]; app.launch()
        openLogPage(app)
        let field = element(app, "checkin.activity"); field.tap(); field.typeText("Two activities")
        let selector = element(app, "checkin.category"); reveal(selector, in: app); selector.tap()
        XCTAssertEqual(element(app, "category-context.activity").label, "Two activities")
        tapCategory("work", in: app)
        app.buttons["category-select.teaching"].tap()
        XCTAssertTrue(app.alerts["Replace conflicting categories?"].waitForExistence(timeout: 5))
        app.alerts.buttons["Replace"].tap(); app.buttons["category-select.music"].tap()
        recordScreen("MultipleCategories", in: app)
        app.buttons["Done"].tap()
        let save = app.buttons["checkin.save"]; reveal(save, in: app); save.tap()
        XCTAssertTrue(app.staticTexts["Saved. You can change it anytime."].waitForExistence(timeout: 5))
    }

    func testCompactCommitmentsKeepsGoalsAndActivityLogs() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-commitments-fixture"]; app.launch()
        openGoalEditor(in: app)
        XCTAssertTrue(app.segmentedControls["plan.unit"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Weekly minimum"].exists)
        XCTAssertFalse(app.buttons["plan.remaining.work"].exists)
        setPlanNumber("categories.target.teaching", to: "85", in: app)
        showPlanStart(in: app)
        XCTAssertEqual(element(app, "categories.calculated-goal.work").value as? String, "85")
        let children = element(app, "plan.children.work"); reveal(children, in: app)
        XCTAssertTrue(app.staticTexts["Teaching"].waitForExistence(timeout: 5))
        recordScreen("CompactCategoryOutline", in: app)
        openLogs(app)
        XCTAssertTrue(app.staticTexts["Preparing classes"].waitForExistence(timeout: 5))
    }

    func testBulkGroupingIntoExistingParentPreviewsGoalsAndCanUndo() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-life-area-fixture"]; app.launch()
        openGoalEditor(in: app)
        selectPlanCategory("admin", in: app); selectPlanCategory("music", in: app)
        XCTAssertTrue(app.textFields["categories.target.music"].exists)
        XCTAssertFalse(app.navigationBars["Categories"].exists)
        app.buttons["plan.group-selected"].tap()
        element(app, "categories.destination").tap()
        app.buttons.matching(NSPredicate(format: "label == %@ AND identifier != %@", "Work", "plan.children.work")).firstMatch.tap()
        let preview = app.staticTexts["30% → 55%"]
        reveal(preview, in: app); XCTAssertTrue(preview.exists)
        recordScreen("BulkGroupingPreview", in: app)
        let move = app.buttons["categories.apply-move"]; XCTAssertTrue(move.isEnabled); move.tap()
        let undo = app.buttons["categories.undo-move"]; reveal(undo, in: app)
        XCTAssertTrue(undo.waitForExistence(timeout: 5)); undo.tap()
        XCTAssertFalse(app.buttons["plan.group-selected"].exists)
        let music = app.textFields["categories.target.music"]; reveal(music, in: app)
        XCTAssertEqual(music.value as? String, "15")
        let workTarget = element(app, "categories.calculated-goal.work"); reveal(workTarget, in: app)
        XCTAssertEqual(workTarget.value as? String, "30")
    }

    func testBulkGroupingCreatesParentAndPersistsWithoutLosingLogs() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-life-area-fixture"]; app.launch()
        openGoalEditor(in: app)
        selectPlanCategory("admin", in: app); selectPlanCategory("music", in: app)
        recordScreen("DirectCategorySelection", in: app)
        app.buttons["plan.group-selected"].tap()
        let name = app.textFields["categories.new-parent-name"]; XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap(); name.typeText("Personal projects"); app.buttons["keyboard.done"].tap()
        XCTAssertTrue(app.buttons["categories.apply-move"].isEnabled)
        app.buttons["categories.apply-move"].tap()
        waitForGroupingToFinish(in: app)
        let goal = app.staticTexts["Personal projects calculated goal percent"]; reveal(goal, in: app)
        XCTAssertEqual(goal.value as? String, "25")
        recordScreen("GroupedLifeAreas", in: app)
        app.terminate(); app.launchArguments = []; app.launch(); openGoalEditor(in: app)
        reveal(goal, in: app); XCTAssertEqual(goal.value as? String, "25")
        openLogs(app)
        XCTAssertTrue(app.staticTexts["Guitar practice"].waitForExistence(timeout: 5))
    }

    func testCommitmentsShowsAllRootCategoriesAndExpandsWithoutChangingSelection() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-life-area-fixture"]; app.launch()
        openGoalEditor(in: app)
        XCTAssertTrue(app.segmentedControls["plan.unit"].waitForExistence(timeout: 5))
        app.buttons["plan.hide-blank-goals"].tap()
        XCTAssertFalse(app.buttons["plan.add-area"].exists)
        XCTAssertFalse(element(app, "plan.loose-categories").exists)
        XCTAssertFalse(app.buttons["plan.group-selected"].exists)
        let german = app.textFields["categories.target.german"]; reveal(german, in: app)
        XCTAssertTrue(german.exists)
        selectPlanCategory("german", in: app)
        let group = app.buttons["plan.group-selected"]
        XCTAssertEqual(group.label, "Move")
        let work = app.buttons["plan.children.work"]; reveal(work, in: app); work.tap()
        let teaching = app.staticTexts["Teaching"]; reveal(teaching, in: app)
        XCTAssertTrue(teaching.exists)
        XCTAssertFalse(app.buttons["plan.select.teaching"].exists)
        XCTAssertEqual(group.label, "Move")
        XCTAssertTrue(element(app, "categories.calculated-goal.work").exists)
        recordScreen("CategoryTreeExpanded", in: app)
        app.buttons["plan.selection-done"].tap()
        XCTAssertFalse(group.exists)
    }

    func testCompactOutlineExpandsChildrenWithoutOpeningLogs() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-allocation-fixture", "--ui-category-outline"]; app.launch()
        openGoalEditor(in: app)
        app.buttons["plan.hide-blank-goals"].tap()
        XCTAssertTrue(app.segmentedControls["plan.unit"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["categories.save-targets"].exists)
        let work = app.buttons["plan.children.work"]; reveal(work, in: app); work.tap()
        let teaching = element(app, "plan.name.teaching"); reveal(teaching, in: app)
        XCTAssertTrue(teaching.exists)
        let music = app.buttons["plan.children.music"]; reveal(music, in: app); music.tap()
        let guitar = element(app, "plan.name.guitar"); reveal(guitar, in: app)
        XCTAssertTrue(guitar.exists)
        XCTAssertTrue(element(app, "plan.direct.music").exists)
        XCTAssertFalse(app.buttons["group.done"].exists)
        XCTAssertFalse(app.buttons["View logs"].exists)
        XCTAssertFalse(app.buttons["plan.remaining.work"].exists)
        XCTAssertTrue(element(app, "categories.calculated-goal.music").exists)
        // Names now open category details; close the sheet before exercising
        // the outline beneath it. Disclosure controls only expand/collapse.
        guitar.tap()
        XCTAssertTrue(app.buttons["category-detail.close"].waitForExistence(timeout: 5))
        app.buttons["category-detail.close"].tap()
        XCTAssertTrue(app.navigationBars["Edit goals"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["group.done"].exists)
        recordScreen("CompactNestedOutline", in: app)
        reveal(music, in: app); music.tap()
        XCTAssertFalse(guitar.exists)
        XCTAssertTrue(teaching.exists)
        reveal(work, in: app); work.tap()
        XCTAssertFalse(teaching.exists)
        XCTAssertFalse(music.exists)
        XCTAssertFalse(app.buttons["group.done"].exists)
    }

    func testGroupingProtectsUnsavedGoalsAndCancelKeepsSelection() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-life-area-fixture"]; app.launch()
        openGoalEditor(in: app)
        setPlanNumber("categories.target.teaching", to: "35", in: app)
        selectPlanCategory("admin", in: app); selectPlanCategory("music", in: app)
        app.buttons["plan.group-selected"].tap()
        XCTAssertTrue(element(app, "categories.destination").waitForExistence(timeout: 5))
        app.navigationBars["Group categories"].buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["plan.group-selected"].exists)
        let work = element(app, "categories.calculated-goal.work"); reveal(work, in: app)
        XCTAssertEqual(work.value as? String, "35")
    }

    func testGroupingCanSaveACompleteDraftBeforePreviewingMove() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-life-area-fixture"]; app.launch()
        openGoalEditor(in: app)
        setPlanNumber("categories.target.teaching", to: "35", in: app)
        setPlanNumber("categories.target.music", to: "10", in: app)
        selectPlanCategory("admin", in: app); selectPlanCategory("music", in: app)
        app.buttons["plan.group-selected"].tap()
        let name = app.textFields["categories.new-parent-name"]; XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap(); name.typeText("Personal projects"); app.buttons["keyboard.done"].firstMatch.tap()
        app.buttons["categories.apply-move"].tap()
        XCTAssertTrue(app.buttons["categories.undo-move"].waitForExistence(timeout: 5))
        let root = element(app, "plan.name.work"); reveal(root, in: app)
        XCTAssertEqual(element(app, "categories.calculated-goal.work").value as? String, "35")
        XCTAssertFalse(app.staticTexts["Save plan"].exists)
    }

    private func showPlanStart(in app: XCUIApplication) {
        let total = element(app, "plan.name.work")
        for _ in 0..<12 {
            if total.exists && total.isHittable { break }
            app.swipeDown()
        }
        reveal(total, in: app)
    }

    func testFocusedLogReviewSavesMoodAndCategoriesWithoutChangingCapture() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-review-range-fixture"]; app.launch()
        let review = app.buttons["dashboard.review.uncategorized"]; reveal(review, in: app); review.tap()
        XCTAssertEqual(element(app, "category-context.activity").label, "Quokka activity fixture")
        XCTAssertEqual(element(app, "log-review.position").label, "1 of 1")
        app.buttons["mood.4"].tap()
        tapCategory("work", in: app); tapCategory("social", in: app)
        recordScreen("FocusedMoodReview", in: app)
        app.buttons["log-review.save-next"].tap()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Review complete"].exists)
        XCTAssertFalse(app.buttons["log-review.close"].exists)
        let group = dashboardGroup("work", in: app); reveal(group, in: app); group.tap()
        openCategoryLogs(in: app)
        XCTAssertTrue(app.staticTexts["Mood: 4/5"].waitForExistence(timeout: 5))
        let change = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "group.choose.")).firstMatch
        reveal(change, in: app); change.tap()
        let selectedMood = app.buttons["mood.4"]; reveal(selectedMood, in: app)
        XCTAssertEqual(selectedMood.value as? String, "Selected")
        app.buttons["mood.clear"].tap(); app.buttons["group-selection.done"].tap()
        XCTAssertFalse(app.staticTexts["Mood: 4/5"].exists)
        closeCategoryLogs(in: app)
        app.terminate(); app.launchArguments = []; app.launch()
        XCTAssertFalse(app.buttons["dashboard.review.uncategorized"].exists)
        openLogPage(app)
        XCTAssertTrue(element(app, "checkin.activity").exists)
        XCTAssertFalse(app.buttons["mood.1"].exists)
    }

    func testDashboardExpandsNestedCategoriesAndKeepsLogNavigation() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-allocation-fixture", "--ui-category-outline"]; app.launch()
        toggleDashboardZeroFilter(in: app)
        let work = app.buttons["dashboard.children.work"]
        XCTAssertTrue(work.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["dashboard.group.teaching"].exists)
        work.tap()
        XCTAssertTrue(app.buttons["dashboard.group.teaching"].waitForExistence(timeout: 5))
        let music = app.buttons["dashboard.children.music"]; reveal(music, in: app); music.tap()
        XCTAssertTrue(app.buttons["dashboard.group.guitar"].waitForExistence(timeout: 5))
        recordScreen("DashboardCategoryTree", in: app)
        let teaching = app.buttons["dashboard.group.teaching"]; reveal(teaching, in: app); teaching.tap()
        openCategoryLogs(in: app)
        XCTAssertTrue(app.staticTexts["Preparing classes"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Guitar practice"].exists)
        closeCategoryLogs(in: app)
        reveal(work, in: app); work.tap()
        XCTAssertFalse(app.buttons["dashboard.group.teaching"].exists)
        XCTAssertFalse(app.buttons["dashboard.group.guitar"].exists)
        app.buttons["Show pie chart"].tap()
        XCTAssertTrue(app.buttons["report.pie.group.work"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["report.pie.group.teaching"].exists)
    }

    func testCategoryPickerShowsAllHierarchyLevelsWithoutExpansionAndKeepsEntryVisible() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-allocation-fixture", "--ui-category-outline"]; app.launch()
        openLogPage(app)
        let field = element(app, "checkin.activity"); field.tap(); field.typeText("Preparing teaching materials")
        let picker = element(app, "checkin.category"); reveal(picker, in: app); picker.tap()
        let context = element(app, "category-context.activity")
        XCTAssertTrue(context.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["category-select.teaching"].exists)
        XCTAssertTrue(app.buttons["category-select.music"].exists)
        let guitar = app.buttons["category-select.guitar"]; reveal(guitar, in: app)
        XCTAssertTrue(guitar.exists); guitar.tap()
        tapCategory("teaching", in: app)
        XCTAssertEqual(guitar.value as? String, "Selected")
        XCTAssertEqual(app.buttons["category-select.teaching"].value as? String, "Selected")
        XCTAssertTrue(context.isHittable)
        XCTAssertEqual(guitar.label, "Work › Music › Guitar")
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "category-select.children.")).count, 0)
        recordScreen("CategoryPickerFullTree", in: app)
        app.buttons["Done"].tap()
    }

    func testReviewStaysOpenBetweenLogsAndDismissesAfterTheLastSave() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-review-range-fixture"]; app.launch()
        element(app, "report.range").tap(); app.buttons["All time"].tap()
        let review = app.buttons["dashboard.review.uncategorized"]; reveal(review, in: app); review.tap()
        XCTAssertEqual(element(app, "log-review.position").label, "1 of 2")
        tapCategory("work", in: app); app.buttons["log-review.save-next"].tap()
        XCTAssertTrue(app.navigationBars["Review logs"].exists)
        XCTAssertEqual(element(app, "log-review.position").label, "2 of 2")
        XCTAssertEqual(element(app, "category-context.activity").label, "Older ungrouped observation")
        tapCategory("social", in: app); app.buttons["mood.5"].tap()
        app.buttons["log-review.save-next"].tap()
        XCTAssertTrue(app.navigationBars["Your time"].waitForExistence(timeout: 5))
        if app.buttons["log-review.close"].exists {
            recordScreen("ReviewAfterLastSave", in: app)
            print("REVIEW AFTER LAST SAVE: \(app.debugDescription)")
        }
        XCTAssertFalse(app.buttons["log-review.close"].exists)
        XCTAssertFalse(app.staticTexts["Review complete"].exists)
        XCTAssertFalse(app.buttons["dashboard.review.uncategorized"].exists)
    }

    func testReviewTextEditRetainsSearchSelectedCategoriesMoodAndPosition() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-review-range-fixture"]; app.launch()
        let review = app.buttons["dashboard.review.uncategorized"]; reveal(review, in: app); review.tap()
        app.buttons["mood.4"].tap(); tapCategory("work", in: app); tapCategory("social", in: app)
        let search = app.textFields["category-search.field"]; search.tap(); search.typeText("work")
        editInline("category-context.activity", adding: " corrected", in: app, finishEditing: false)
        XCTAssertTrue((app.textFields["category-context.activity"].value as? String ?? "").contains("corrected"))
        XCTAssertEqual(search.value as? String, "work")
        XCTAssertEqual(element(app, "log-review.position").label, "1 of 1")
        XCTAssertTrue(app.buttons["category-tag.work"].exists); XCTAssertTrue(app.buttons["category-tag.social"].exists)
        app.buttons["category-search.clear"].tap()
        let mood = app.buttons["mood.4"]; reveal(mood, in: app); XCTAssertEqual(mood.value as? String, "Selected")
        recordScreen("InlineLogReview", in: app)
        app.buttons["log-review.save-next"].tap()
        let group = dashboardGroup("work", in: app); reveal(group, in: app); group.tap()
        openCategoryLogs(in: app)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "corrected")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Mood: 4/5"].exists)
    }

    func testCategoryAssignmentCanEditTextOrCancelWithoutLosingDraftChoices() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-grouping-ledger"]; app.launch()
        let group = dashboardGroup("uncategorized", in: app); reveal(group, in: app); group.tap()
        openCategoryLogs(in: app)
        app.buttons["Choose group"].tap()
        app.buttons["mood.3"].tap(); tapCategory("work", in: app)
        editInline("category-context.activity", adding: " corrected", in: app)
        let context = element(app, "category-context.activity")
        let updated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            context.label.contains("corrected") || (context.value as? String ?? "").contains("corrected")
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [updated], timeout: 5), .completed)
        XCTAssertTrue(app.buttons["category-tag.work"].exists)
        app.buttons["group-selection.done"].tap(); closeCategoryLogs(in: app)
        let work = dashboardGroup("work", in: app)
        XCTAssertTrue(work.waitForExistence(timeout: 5)); work.tap(); openCategoryLogs(in: app)
        let edited = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "corrected")).firstMatch
        reveal(edited, in: app); XCTAssertTrue(edited.exists)
        XCTAssertTrue(app.staticTexts["Mood: 3/5"].exists)
    }

    func testCategorySearchKeepsHierarchyAndSelectionsAndCanCreateFromNoResults() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-allocation-fixture", "--ui-category-outline"]; app.launch()
        openLogPage(app)
        let field = element(app, "checkin.activity")
        XCTAssertTrue(field.waitForExistence(timeout: 10)); field.tap(); field.typeText("Activity to categorize")
        let picker = element(app, "checkin.category"); reveal(picker, in: app); picker.tap()
        let search = app.textFields["category-search.field"]
        search.tap(); search.typeText("guitar")
        XCTAssertTrue(app.buttons["category-select.work"].exists)
        XCTAssertTrue(app.buttons["category-select.music"].exists)
        XCTAssertFalse(app.buttons["category-select.teaching"].exists)
        let guitar = app.buttons["category-select.guitar"]; reveal(guitar, in: app); guitar.tap()
        XCTAssertTrue(element(app, "category-context.activity").isHittable)
        // Selecting a result clears the query and keeps input ready for the
        // next category, matching the shared selector's current behavior.
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        XCTAssertTrue(["", "Search categories"].contains(search.value as? String ?? "<missing>"))
        XCTAssertFalse(app.buttons["category-search.clear"].exists)
        reveal(guitar, in: app)
        XCTAssertEqual(guitar.value as? String, "Selected")
        tapCategory("teaching", in: app)
        search.tap(); search.typeText("Creative laboratory")
        XCTAssertTrue(element(app, "category-search.empty").waitForExistence(timeout: 5))
        let create = app.buttons["category-select.create"]; reveal(create, in: app); create.tap()
        XCTAssertEqual(app.alerts.textFields["Group name"].value as? String, "Creative laboratory")
        app.alerts.buttons["Create"].tap()
        reveal(guitar, in: app); XCTAssertEqual(guitar.value as? String, "Selected")
        let teaching = app.buttons["category-select.teaching"]; reveal(teaching, in: app)
        XCTAssertEqual(teaching.value as? String, "Selected")
        let created = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label == %@", "category-select.", "Creative laboratory")).firstMatch
        reveal(created, in: app); XCTAssertEqual(created.value as? String, "Selected")
        recordScreen("CategorySearchWithCreatedGroup", in: app)
        app.buttons["Done"].tap()
    }

    func testCategoryActionsCreateChildFirstThenMoveSelectedLogs() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-allocation-fixture"]; app.launch()
        openGoalEditor(in: app)
        XCTAssertFalse(app.buttons["plan.manage-categories"].exists)
        XCTAssertFalse(app.buttons["plan.select.work"].exists)
        selectPlanCategory("work", in: app)
        app.buttons["plan.create-child"].tap()
        let name = app.textFields["category-name.field"]; XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap(); name.typeText("Hygiene"); app.buttons["category-name.save"].tap()
        XCTAssertFalse(app.buttons["plan.selection-done"].exists)
        let arrow = app.buttons["plan.children.work"]; reveal(arrow, in: app)
        // Creating a child already reveals the branch. Do not collapse it.
        if arrow.label.hasPrefix("Expand ") { arrow.tap() }
        selectPlanCategory("teaching", in: app)
        recordScreen("CategorySelectionActions", in: app)
        app.buttons["plan.open-category"].tap()
        openCategoryLogs(in: app)
        XCTAssertTrue(app.staticTexts["Preparing classes"].waitForExistence(timeout: 5))
        app.buttons["group.select"].tap()
        element(app, "group.log.today-teaching").tap()
        app.buttons["group.move-logs"].tap()
        let destination = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "log-move.", "Hygiene")).firstMatch
        XCTAssertTrue(destination.waitForExistence(timeout: 5)); destination.tap()
        XCTAssertTrue(app.staticTexts["There are no logs in this group for this view."].waitForExistence(timeout: 5))
        closeCategoryLogs(in: app)
        XCTAssertFalse(app.buttons["plan.selection-done"].exists)
        let child = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label == %@", "plan.name.", "Hygiene")).firstMatch
        reveal(child, in: app); child.tap()
        openCategoryLogs(in: app)
        XCTAssertTrue(app.staticTexts["Preparing classes"].waitForExistence(timeout: 5))
        closeCategoryLogs(in: app)
        XCUIDevice.shared.press(.home); app.activate()
        XCTAssertTrue(app.navigationBars["Edit goals"].exists)
        recordScreen("CategoryOutlineAfterMove", in: app)
    }

    func testSelectingCategoriesAtAnyDepthOffersOnlyMoveForMultiple() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-allocation-fixture", "--ui-category-outline"]; app.launch()
        openGoalEditor(in: app)
        app.buttons["plan.hide-blank-goals"].tap()
        let arrow = app.buttons["plan.children.work"]; reveal(arrow, in: app); arrow.tap()
        selectPlanCategory("work", in: app); selectPlanCategory("teaching", in: app)
        XCTAssertTrue(app.buttons["plan.group-selected"].exists)
        XCTAssertFalse(app.buttons["plan.delete"].exists); XCTAssertFalse(app.buttons["plan.rename"].exists)
        XCTAssertFalse(app.buttons["plan.create-child"].exists); XCTAssertFalse(app.buttons["plan.open-category"].exists)
        app.buttons["plan.selection-done"].tap()
        XCTAssertFalse(app.buttons["plan.group-selected"].exists)
    }

    func testCategoryRenameAndDeleteKeepLogsAndPromoteChildren() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-allocation-fixture"]; app.launch()
        openGoalEditor(in: app); selectPlanCategory("work", in: app)
        app.buttons["plan.rename"].tap()
        let name = app.textFields["category-name.field"]; XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap(); name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 20)); name.typeText("Responsibilities")
        app.buttons["category-name.save"].tap()
        let renamed = element(app, "plan.name.work"); reveal(renamed, in: app)
        XCTAssertEqual(renamed.label, "Responsibilities")
        selectPlanCategory("work", in: app); app.buttons["plan.delete"].tap()
        app.sheets.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["plan.selection-done"].exists)
        app.buttons["plan.delete"].tap(); app.sheets.buttons["Delete category"].tap()
        let finished = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.buttons["plan.selection-done"])
        XCTAssertEqual(XCTWaiter.wait(for: [finished], timeout: 10), .completed)
        XCTAssertFalse(renamed.exists)
        let promoted = app.textFields["categories.target.teaching"]; reveal(promoted, in: app)
        XCTAssertTrue(promoted.exists)
        openLogs(app); XCTAssertTrue(app.staticTexts["Preparing classes"].waitForExistence(timeout: 5))
    }

    private func waitForGroupingToFinish(in app: XCUIApplication) {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.buttons["plan.group-selected"])
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 5), .completed)
    }

    private func selectPlanCategory(_ id: String, in app: XCUIApplication) {
        let loaded = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element(app, "plan.loading"))
        XCTAssertEqual(XCTWaiter.wait(for: [loaded], timeout: 15), .completed)
        if app.buttons["plan.select"].exists {
            let select = app.buttons["plan.select"]
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: select)
            XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed)
            select.tap()
        }
        XCTAssertTrue(app.buttons["plan.selection-done"].waitForExistence(timeout: 10))
        let row = element(app, "plan.name.\(id)"); reveal(row, in: app); row.tap()
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "Selected"), object: row)
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 10), .completed)
    }

    private func tapCategory(_ id: String, in app: XCUIApplication) {
        let button = app.buttons["category-select.\(id)"]; reveal(button, in: app); button.tap()
    }

    private func setPlanNumber(_ id: String, to value: String, in app: XCUIApplication) {
        if !app.textFields[id].exists && app.buttons["plan.hide-blank-goals"].value as? String == "On" && !app.buttons["plan.children.work"].exists {
            app.buttons["plan.hide-blank-goals"].tap()
        }
        if id == "categories.target.teaching" && !app.textFields[id].exists {
            let expand = app.buttons["plan.children.work"]; reveal(expand, in: app); expand.tap()
        }
        let field = app.textFields[id]; reveal(field, in: app)
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 12)); field.typeText(value)
        if value.isEmpty { XCTAssertTrue(["", "—"].contains(field.value as? String ?? "")) }
        else { XCTAssertEqual(field.value as? String, value) }
        if app.buttons["keyboard.done"].isHittable { app.buttons["keyboard.done"].tap() }
    }

    func testRankedIdeasStayFirstAndNewIdeasHaveTheirOwnSectionAndShortcut() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-ranked-inbox-fixture"]; app.launch()
        openInbox(app)
        XCTAssertTrue(app.staticTexts["Ranked priority 1"].waitForExistence(timeout: 5))
        XCTAssertTrue(element(app, "inbox.ranked-title").label.contains("20"))
        XCTAssertFalse(app.staticTexts["Ranked priority 21"].exists)
        XCTAssertFalse(app.staticTexts["New imported idea"].isHittable)
        recordScreen("InboxRankedFirst", in: app)
        app.buttons["inbox.new-shortcut"].tap()
        let imported = app.staticTexts["New imported idea"]
        XCTAssertTrue(imported.waitForExistence(timeout: 5)); XCTAssertTrue(imported.isHittable)
        XCTAssertTrue(element(app, "inbox.waiting-title").exists)
        recordScreen("InboxNewWaiting", in: app)
        reveal(app.buttons["inbox.review"], in: app)
        XCTAssertTrue(app.buttons["inbox.review"].isHittable)
        app.buttons["inbox.review"].tap()
        XCTAssertTrue(app.buttons["ranking.first"].waitForExistence(timeout: 5))
    }

    func testReminderTransferKeepsSourceAfterSaveFailureAndRetriesDeletionWithoutDuplicates() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-empty-ledger", "--ui-reminders-fixture", "--ui-reminders-save-failure"]; app.launch()
        app.tabBars.buttons["Settings"].tap(); app.buttons["settings.reminders"].tap()
        allowReminders(in: app)
        app.buttons["reminders.create"].tap()
        let importNow = app.buttons["reminders.import"]; reveal(importNow, in: app)
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: importNow)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 25), .completed)
        assertPendingReminders(1, in: app)
        openInbox(app)
        XCTAssertFalse(app.staticTexts["Reminders bicycle idea UI fixture"].exists)

        app.terminate(); app.launchArguments = ["--ui-reminders-delete-failure"]; app.launch()
        app.tabBars.buttons["Settings"].tap(); app.buttons["settings.reminders"].tap()
        reveal(importNow, in: app)
        let saved = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: importNow)
        XCTAssertEqual(XCTWaiter.wait(for: [saved], timeout: 25), .completed)
        assertPendingReminders(1, in: app)
        openInbox(app)
        XCTAssertTrue(app.staticTexts["Reminders bicycle idea UI fixture"].waitForExistence(timeout: 5))

        app.terminate(); app.launchArguments = []; app.launch()
        app.tabBars.buttons["Settings"].tap(); app.buttons["settings.reminders"].tap()
        reveal(importNow, in: app)
        let transferred = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: importNow)
        XCTAssertEqual(XCTWaiter.wait(for: [transferred], timeout: 25), .completed)
        assertPendingReminders(0, in: app)
        recordScreen("ReminderTransferConfirmed", in: app)
        openInbox(app)
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label == %@", "Reminders bicycle idea UI fixture")).count, 1)
        XCTAssertTrue(element(app, "inbox.waiting-title").exists)
        app.tabBars.buttons["Settings"].tap()
        let disconnect = app.buttons["reminders.disconnect"]; reveal(disconnect, in: app); disconnect.tap()
        openInbox(app)
        let text = app.staticTexts["Reminders bicycle idea UI fixture"]
        reveal(text, in: app); text.tap()
        let editor = app.textFields.matching(NSPredicate(format: "identifier BEGINSWITH %@", "inbox.details.")).firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 5)); editor.typeText(" Corrected details")
        app.buttons["keyboard.done"].firstMatch.tap()
        let corrected = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Corrected details")).firstMatch
        XCTAssertTrue(corrected.waitForExistence(timeout: 5))
        recordScreen("InboxIdeaEdited", in: app)
        app.terminate(); app.launch()
        openInbox(app)
        XCTAssertTrue(corrected.waitForExistence(timeout: 5))
    }

    func testInboxNotesSnoozeAndBringBackSurviveRelaunch() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-inbox-export-fixture"]; app.launch()
        openInbox(app)
        editNotes("inbox.notes.open", adding: "Called the shop. Next: book a visit.", in: app)
        recordScreen("InboxTaskNotes", in: app)
        swipeIdeaAction("open", action: "snooze", in: app)
        app.buttons["snooze.week"].tap()
        if app.buttons["Keep chosen date"].waitForExistence(timeout: 2) { app.buttons["Keep chosen date"].tap() }
        let snoozed = element(app, "inbox.snoozed")
        reveal(snoozed, in: app); snoozed.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Returns ")).firstMatch.waitForExistence(timeout: 5))
        recordScreen("InboxSnoozed", in: app)
        app.terminate(); app.launchArguments = []; app.launch(); openInbox(app)
        reveal(snoozed, in: app); snoozed.tap()
        openIdeaEditor("open", in: app)
        XCTAssertEqual(element(app, "task-planning.notes").label, "Called the shop. Next: book a visit.")
        let bringBack = app.buttons["task-planning.bring-back"]; reveal(bringBack, in: app); bringBack.tap()
        let returned = element(app, "inbox.details.open")
        for _ in 0..<5 { if returned.exists, returned.isHittable { break }; app.swipeDown() }
        XCTAssertTrue(returned.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["ranking.first"].exists)
        recordScreen("InboxReturnedFromSnooze", in: app)
    }

    func testRankingEditsCompletesAndMovesToReferenceWithoutLeavingReview() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-inbox-fixture"]; app.launch()
        openInbox(app); openRanking(app)
        let first = app.buttons["ranking.first"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        let original = first.label
        editNotes("ranking.first.notes", adding: "Reviewed during ranking", in: app)
        XCTAssertEqual(first.label, original)
        app.buttons["ranking.first.actions"].tap(); app.buttons["Move to Reference"].tap()
        XCTAssertFalse(first.exists && first.label == original)
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        let completed = first.label
        let markDone = app.buttons["ranking.first.done"]
        XCTAssertTrue(markDone.waitForExistence(timeout: 5)); markDone.tap()
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !first.exists || first.label != completed }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed)
        recordScreen("RankingActions", in: app)
        app.navigationBars["Rank ideas"].buttons["Done"].tap()
        let header = element(app, "inbox.reference-title"); reveal(header, in: app)
        XCTAssertTrue(header.label.contains("1"))
        XCTAssertTrue(app.staticTexts[original.replacingOccurrences(of: "Choose: ", with: "")].exists)
        recordScreen("InboxReference", in: app)
        app.terminate(); app.launchArguments = []; app.launch(); openInbox(app)
        reveal(header, in: app); XCTAssertTrue(app.staticTexts[original.replacingOccurrences(of: "Choose: ", with: "")].exists)
    }

    func testCustomDaySnoozeOffersMondayAndKeepsTaskInSnoozedSection() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-inbox-export-fixture"]; app.launch()
        openInbox(app)
        swipeIdeaAction("open", action: "snooze", in: app)
        let days = app.textFields["snooze.days"]
        XCTAssertTrue(days.waitForExistence(timeout: 5)); days.tap()
        // Always choose the upcoming Saturday, so the weekend prompt is deterministic.
        let weekday = Calendar.current.component(.weekday, from: Date())
        let count = (7 - weekday + 7) % 7
        days.typeText(XCUIKeyboardKey.delete.rawValue + String(count == 0 ? 7 : count))
        if app.buttons["keyboard.done"].exists { app.buttons["keyboard.done"].tap() }
        app.buttons["snooze.days-save"].tap()
        XCTAssertTrue(app.buttons["Move to Monday"].waitForExistence(timeout: 5))
        app.buttons["Move to Monday"].tap()
        let snoozed = element(app, "inbox.snoozed"); reveal(snoozed, in: app); snoozed.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Returns ")).firstMatch.exists)
        recordScreen("InboxWeekdaySnooze", in: app)
    }

    func testInboxAutoFocusesCaptureAndSavingNeverOpensRanking() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-ranked-inbox-fixture"]; app.launch()
        openInbox(app, capture: true)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        let field = element(app, "inbox.text")
        XCTAssertTrue(field.isHittable)
        recordScreen("InboxCaptureFirst", in: app)
        field.typeText("Quick capture without ranking")
        app.buttons["inbox.save"].tap()
        XCTAssertFalse(app.buttons["inbox.save"].isEnabled)
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        XCTAssertFalse(app.navigationBars["Rank ideas"].exists)
        XCTAssertTrue(app.buttons["inbox.new-shortcut"].label.contains("4"))
        app.buttons["inbox.new-shortcut"].tap()
        XCTAssertTrue(app.staticTexts["Quick capture without ranking"].waitForExistence(timeout: 5))
        app.terminate(); app.launchArguments = []; app.launch(); openInbox(app)
        app.buttons["inbox.new-shortcut"].tap()
        XCTAssertTrue(app.staticTexts["Quick capture without ranking"].waitForExistence(timeout: 5))
    }

    func testInboxReviewIsNearTopAndInsertionProgressSurvivesRelaunch() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-ranked-inbox-fixture"]; app.launch()
        openInbox(app)
        let review = app.buttons["inbox.review"]
        XCTAssertTrue(review.isHittable)
        XCTAssertLessThan(review.frame.minY, element(app, "inbox.ranked-title").frame.minY)
        recordScreen("InboxReviewAndSearch", in: app)
        review.tap()
        XCTAssertTrue(app.buttons["ranking.first"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["ranking.first"].label, "Choose: New manual idea")
        XCTAssertTrue(app.staticTexts["Which is more important to act on now?"].exists)
        app.buttons["ranking.first"].tap()
        let first = app.buttons["ranking.first"].label, second = app.buttons["ranking.second"].label
        recordScreen("ScreeningReview", in: app)
        app.navigationBars["Rank ideas"].buttons["Done"].tap()
        app.terminate(); app.launchArguments = []; app.launch(); openInbox(app)
        openRanking(app)
        XCTAssertEqual(app.buttons["ranking.first"].label, first)
        XCTAssertEqual(app.buttons["ranking.second"].label, second)
    }

    func testBacklogReviewCanPauseCaptureAndResumeAfterRelaunch() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-tournament-fixture"]; app.launch()
        openInbox(app, capture: true); openRanking(app)
        XCTAssertTrue(element(app, "ranking.review-progress").waitForExistence(timeout: 5))
        recordScreen("OptionalBacklogReview", in: app)
        app.buttons["ranking.first"].tap()
        let first = app.buttons["ranking.first"].label, second = app.buttons["ranking.second"].label
        app.navigationBars["Rank ideas"].buttons["Done"].tap()
        app.terminate(); app.launchArguments = []; app.launch(); openInbox(app, capture: true)
        openRanking(app)
        XCTAssertEqual(app.buttons["ranking.first"].label, first)
        XCTAssertEqual(app.buttons["ranking.second"].label, second)
        app.navigationBars["Rank ideas"].buttons["Done"].tap()
        let field = element(app, "inbox.text"); reveal(field, in: app); field.tap()
        field.typeText("A new idea during backlog review")
        app.buttons["inbox.save"].tap()
        XCTAssertFalse(app.navigationBars["Rank ideas"].exists)
        if app.buttons["keyboard.done"].exists { app.buttons["keyboard.done"].tap() }
        openRanking(app)
        XCTAssertEqual(app.buttons["ranking.first"].label, "Choose: A new idea during backlog review")
        recordScreen("NewestCaptureScreening", in: app)
    }

    func testOneRejectedNewIdeaEndsReviewAndShowsOptionalBacklogAndStaleness() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-screening-inbox-fixture"]; app.launch()
        openInbox(app, capture: true); openRanking(app)
        XCTAssertEqual(app.buttons["ranking.first"].label, "Choose: One quick new idea")
        XCTAssertEqual(app.buttons["ranking.second"].label, "Choose: Priority 20")
        XCTAssertTrue(element(app, "ranking.review-progress").exists)
        recordScreen("FastNewIdeaScreening", in: app)
        app.buttons["ranking.second"].tap()
        XCTAssertTrue(app.staticTexts["Review complete"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["ranking.first"].exists)
        XCTAssertEqual(app.buttons["ranking.more"].label, "Review oldest backlog ideas")
        recordScreen("NewIdeasReviewedOptionalBacklog", in: app)
        app.navigationBars["Rank ideas"].buttons["Done"].tap()
        let oldest = element(app, "inbox.backlog-oldest-review")
        reveal(oldest, in: app)
        let expectedAge = Date().addingTimeInterval(-18 * 86400).formatted(.relative(presentation: .numeric))
        XCTAssertTrue(oldest.label.contains(expectedAge))
        XCTAssertTrue(element(app, "inbox.backlog-undated").exists)
        recordScreen("BacklogReviewStaleness", in: app)
    }

    func testInboxSearchFindsCompletedAndNotesAndClearRestoresLists() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-inbox-export-fixture"]; app.launch()
        openInbox(app)
        let search = app.textFields["inbox.search"]; search.tap(); search.typeText("completed")
        XCTAssertTrue(app.staticTexts["Completed idea"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Deleted idea"].exists)
        XCTAssertFalse(app.staticTexts["Idea to analyze\nKeep every line"].exists)
        recordScreen("InboxSearchCompleted", in: app)
        app.buttons["inbox.search-clear"].tap()
        // Clearing can already be dismissing the keyboard. Tap the stable
        // navigation bar instead of a Done control that may disappear mid-tap.
        app.navigationBars["Inbox"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        editNotes("inbox.notes.open", adding: "Unique bicycle wheels", in: app)
        reveal(search, in: app); search.tap(); search.typeText("BICYCLE")
        XCTAssertTrue(app.staticTexts["Idea to analyze\nKeep every line"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Completed idea"].exists)
        recordScreen("InboxSearchNotes", in: app)
        app.buttons["inbox.search-clear"].tap()
        app.navigationBars["Inbox"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        XCTAssertTrue(element(app, "inbox.waiting-title").exists)
        XCTAssertFalse(app.navigationBars["Rank ideas"].exists)
    }

    func testInboxUsesJournalCategoriesAndCombinesCategoryAndTextSearch() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-inbox-fixture"]; app.launch()
        openInbox(app)
        openIdeaEditor("a", in: app)
        let categorize = app.buttons["task-planning.categories"]; reveal(categorize, in: app); categorize.tap()
        let context = element(app, "category-context.activity")
        XCTAssertTrue(context.waitForExistence(timeout: 5)); XCTAssertTrue(context.label.contains("First idea"))
        tapCategory("work", in: app); tapCategory("social", in: app)
        XCTAssertTrue(context.isHittable)
        app.buttons["idea-categories.done"].tap()
        XCTAssertTrue(categorize.label.contains("Work")); XCTAssertTrue(categorize.label.contains("Socializing"))
        app.buttons["task-planning.save"].tap()
        let filter = app.buttons["inbox.category-filter"]
        // The search row is above the current idea and can be unloaded by List.
        for _ in 0..<8 { if filter.exists, filter.isHittable { break }; app.swipeDown() }
        reveal(filter, in: app); filter.tap()
        app.buttons["inbox.filter.work"].tap()
        XCTAssertTrue(app.staticTexts["First idea"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Second idea"].exists)
        let search = app.textFields["inbox.search"]; search.tap(); search.typeText("first")
        if app.buttons["keyboard.done"].exists { app.buttons["keyboard.done"].tap() }
        XCTAssertTrue(app.staticTexts["First idea"].exists)
        recordScreen("InboxSharedCategoriesAndSearch", in: app)
        app.buttons["inbox.search-clear"].tap(); app.buttons["inbox.category-filter-clear"].tap()
        app.terminate(); app.launchArguments = []; app.launch(); openInbox(app)
        openIdeaEditor("a", in: app)
        reveal(categorize, in: app); XCTAssertTrue(categorize.label.contains("Work"))
    }

    func testRankingCanCategorizeWithoutAnsweringOrChangingTheComparison() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-inbox-fixture"]; app.launch()
        openInbox(app); openRanking(app)
        let first = app.buttons["ranking.first"], second = app.buttons["ranking.second"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        let firstTitle = first.label, secondTitle = second.label
        let categorize = app.buttons["ranking.first.category"]; categorize.tap()
        let context = element(app, "category-context.activity")
        XCTAssertTrue(context.waitForExistence(timeout: 5)); XCTAssertTrue(context.label.contains(firstTitle.replacingOccurrences(of: "Choose: ", with: "")))
        tapCategory("work", in: app)
        app.buttons["category-select.create"].tap()
        app.alerts.textFields["Group name"].typeText("Creative Projects")
        let create = app.alerts.buttons["Create"]
        XCTAssertTrue(create.isEnabled)
        recordScreen("RankingNewGroupDraft", in: app)
        create.tap()
        XCTAssertTrue(app.alerts["New group"].waitForNonExistence(timeout: 5))
        XCTAssertEqual(app.buttons["category-select.work"].value as? String, "Selected")
        let created = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "category-select.", "Creative Projects")).firstMatch
        XCTAssertTrue(created.exists); XCTAssertEqual(created.value as? String, "Selected")
        XCTAssertTrue(context.isHittable)
        app.buttons["idea-categories.done"].tap()
        XCTAssertEqual(first.label, firstTitle); XCTAssertEqual(second.label, secondTitle)
        XCTAssertTrue(categorize.label.contains("Work")); XCTAssertTrue(categorize.label.contains("Creative Projects"))
        recordScreen("RankingCategoryShortcut", in: app)
        app.navigationBars["Rank ideas"].buttons["Done"].tap()
        app.terminate(); app.launchArguments = []; app.launch(); openInbox(app); openRanking(app)
        XCTAssertEqual(first.label, firstTitle); XCTAssertEqual(second.label, secondTitle)
        XCTAssertTrue(categorize.label.contains("Creative Projects"))
    }

    private func openInbox(_ app: XCUIApplication, capture: Bool = false) {
        app.tabBars.buttons["Inbox"].tap()
        if !capture, app.keyboards.firstMatch.waitForExistence(timeout: 1) {
            // Setup should use the explicit dismissal control. A separate
            // keyboard test verifies tapping outside the input itself.
            let done = app.buttons["keyboard.done"]
            if done.waitForExistence(timeout: 5), done.isHittable { done.tap() }
            else { app.navigationBars["Inbox"].tap() }
            let hidden = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.keyboards.firstMatch)
            XCTAssertEqual(XCTWaiter.wait(for: [hidden], timeout: 5), .completed)
        }
    }

    private func allowReminders(in app: XCUIApplication) {
        let allow = app.buttons["reminders.allow"]
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let permission = springboard.alerts.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Allow")).firstMatch
        for _ in 0..<3 {
            // The validation script grants EventKit access before launch, but
            // an unrelated notification prompt can still cover this screen.
            if permission.waitForExistence(timeout: 1) { permission.tap() }
            if app.buttons["reminders.create"].exists { break }
            if allow.waitForExistence(timeout: 2) { allow.tap() }
            if permission.waitForExistence(timeout: 3) { permission.tap() }
            if app.buttons["reminders.create"].waitForExistence(timeout: 3) { break }
        }
        XCTAssertTrue(app.buttons["reminders.create"].waitForExistence(timeout: 10))
    }

    private func assertPendingReminders(_ count: Int, in app: XCUIApplication) {
        let pending = element(app, "reminders.pending-count"); reveal(pending, in: app)
        let expected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@ OR value == %@", "\(count)", "\(count)"), object: pending)
        XCTAssertEqual(XCTWaiter.wait(for: [expected], timeout: 15), .completed)
    }

    private func openRanking(_ app: XCUIApplication) {
        let review = app.buttons["inbox.review"]
        reveal(review, in: app); review.tap()
    }

    private func openHistory(_ app: XCUIApplication) {
        showToday(app)
        reveal(element(app, "report.range"), in: app)
    }
    private func openIdeaEditor(_ id: String, prefix: String = "inbox", in app: XCUIApplication) {
        if app.buttons["keyboard.done"].firstMatch.isHittable { app.buttons["keyboard.done"].firstMatch.tap() }
        let details = app.buttons["\(prefix).edit.\(id)"]; reveal(details, in: app); details.tap()
        XCTAssertTrue(app.buttons["task-planning.save"].waitForExistence(timeout: 5))
    }
    private func swipeIdeaAction(_ id: String, action: String, in app: XCUIApplication) {
        if app.buttons["keyboard.done"].firstMatch.isHittable { app.buttons["keyboard.done"].firstMatch.tap() }
        let details = app.buttons["inbox.edit.\(id)"]; reveal(details, in: app); details.swipeLeft()
        let button = app.buttons["inbox.\(action).\(id)"]
        XCTAssertTrue(button.waitForExistence(timeout: 5)); button.tap()
    }
    private func editNotes(_ id: String, adding text: String, in app: XCUIApplication) {
        if id.hasPrefix("inbox.notes.") {
            openIdeaEditor(String(id.dropFirst("inbox.notes.".count)), in: app)
            editInline("task-planning.notes", adding: text, in: app)
            app.buttons["task-planning.save"].tap()
        } else {
            let expand = element(app, "\(id).expand"); reveal(expand, in: app); expand.tap()
            editInline(id, adding: text, in: app)
        }
    }

    private func editInline(_ id: String, adding suffix: String, in app: XCUIApplication, finishEditing: Bool = true) {
        let label = element(app, id); reveal(label, in: app); label.tap()
        let field = element(app, id)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        dismissKeyboardIntroduction(in: app)
        field.typeText(suffix)
        let typed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            ((field.value as? String) ?? field.label).contains(suffix)
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [typed], timeout: 5), .completed)
        if finishEditing {
            finishInlineEditing(in: app)
        }
        if !id.hasPrefix("task-planning."), !id.hasPrefix("category-context.") { XCTAssertFalse(app.navigationBars["Edit idea"].exists) }
        XCTAssertFalse(app.navigationBars["Edit log text"].exists)
    }

    private func finishInlineEditing(in app: XCUIApplication) {
        dismissKeyboardIntroduction(in: app)
        let buttons = app.buttons.matching(identifier: "keyboard.done")
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            buttons.allElementsBoundByIndex.contains { $0.isHittable }
        }, object: nil)
        let result = XCTWaiter.wait(for: [ready], timeout: 10)
        if result != .completed { print("INLINE KEYBOARD FAILURE: \(app.debugDescription)") }
        XCTAssertEqual(result, .completed)
        guard let done = buttons.allElementsBoundByIndex.first(where: { $0.isHittable }) else {
            XCTFail("Keyboard Done must be visible and hittable"); return
        }
        done.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
    }

    private func switchGoalUnit(_ label: String, in app: XCUIApplication, expectedSelection: String? = nil) {
        let picker = app.segmentedControls["plan.unit"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5)); picker.buttons[label].tap()
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "selected == true"), object: picker.buttons[expectedSelection ?? label])
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 5), .completed)
    }

    func testDailyGoalsShowsTimeRemainingAndMatchingProgressWithoutTable() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-daily-goals-fixture"]; app.launch()
        app.tabBars.buttons["Commitments"].tap(); openCategoryTargets(in: app)
        XCTAssertEqual(element(app, "goals.time-left").label, "4h 30m left today")
        XCTAssertEqual(element(app, "goals.needed").label, "3h 0m left across your goals")
        XCTAssertEqual(element(app, "goals.other-time").label, "1h 30m for other activities")
        XCTAssertTrue(element(app, "goals.capacity-bar").exists)
        let music = element(app, "goals.progress.music")
        XCTAssertEqual(music.value as? String, "1h 0m of 3h 0m today. 2h 0m remaining")
        XCTAssertTrue(element(app, "goals.progress.teaching").exists)
        XCTAssertFalse(element(app, "goals.progress.work").exists)
        XCTAssertFalse(element(app, "goals.progress.food").exists)
        XCTAssertFalse(app.segmentedControls["plan.unit"].exists)
        XCTAssertFalse(app.buttons["plan.sort.today"].exists)
        recordScreen("DailyGoalsTimeAndProgress", in: app)
    }

    func testGoalBarsShareOneScaleWithoutParentTotals() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-daily-goals-proportional"]; app.launch()
        app.tabBars.buttons["Commitments"].tap(); openCategoryTargets(in: app)
        let music = element(app, "goals.target-bar.music"), teaching = element(app, "goals.target-bar.teaching")
        XCTAssertTrue(music.waitForExistence(timeout: 5)); XCTAssertTrue(teaching.exists)
        XCTAssertEqual(teaching.frame.width, music.frame.width * 2, accuracy: 2)
        XCTAssertFalse(element(app, "goals.progress.work").exists)
        XCTAssertTrue(element(app, "goals.progress.food").exists)
        XCTAssertEqual(element(app, "goals.needed").label, "1h 30m left across your goals")
        recordScreen("ProportionalLeafGoalBars", in: app)
    }

    func testDayBarShowsElapsedAndRemainingOnTheWholeWindowScale() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-daily-goals-fixture"]; app.launch()
        app.tabBars.buttons["Commitments"].tap(); openCategoryTargets(in: app)
        let bar = element(app, "goals.capacity-bar"), elapsed = element(app, "goals.day-segment.elapsed")
        let music = element(app, "goals.day-segment.goal:music"), teaching = element(app, "goals.day-segment.goal:teaching")
        let other = element(app, "goals.day-segment.other")
        XCTAssertTrue(elapsed.waitForExistence(timeout: 5))
        XCTAssertEqual(elapsed.frame.width / bar.frame.width, 0.7, accuracy: 0.01)
        XCTAssertEqual(music.frame.width, teaching.frame.width * 2, accuracy: 2)
        XCTAssertEqual(other.frame.width / bar.frame.width, 0.1, accuracy: 0.01)
        XCTAssertEqual(elapsed.frame.width + music.frame.width + teaching.frame.width + other.frame.width, bar.frame.width, accuracy: 2)
        XCTAssertTrue(app.staticTexts["Now"].exists)
        recordScreen("WholeDayElapsedAndRemainingGoals", in: app)
    }

    func testCompletedGoalsRemainVisibleWithoutOpeningAnotherSection() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-daily-goals-completed"]; app.launch()
        app.tabBars.buttons["Commitments"].tap(); openCategoryTargets(in: app)
        for id in ["music", "teaching", "food"] {
            let row = element(app, "goals.progress.\(id)")
            XCTAssertTrue(row.waitForExistence(timeout: 5))
            XCTAssertTrue((row.value as? String ?? "").contains("Goal met"))
        }
        XCTAssertFalse(element(app, "goals.progress.work").exists)
        XCTAssertFalse(element(app, "goals.met").exists)
        XCTAssertEqual(element(app, "goals.needed").label, "0m left across your goals")
        XCTAssertTrue(element(app, "goals.day-segment.other").exists)
        recordScreen("CompletedGoalsStayInList", in: app)
    }

    func testDailyGoalsMakesShortfallExplicit() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-daily-goals-overflow"]; app.launch()
        app.tabBars.buttons["Commitments"].tap(); openCategoryTargets(in: app)
        XCTAssertEqual(element(app, "goals.time-left").label, "4h 30m left today")
        XCTAssertEqual(element(app, "goals.needed").label, "12h 0m left across your goals")
        XCTAssertEqual(element(app, "goals.shortfall").label, "7h 30m more than the time left")
        XCTAssertFalse(element(app, "goals.other-time").exists)
        recordScreen("DailyGoalsShortfall", in: app)
    }

    func testDayWindowChangesGoalHoursWithoutClippingEarlierLogsOrAllDayAlerts() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-daily-goals-fixture"]; app.launch()
        app.tabBars.buttons["Commitments"].tap(); openCategoryTargets(in: app)
        app.buttons["goals.day-window"].tap()
        element(app, "goals.window-start").tap()
        let eight = app.buttons["08:00"]; reveal(eight, in: app); eight.tap()
        app.buttons["goals.window-save"].tap()
        let music = element(app, "goals.progress.music")
        XCTAssertTrue(music.waitForExistence(timeout: 5))
        XCTAssertEqual(music.value as? String, "1h 0m of 2h 48m today. 1h 48m remaining")
        XCTAssertEqual(element(app, "goals.time-left").label, "4h 30m left today")
        app.tabBars.buttons["Settings"].tap()
        let allDay = app.switches["settings.notifications-all-day"]; reveal(allDay, in: app)
        XCTAssertEqual(allDay.value as? String, "1")
        app.terminate(); app.launchArguments = []; app.launch()
        openGoalEditor(in: app); switchGoalUnit("Time", in: app)
        XCTAssertEqual(app.textFields["categories.target.music"].value as? String, "2.8")
    }

    func testEditingGoalUpdatesSimpleProgressImmediately() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-daily-goals-fixture"]; app.launch()
        openGoalEditor(in: app)
        setPlanNumber("categories.target.music", to: "30", in: app)
        app.buttons["Close"].tap()
        openCategoryTargets(in: app)
        let music = element(app, "goals.progress.music")
        XCTAssertTrue(music.waitForExistence(timeout: 5))
        XCTAssertEqual(music.value as? String, "1h 0m of 4h 30m today. 3h 30m remaining")
        XCTAssertEqual(element(app, "goals.needed").label, "4h 30m left across your goals")
        recordScreen("DailyGoalsAfterEditing", in: app)
    }

    func testGoalEditorEditsWithLargeHistoryAndKeepsParentTotals() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-daily-goals-large-editor"]; app.launch()
        openGoalEditor(in: app)
        setPlanNumber("categories.target.music", to: "27.5", in: app)
        let arrow = app.buttons["plan.children.work"]
        reveal(arrow, in: app)
        if arrow.label.hasPrefix("Expand ") { arrow.tap() }
        setPlanNumber("categories.target.teaching", to: "32.5", in: app)
        XCTAssertEqual(element(app, "categories.calculated-goal.work").value as? String, "32.5")
        XCTAssertEqual(app.textFields["categories.target.music"].value as? String, "27.5")
        recordScreen("GoalEditorWithLargeHistory", in: app)
        app.buttons["Close"].tap()
        XCTAssertFalse(element(app, "goals.progress.work").exists)
        app.terminate(); app.launchArguments = []; app.launch()
        openGoalEditor(in: app)
        XCTAssertEqual(app.textFields["categories.target.music"].value as? String, "27.5")
        let parent = element(app, "categories.calculated-goal.work"); reveal(parent, in: app)
        XCTAssertEqual(parent.value as? String, "32.5")
    }

    func testDailyGoalsWithoutHistoryUsesConfiguredWindowForGoalEditing() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-empty-ledger"]; app.launch()
        app.tabBars.buttons["Commitments"].tap(); openCategoryTargets(in: app)
        XCTAssertTrue(app.buttons["Choose favorites"].waitForExistence(timeout: 5))
        XCTAssertTrue(element(app, "goals.time-left").exists)
        app.buttons["goals.edit"].tap()
        app.buttons["plan.hide-blank-goals"].tap()
        switchGoalUnit("Time", in: app)
        setPlanNumber("categories.target.work", to: "3", in: app)
        switchGoalUnit("%", in: app)
        XCTAssertEqual(app.textFields["categories.target.work"].value as? String, "20")
        selectPlanCategory("work", in: app); app.buttons["plan.favorite"].tap()
        app.buttons["Close"].tap()
        openCategoryTargets(in: app)
        XCTAssertTrue(element(app, "goals.progress.work").waitForExistence(timeout: 5))
    }

    func testGoalEditorRetainsFeedbackWithoutDirectionArrows() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-goal-hours-fixture"]; app.launch()
        openGoalEditor(in: app)
        let todayMusic = element(app, "plan.actual.today.music"), weekMusic = element(app, "plan.actual.week.music")
        let weekWork = element(app, "plan.actual.week.work")
        XCTAssertTrue(todayMusic.waitForExistence(timeout: 5))
        XCTAssertTrue(todayMusic.label.contains("below goal"))
        XCTAssertTrue(weekMusic.label.contains("below goal"))
        XCTAssertTrue(weekWork.label.contains("above goal"))
        recordScreen("GoalEditorPercent", in: app)
        switchGoalUnit("Time", in: app)
        XCTAssertTrue(todayMusic.label.contains("below goal"))
        XCTAssertTrue(weekMusic.label.contains("below goal"))
        XCTAssertTrue(weekWork.label.contains("above goal"))
        app.buttons["plan.hide-blank-goals"].tap()
        let food = element(app, "plan.actual.week.food"); reveal(food, in: app)
        XCTAssertFalse((food.value as? String ?? "").contains("toward goal"))
        recordScreen("GoalEditorTime", in: app)
    }

    func testCommitmentsColumnHeadingsSortAndReverseWithinTheHierarchy() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-allocation-sort-fixture"]; app.launch()
        openGoalEditor(in: app)
        let work = element(app, "plan.name.work"), music = element(app, "plan.name.music")
        XCTAssertTrue(work.waitForExistence(timeout: 5))
        XCTAssertLessThan(music.frame.minY, work.frame.minY)
        app.buttons["plan.sort.goal"].tap()
        XCTAssertEqual(app.buttons["plan.sort.goal"].value as? String, "Descending")
        XCTAssertLessThan(work.frame.minY, music.frame.minY)
        app.buttons["plan.children.work"].tap()
        let teaching = element(app, "plan.name.teaching"), admin = element(app, "plan.name.admin")
        XCTAssertLessThan(work.frame.minY, teaching.frame.minY)
        XCTAssertLessThan(teaching.frame.minY, admin.frame.minY)
        XCTAssertLessThan(admin.frame.minY, music.frame.minY)
        recordScreen("CommitmentsSortGoalDescending", in: app)
        app.buttons["plan.sort.goal"].tap()
        XCTAssertEqual(app.buttons["plan.sort.goal"].value as? String, "Ascending")
        XCTAssertLessThan(music.frame.minY, work.frame.minY)
        XCTAssertLessThan(work.frame.minY, admin.frame.minY)
        XCTAssertLessThan(admin.frame.minY, teaching.frame.minY)
        app.buttons["plan.sort.category"].tap()
        XCTAssertLessThan(music.frame.minY, work.frame.minY)
        app.buttons["plan.sort.category"].tap()
        XCTAssertLessThan(work.frame.minY, music.frame.minY)
        XCTAssertTrue(app.segmentedControls["plan.unit"].isHittable)
    }

    func testCommitmentsActualSortsWorkInBothUnitsAndPersistWithBlankGoalsLast() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-allocation-sort-fixture"]; app.launch()
        openGoalEditor(in: app)
        app.buttons["plan.hide-blank-goals"].tap()
        let food = element(app, "plan.name.food"), work = element(app, "plan.name.work"), music = element(app, "plan.name.music")
        app.buttons["plan.sort.today"].tap()
        XCTAssertLessThan(work.frame.minY, music.frame.minY)
        XCTAssertLessThan(music.frame.minY, food.frame.minY)
        app.buttons["plan.sort.goal"].tap()
        XCTAssertLessThan(work.frame.minY, music.frame.minY)
        XCTAssertLessThan(music.frame.minY, food.frame.minY)
        app.buttons["plan.sort.goal"].tap()
        XCTAssertLessThan(music.frame.minY, work.frame.minY)
        XCTAssertLessThan(work.frame.minY, food.frame.minY)
        app.buttons["plan.sort.week"].tap()
        XCTAssertLessThan(food.frame.minY, work.frame.minY)
        XCTAssertLessThan(work.frame.minY, music.frame.minY)
        switchGoalUnit("Time", in: app)
        XCTAssertEqual(app.buttons["plan.sort.week"].value as? String, "Descending")
        XCTAssertLessThan(food.frame.minY, work.frame.minY)
        recordScreen("CommitmentsSortSevenDaysTime", in: app)
        app.terminate(); app.launchArguments = []; app.launch(); openGoalEditor(in: app)
        XCTAssertEqual(app.buttons["plan.sort.week"].value as? String, "Descending")
        XCTAssertTrue(app.segmentedControls["plan.unit"].buttons["Time"].isSelected)
        XCTAssertLessThan(food.frame.minY, work.frame.minY)
        app.buttons["plan.sort.week"].tap()
        XCTAssertEqual(app.buttons["plan.sort.week"].value as? String, "Ascending")
        XCTAssertLessThan(music.frame.minY, work.frame.minY)
        XCTAssertLessThan(work.frame.minY, food.frame.minY)
    }

    private func toggleDashboardZeroFilter(in app: XCUIApplication) {
        app.buttons["dashboard.filter"].tap()
        let filter = element(app, "dashboard.hide-zero-time")
        XCTAssertTrue(filter.waitForExistence(timeout: 5)); filter.tap()
        // A Toggle in a menu may keep its menu open on some iOS versions.
        if app.buttons["Dismiss context menu"].exists { app.buttons["Dismiss context menu"].tap() }
    }

    func testDashboardZeroFilterHidesEmptyBranchesAndUsesSelectedPeriod() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-zero-category-fixture"]; app.launch()
        XCTAssertTrue(app.buttons["dashboard.group.work"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["dashboard.group.music"].exists)
        XCTAssertFalse(app.buttons["dashboard.group.food"].exists)
        app.buttons["dashboard.children.work"].tap()
        XCTAssertTrue(app.buttons["dashboard.group.teaching"].exists)
        XCTAssertFalse(app.buttons["dashboard.group.admin"].exists)
        recordScreen("DashboardHideZeroTime", in: app)
        toggleDashboardZeroFilter(in: app)
        XCTAssertTrue(app.buttons["dashboard.group.admin"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["dashboard.group.music"].exists)
        recordScreen("DashboardShowZeroTime", in: app)
        toggleDashboardZeroFilter(in: app)
        XCTAssertFalse(app.buttons["dashboard.group.admin"].exists)
        element(app, "report.range").tap(); app.buttons["Past 7 days"].tap()
        XCTAssertTrue(app.buttons["dashboard.group.food"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["dashboard.group.music"].exists)
    }

    func testCommitmentsBlankGoalFilterIgnoresActualTimeAndKeepsZeroGoals() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-zero-category-fixture"]; app.launch()
        openGoalEditor(in: app)
        XCTAssertEqual(app.buttons["plan.hide-blank-goals"].value as? String, "On")
        // Actual time is deliberately irrelevant: Work has today's time and
        // Eating has historical time, but both have blank goals.
        XCTAssertFalse(element(app, "plan.name.work").exists)
        XCTAssertFalse(element(app, "plan.name.food").exists)
        XCTAssertTrue(element(app, "plan.name.music").exists)
        XCTAssertEqual(app.textFields["categories.target.unused-0"].value as? String, "0")
        XCTAssertFalse(element(app, "plan.name.unused-1").exists)
        app.buttons["plan.children.music"].tap()
        XCTAssertEqual(app.textFields["categories.target.guitar"].value as? String, "25")
        XCTAssertTrue(element(app, "plan.actual.today.guitar").label.contains("0.0%"))
        recordScreen("CommitmentsHideBlankGoals", in: app)
        switchGoalUnit("Time", in: app)
        XCTAssertTrue(element(app, "plan.name.guitar").exists)
        XCTAssertEqual(app.textFields["categories.target.unused-0"].value as? String, "0")
        XCTAssertFalse(element(app, "plan.name.food").exists)
        switchGoalUnit("%", in: app)
        app.buttons["plan.hide-blank-goals"].tap()
        XCTAssertTrue(element(app, "plan.name.food").waitForExistence(timeout: 5))
        let work = app.buttons["plan.children.work"]; reveal(work, in: app); work.tap()
        let admin = element(app, "plan.name.admin"); reveal(admin, in: app); XCTAssertTrue(admin.exists)
        app.terminate(); app.launchArguments = []; app.launch()
        XCTAssertEqual(app.buttons["dashboard.filter"].value as? String, "Zero-time categories hidden")
        openGoalEditor(in: app)
        XCTAssertEqual(app.buttons["plan.hide-blank-goals"].value as? String, "Off")
        let unused = element(app, "plan.name.unused-1"); reveal(unused, in: app); XCTAssertTrue(unused.exists)
    }

    func testCommitmentsUnitPickerStaysPinnedWhileScrollingAndSwitchingUnits() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-zero-category-fixture"]; app.launch()
        openGoalEditor(in: app)
        app.buttons["plan.hide-blank-goals"].tap()
        let picker = app.segmentedControls["plan.unit"]
        let initialY = picker.frame.minY
        let last = element(app, "plan.name.unused-29"); reveal(last, in: app)
        XCTAssertTrue(last.isHittable)
        XCTAssertTrue(picker.buttons["Time"].isHittable)
        XCTAssertEqual(picker.frame.minY, initialY, accuracy: 2)
        picker.buttons["Time"].tap()
        XCTAssertTrue(picker.buttons["Time"].isSelected)
        XCTAssertTrue(last.isHittable)
        XCTAssertEqual(picker.frame.minY, initialY, accuracy: 2)
        XCTAssertTrue(app.buttons["plan.hide-blank-goals"].isHittable)
        recordScreen("PinnedCommitmentsUnitsAtBottom", in: app)
    }

    func testGoalUnitsShowOneValueAndHourEditsConvertToFixedPercentages() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-goal-hours-fixture"]; app.launch()
        openGoalEditor(in: app)
        let weekMusic = element(app, "plan.actual.week.music"); reveal(weekMusic, in: app)
        XCTAssertTrue(weekMusic.label.contains("7.1%")); XCTAssertFalse(weekMusic.label.contains("1h"))
        switchGoalUnit("Time", in: app)
        reveal(weekMusic, in: app); XCTAssertTrue(weekMusic.label.contains("1h per day")); XCTAssertFalse(weekMusic.label.contains("%"))
        XCTAssertEqual(app.textFields["categories.target.music"].value as? String, "1.5")
        setPlanNumber("categories.target.teaching", to: "4", in: app)
        XCTAssertEqual(element(app, "categories.calculated-goal.work").value as? String, "4")
        XCTAssertEqual(app.textFields["categories.target.music"].value as? String, "1.5")
        recordScreen("GoalsTimeOnly", in: app)
        switchGoalUnit("%", in: app)
        let teaching = app.textFields["categories.target.teaching"]; reveal(teaching, in: app)
        XCTAssertEqual(teaching.value as? String, "26.67")
        XCTAssertEqual(app.textFields["categories.target.music"].value as? String, "10")
        recordScreen("GoalsPercentOnly", in: app)
        switchGoalUnit("Time", in: app)
        app.terminate(); app.launchArguments = []; app.launch(); openGoalEditor(in: app)
        XCTAssertTrue(app.segmentedControls["plan.unit"].buttons["Time"].isSelected)
        let expand = app.buttons["plan.children.work"]; reveal(expand, in: app); expand.tap()
        let restored = app.textFields["categories.target.teaching"]; reveal(restored, in: app)
        XCTAssertEqual(restored.value as? String, "4")
    }

    func testOptionalGoalsRemainEditableWithoutBalanceSummary() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-goal-hours-fixture"]; app.launch()
        openGoalEditor(in: app)
        XCTAssertFalse(app.staticTexts["Priority goals"].exists)
        XCTAssertFalse(app.staticTexts["Other activities"].exists)
        XCTAssertFalse(app.staticTexts["Over by"].exists)
        XCTAssertFalse(app.buttons["plan.copy-week"].exists)
        setPlanNumber("categories.target.music", to: "20", in: app)
        XCTAssertEqual(app.textFields["categories.target.music"].value as? String, "20")
        setPlanNumber("categories.target.music", to: "", in: app)
        XCTAssertFalse(app.textFields["categories.target.music"].exists)
        XCTAssertEqual(element(app, "categories.calculated-goal.work").value as? String, "20")
        recordScreen("CompactCommitmentsWithoutSummary", in: app)
    }

    func testTimeModeWithoutCompletedDataPreservesExistingPercentageGoals() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-empty-ledger"]; app.launch()
        openGoalEditor(in: app)
        setPlanNumber("categories.target.work", to: "30", in: app)
        switchGoalUnit("Time", in: app)
        let work = app.textFields["categories.target.work"]; reveal(work, in: app)
        XCTAssertTrue(work.isEnabled)
        XCTAssertEqual(work.value as? String, "4.5")
        XCTAssertFalse(app.buttons["plan.copy-week"].exists)
        switchGoalUnit("%", in: app)
        reveal(work, in: app); XCTAssertEqual(work.value as? String, "30")
    }

    func testInvalidHoursStayEditableAndUnitSwitchDoesNotDiscardThem() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-goal-hours-fixture"]; app.launch()
        openGoalEditor(in: app); switchGoalUnit("Time", in: app)
        setPlanNumber("categories.target.teaching", to: "20", in: app)
        let error = element(app, "plan.error"); reveal(error, in: app); XCTAssertTrue(error.exists)
        switchGoalUnit("%", in: app, expectedSelection: "Time")
        XCTAssertTrue(app.segmentedControls["plan.unit"].buttons["Time"].isSelected)
        let teaching = app.textFields["categories.target.teaching"]; reveal(teaching, in: app)
        XCTAssertEqual(teaching.value as? String, "20")
        setPlanNumber("categories.target.teaching", to: "4", in: app)
        XCTAssertEqual(element(app, "categories.calculated-goal.work").value as? String, "4")
        XCTAssertFalse(element(app, "plan.error").exists)
    }

    func testHistoricalAverageUsesCompletedDaysWhileTodayStaysLive() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-goal-hours-fixture"]; app.launch()
        openGoalEditor(in: app)
        XCTAssertEqual(element(app, "plan.coverage").label, "3 of 7")
        app.buttons["plan.children.work"].tap()
        let week = element(app, "plan.actual.week.teaching"); reveal(week, in: app)
        XCTAssertTrue(week.label.contains("28.6%"))
        switchGoalUnit("Time", in: app)
        reveal(week, in: app); XCTAssertTrue(week.label.contains("4h per day"))
        let today = element(app, "plan.actual.today.teaching"); XCTAssertFalse(today.label.contains("per day"))
        XCTAssertFalse(today.label.contains("%"))
        recordScreen("CompletedDayAverage", in: app)
    }

    func testGoalsAutosaveNestedValuesAndUnfinishedTotalsAcrossRestart() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-allocation-fixture"]; app.launch()
        openGoalEditor(in: app)
        XCTAssertFalse(app.buttons["categories.save-targets"].exists)
        XCTAssertFalse(app.textFields["categories.target.work"].exists)
        setPlanNumber("categories.target.teaching", to: "80", in: app)
        XCTAssertEqual(element(app, "categories.calculated-goal.work").value as? String, "80")
        setPlanNumber("categories.target.music", to: "30", in: app)
        setPlanNumber("categories.target.music", to: "20", in: app)
        recordScreen("CalculatedParentGoals", in: app)
        app.terminate(); app.launchArguments = []; app.launch(); openGoalEditor(in: app)
        XCTAssertEqual(element(app, "categories.calculated-goal.work").value as? String, "80")
        app.buttons["plan.children.work"].tap()
        XCTAssertEqual(app.textFields["categories.target.teaching"].value as? String, "80")
        XCTAssertEqual(app.textFields["categories.target.music"].value as? String, "20")
    }

    func testIndividualGoalCopyAndContextualHelpRemainWithoutBulkCopy() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-allocation-fixture"]; app.launch()
        openGoalEditor(in: app)
        XCTAssertFalse(app.staticTexts["Hold a category for actions."].exists)
        XCTAssertFalse(app.buttons["plan.copy-week"].exists)
        let musicValue = app.textFields["categories.target.music"].value as? String
        app.buttons["plan.children.work"].tap()
        let teaching = app.textFields["categories.target.teaching"]
        XCTAssertFalse((teaching.value as? String ?? "").isEmpty)
        XCTAssertEqual(element(app, "categories.calculated-goal.work").value as? String, teaching.value as? String)
        teaching.tap()
        XCTAssertTrue(app.buttons["plan.copy-focused-week"].waitForExistence(timeout: 5))
        app.buttons["plan.copy-focused-week"].tap(); app.buttons["keyboard.done"].firstMatch.tap()
        XCTAssertEqual(app.textFields["categories.target.music"].value as? String, musicValue)
        element(app, "plan.name.work").tap()
        XCTAssertTrue(app.buttons["category-detail.close"].waitForExistence(timeout: 5))
        app.buttons["category-detail.close"].tap()
        XCTAssertFalse(app.buttons["plan.copy-selected-week"].exists)
        app.buttons["plan.help"].tap()
        XCTAssertTrue(app.staticTexts["Goals & categories"].waitForExistence(timeout: 5))
        recordScreen("CalculatedGoalHelp", in: app)
    }

    func testNestedCalculatedGoalsAndDirectRowsHaveNoEditableTarget() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-allocation-fixture", "--ui-category-outline"]; app.launch()
        openGoalEditor(in: app)
        app.buttons["plan.hide-blank-goals"].tap()
        app.buttons["plan.children.work"].tap()
        app.buttons["plan.children.music"].tap()
        setPlanNumber("categories.target.guitar", to: "80", in: app)
        setPlanNumber("categories.target.teaching", to: "30", in: app)
        XCTAssertEqual(element(app, "categories.calculated-goal.music").value as? String, "80")
        XCTAssertEqual(element(app, "categories.calculated-goal.work").value as? String, "110")
        XCTAssertFalse(app.textFields["categories.target.work"].exists)
        XCTAssertFalse(app.textFields["categories.target.music"].exists)
        XCTAssertTrue(element(app, "categories.direct-goal.music").exists)
        recordScreen("NestedCalculatedGoalsAndDirectTime", in: app)
    }

    func testSingleTapCategoryActionsAndExplicitMultipleSelection() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-allocation-fixture"]; app.launch()
        openGoalEditor(in: app)
        element(app, "plan.name.work").tap()
        XCTAssertTrue(app.buttons["category-detail.logs"].waitForExistence(timeout: 5))
        app.buttons["category-detail.close"].tap()
        app.buttons["plan.select"].tap()
        element(app, "plan.name.work").tap()
        XCTAssertTrue(app.buttons["plan.rename"].exists); XCTAssertTrue(app.buttons["plan.create-child"].exists)
        let music = element(app, "plan.name.music"); reveal(music, in: app); music.tap()
        XCTAssertFalse(app.buttons["plan.rename"].exists); XCTAssertTrue(app.buttons["plan.group-selected"].exists)
        recordScreen("ExplicitMultipleCategorySelection", in: app)
        app.buttons["plan.selection-done"].tap()
        XCTAssertFalse(app.buttons["plan.group-selected"].exists)
        let create = app.buttons["plan.create-category"]; reveal(create, in: app)
        XCTAssertTrue(create.exists)
    }

    func testLogCategorySearchSelectsOnceKeepsKeyboardAndShowsRemovableTags() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-review-range-fixture"]; app.launch()
        let review = app.buttons["dashboard.review.uncategorized"]; reveal(review, in: app); review.tap()
        let search = app.textFields["category-search.field"]; search.tap(); search.typeText("work")
        app.buttons["category-select.work"].tap()
        XCTAssertTrue(app.buttons["category-tag.work"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        search.typeText("social")
        XCTAssertTrue(app.buttons["category-tag.work"].isHittable)
        app.buttons["category-select.social"].tap()
        XCTAssertTrue(app.buttons["category-tag.social"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["category-tag.work"].isHittable)
        recordScreen("PinnedTagsWithKeyboard", in: app)
        app.buttons["category-tag.work"].tap()
        XCTAssertFalse(app.buttons["category-tag.work"].exists)
        let save = app.buttons["log-review.save-next"]
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        XCTAssertFalse(app.buttons.matching(identifier: "keyboard.done").allElementsBoundByIndex.contains { $0.isHittable })
        XCTAssertTrue(save.isHittable)
        XCTAssertLessThanOrEqual(save.frame.maxY, app.keyboards.firstMatch.frame.minY)
        recordScreen("LogReviewSingleSaveWithKeyboard", in: app)
        save.tap()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 5))
        XCTAssertTrue(dashboardGroup("social", in: app).exists)
    }

    func testLogReviewSavesInlineTextCategoriesAndMoodWithOneTapThenAdvances() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-review-range-fixture"]; app.launch()
        element(app, "report.range").tap(); app.buttons["All time"].tap()
        let review = app.buttons["dashboard.review.uncategorized"]; reveal(review, in: app); review.tap()
        XCTAssertEqual(element(app, "log-review.position").label, "1 of 2")
        app.buttons["mood.4"].tap(); tapCategory("work", in: app)
        let activity = element(app, "category-context.activity"); activity.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        element(app, "category-context.activity").typeText(" corrected")
        let save = app.buttons["log-review.save-next"]
        XCTAssertTrue(save.isHittable)
        XCTAssertLessThanOrEqual(save.frame.maxY, app.keyboards.firstMatch.frame.minY)
        XCTAssertFalse(app.buttons.matching(identifier: "keyboard.done").allElementsBoundByIndex.contains { $0.isHittable })
        recordScreen("LogReviewSaveInlineEditDirectly", in: app)
        save.tap()
        XCTAssertEqual(element(app, "log-review.position").label, "2 of 2")
        XCTAssertEqual(element(app, "category-context.activity").label, "Older ungrouped observation")
        tapCategory("social", in: app); save.tap()
        XCTAssertTrue(app.navigationBars["Your time"].waitForExistence(timeout: 5))
        if app.buttons["log-review.close"].exists {
            recordScreen("ReviewAfterLastSave", in: app)
            print("REVIEW AFTER LAST SAVE: \(app.debugDescription)")
        }
        XCTAssertFalse(app.buttons["log-review.close"].exists)
        XCTAssertFalse(app.staticTexts["Review complete"].exists)
        app.terminate(); app.launchArguments = []; app.launch()
        dashboardGroup("work", in: app).tap(); openCategoryLogs(in: app)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "corrected")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Mood: 4/5"].exists)
    }

    func testInboxUsesSamePinnedTagsAndInlineTextEditing() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-inbox-fixture"]; app.launch()
        openInbox(app)
        editInline("inbox.details.a", adding: " updated", in: app)
        openIdeaEditor("a", in: app)
        let categorize = app.buttons["task-planning.categories"]; reveal(categorize, in: app); categorize.tap()
        let search = app.textFields["category-search.field"]; search.tap(); search.typeText("work")
        app.buttons["category-select.work"].tap()
        XCTAssertTrue(app.buttons["category-tag.work"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        search.typeText("social"); app.buttons["category-select.social"].tap()
        XCTAssertTrue(app.buttons["category-tag.social"].exists)
        app.buttons["keyboard.done"].firstMatch.tap()
        editInline("category-context.activity", adding: " categorized", in: app)
        XCTAssertTrue(app.buttons["category-tag.work"].exists); XCTAssertTrue(app.buttons["category-tag.social"].exists)
        recordScreen("InboxSharedTagPicker", in: app)
        app.buttons["idea-categories.done"].tap()
        XCTAssertTrue(categorize.label.contains("Work")); XCTAssertTrue(categorize.label.contains("Socializing"))
        app.buttons["task-planning.save"].tap()
        XCTAssertTrue(element(app, "inbox.details.a").label.contains("categorized"))
    }

    func testRankingInlineEditDoesNotChooseAndChoiceUsesSeparateButton() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-inbox-fixture"]; app.launch()
        openInbox(app); openRanking(app)
        let first = app.buttons["ranking.first"], second = app.buttons["ranking.second"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        let original = first.label, other = second.label
        editInline("ranking.first.text", adding: " corrected", in: app)
        XCTAssertEqual(first.label, original + " corrected"); XCTAssertEqual(second.label, other)
        XCTAssertFalse(app.navigationBars["Idea notes"].exists)
        editNotes("ranking.first.notes", adding: "Reviewed inline", in: app)
        XCTAssertEqual(first.label, original + " corrected"); XCTAssertEqual(second.label, other)
        recordScreen("InlineRankingWithSeparateChoice", in: app)
        first.tap()
        XCTAssertNotEqual(first.label, original + " corrected")
    }

    func testFocusTasksMigrateLinkedWorkAndEditWithoutSeparateGoalRows() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-dated-goals-fixture"]; app.launch()
        openGoalEditor(in: app)
        XCTAssertFalse(app.buttons["plan.create-goal"].exists)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "plan.dated-goal.")).count, 0)
        element(app, "plan.name.work").tap()
        XCTAssertTrue(app.buttons["category-detail.logs"].waitForExistence(timeout: 5))
        let focusRows = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "category-detail.focus.")).allElementsBoundByIndex
        XCTAssertEqual(Set(focusRows.map(\.identifier)).count, 2)
        recordScreen("SharedCategoryFocusTasks", in: app)
        app.buttons["category-detail.close"].tap(); app.buttons["Close"].tap()
        let row = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "Prepare DIGS lecture")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10)); row.tap()
        XCTAssertTrue(app.textFields["task-planning.hours"].waitForExistence(timeout: 5))
        XCTAssertTrue(element(app, "task-planning.logged").label.contains("1h"))
        setPlanNumber("task-planning.hours", to: "2", in: app)
        recordScreen("InboxTaskWorkEstimate", in: app)
        app.buttons["task-planning.save"].tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5)); XCTAssertTrue(row.label.contains("2h"))
        app.terminate(); app.launchArguments = []; app.launch()
        app.tabBars.buttons["Commitments"].tap()
        XCTAssertTrue(row.waitForExistence(timeout: 10)); XCTAssertTrue(row.label.contains("2h"))
    }

    func testReviewAssignsGoalAndSavesFromTopBarWithKeyboardOpen() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-dated-goals-fixture"]; app.launch()
        app.buttons["dashboard.review.uncategorized"].tap()
        let picker = element(app, "log-review.task"); XCTAssertTrue(picker.waitForExistence(timeout: 5)); picker.tap()
        app.buttons["Prepare SDES lecture"].tap()
        XCTAssertTrue(app.buttons["category-tag.work"].exists)
        let field = app.textFields["category-search.field"]; field.tap(); field.typeText("work")
        let next = app.buttons["log-review.save-next"]
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        XCTAssertTrue(next.isHittable)
        XCTAssertLessThan(next.frame.maxY, app.keyboards.firstMatch.frame.minY)
        XCTAssertTrue(app.navigationBars.buttons["log-review.save-next"].exists)
        recordScreen("ReviewSaveNextInTopBar", in: app)
        next.tap()
        let eventShown = app.buttons["log-review.skip-event"].waitForExistence(timeout: 5)
        if !eventShown {
            recordScreen("GoalReviewFailure", in: app)
            print("GOAL REVIEW APP STATE: \(app.state.rawValue)")
            if app.state == .runningForeground { print("GOAL REVIEW UI: \(app.debugDescription)") }
        }
        XCTAssertTrue(eventShown)
        app.buttons["log-review.skip-event"].tap()
        let reviewClosed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.buttons["log-review.close"])
        XCTAssertEqual(XCTWaiter.wait(for: [reviewClosed], timeout: 5), .completed)
        XCTAssertFalse(app.buttons["dashboard.review.uncategorized"].exists)
        app.terminate(); app.launchArguments = []; app.launch()
        app.tabBars.buttons["Commitments"].tap()
        let sdes = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "Prepare SDES lecture")).firstMatch
        XCTAssertTrue(sdes.waitForExistence(timeout: 10))
        XCTAssertFalse(sdes.label.contains("0m /"))
    }

    func testCalendarReviewUsesPhraseRulesAndKeepsCategoriesAfterRelaunch() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-empty-ledger", "--ui-calendar-matching"]; app.launch()
        let review = app.buttons["dashboard.review.uncategorized"]
        XCTAssertTrue(review.waitForExistence(timeout: 20)); review.tap()
        XCTAssertTrue(element(app, "log-review.calendar-period").waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["category-tag.guitar"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["category-tag.work"].exists)
        XCTAssertFalse(app.buttons["category-tag.music"].exists)
        XCTAssertTrue(element(app, "log-review.suggestion").label.contains("Your phrase rule"))
        recordScreen("CalendarUsesSharedPhraseRules", in: app)
        app.buttons["log-review.save-next"].tap()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 10))
        app.terminate(); app.launchArguments = []; app.launch()
        openLogs(app)
        let entry = element(app, "logs.entry.calendar-ui-matching")
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        app.buttons["Edit time and categories"].firstMatch.tap()
        let categories = element(app, "edit.category")
        XCTAssertTrue(categories.waitForExistence(timeout: 10))
        XCTAssertTrue(categories.label.contains("Guitar"), categories.label)
        XCTAssertTrue(categories.label.contains("Work"), categories.label)
    }

    func testCalendarReviewUsesLearnedMatchesFromConfirmedLogs() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-empty-ledger", "--ui-calendar-matching", "--ui-calendar-learned"]; app.launch()
        let review = app.buttons["dashboard.review.uncategorized"]
        XCTAssertTrue(review.waitForExistence(timeout: 20)); review.tap()
        XCTAssertTrue(app.buttons["category-tag.music"].waitForExistence(timeout: 15))
        let suggestion = element(app, "log-review.suggestion")
        XCTAssertTrue(suggestion.label.contains("Matched confirmed word: cello"), suggestion.label)
        XCTAssertFalse(app.buttons["category-tag.work"].exists)
        recordScreen("CalendarLearnsFromConfirmedLogs", in: app)
        app.buttons["log-review.save-next"].tap()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 10))
    }

    func testCalendarUncategorizedChoiceSurvivesLateMatchAndEditedTitle() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-empty-ledger", "--ui-calendar-matching", "--ui-calendar-matching-delay"]; app.launch()
        let review = app.buttons["dashboard.review.uncategorized"]
        XCTAssertTrue(review.waitForExistence(timeout: 20)); review.tap()
        XCTAssertTrue(element(app, "log-review.calendar-period").waitForExistence(timeout: 10))
        app.buttons["Uncategorized"].tap()
        editInline("category-context.activity", adding: " solo", in: app)
        let suggestion = element(app, "log-review.suggestion")
        let updated = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND label CONTAINS %@", "solo"), object: suggestion)
        XCTAssertEqual(XCTWaiter.wait(for: [updated], timeout: 20), .completed)
        for id in ["music", "guitar", "work", "personal"] { XCTAssertFalse(app.buttons["category-tag.\(id)"].exists) }
        recordScreen("CalendarKeepsExplicitUncategorized", in: app)
        app.buttons["log-review.save-next"].tap()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 10))
        // Normal launch runs the production background classifier too: the
        // user's explicit empty choice must stay confirmed after it runs.
        app.terminate(); app.launchArguments = []; app.launch()
        openLogs(app)
        XCTAssertTrue(element(app, "logs.entry.calendar-ui-matching").waitForExistence(timeout: 10))
        XCTAssertTrue(element(app, "logs.entry.calendar-ui-matching").label.contains("solo"))
        app.buttons["Edit time and categories"].firstMatch.tap()
        let categories = element(app, "edit.category")
        XCTAssertTrue(categories.waitForExistence(timeout: 10))
        XCTAssertTrue(categories.label.contains("Uncategorized"), categories.label)
    }

    func testCalendarConfirmationRecordsFullPeriodAndUpdatesGoal() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-dated-goals-fixture"]; app.launch()
        app.buttons["dashboard.review.uncategorized"].tap()
        tapCategory("work", in: app); app.buttons["log-review.save-next"].tap()
        element(app, "log-review.task").tap(); app.buttons["Prepare DIGS lecture"].tap()
        recordScreen("ConfirmCalendarPeriod", in: app)
        app.buttons["log-review.save-next"].tap()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Commitments"].tap()
        let digs = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "Prepare DIGS lecture")).firstMatch
        XCTAssertTrue(digs.waitForExistence(timeout: 10))
        XCTAssertTrue(digs.label.contains("2h 0m / 4h 0m"), digs.label)
        app.terminate(); app.launchArguments = []; app.launch()
        XCTAssertFalse(app.buttons["dashboard.calendar-events"].exists)
    }

    func testUnifiedCommitmentsAndPinnedGoalActions() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-feedback-fixture"]; app.launch()
        app.tabBars.buttons["Commitments"].tap()
        XCTAssertTrue(element(app, "goals.progress.work").waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "focus-task.progress.")).count == 2)
        XCTAssertFalse(app.buttons["dated-goals.category-targets"].exists)
        recordScreen("UnifiedCommitments", in: app)
        element(app, "goals.progress.work").tap()
        XCTAssertTrue(element(app, "category-detail.count").waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["category-detail.logs"].exists)
        app.buttons["category-detail.close"].tap()
        XCTAssertTrue(app.navigationBars["Commitments"].exists)
        openGoalEditor(in: app)
        if app.buttons["plan.hide-blank-goals"].value as? String == "On" { app.buttons["plan.hide-blank-goals"].tap() }
        let add = app.buttons["plan.create-category"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        let y = add.frame.midY
        app.swipeUp(); XCTAssertEqual(add.frame.midY, y, accuracy: 4)
        app.swipeUp(); XCTAssertEqual(add.frame.midY, y, accuracy: 4)
        recordScreen("PinnedGoalActions", in: app)
    }

    func testOneDayComparisonHasEarlierBaselineAndUnitSwitch() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-feedback-fixture"]; app.launch()
        app.buttons["Show day comparison"].tap()
        let baseline = element(app, "comparison.baseline")
        let opened = baseline.waitForExistence(timeout: 10)
        if !opened { recordScreen("ComparisonFailure", in: app); print("COMPARISON UI: \(app.debugDescription)") }
        XCTAssertTrue(opened)
        let original = baseline.label
        XCTAssertTrue(app.staticTexts["Today so far"].exists)
        recordScreen("DailyNumericComparison", in: app)
        app.buttons["comparison.previous"].tap()
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != %@", original), object: baseline)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed)
        app.segmentedControls["comparison.unit"].buttons["Time"].tap()
        XCTAssertFalse(app.staticTexts["Today so far"].exists)
        recordScreen("YesterdayTimeComparison", in: app)
    }

    func testSuggestedLogStaysInReviewAndConfirmationRemovesMarker() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-feedback-fixture"]; app.launch()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "awaiting category review")).firstMatch.waitForExistence(timeout: 10))
        app.buttons["dashboard.review.uncategorized"].tap()
        XCTAssertTrue(app.buttons["category-tag.work"].waitForExistence(timeout: 5))
        recordScreen("SuggestedLogReview", in: app)
        let field = app.textFields["category-search.field"]; field.tap(); field.typeText("work")
        XCTAssertTrue(app.buttons["log-review.save-next"].isHittable)
        app.buttons["log-review.save-next"].tap()
        XCTAssertTrue(app.buttons["log-review.skip-event"].waitForExistence(timeout: 5))
        app.buttons["log-review.skip-event"].tap()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "awaiting category review")).firstMatch.exists)
    }

    func testIdeaCategorizationHasInlineDetailsDoneDeleteAndUndo() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-category-workspace"]; app.launch()
        openInbox(app)
        app.buttons["inbox.categorize"].tap(); app.buttons["inbox.categorize-all"].tap()
        XCTAssertTrue(app.buttons["idea-review.done"].waitForExistence(timeout: 5))
        app.buttons["idea-review.notes.expand"].tap()
        element(app, "idea-review.notes").tap()
        element(app, "idea-review.notes").typeText("Extra detail saved while categorizing")
        XCTAssertTrue(app.buttons["idea-review.save-next"].isHittable)
        recordScreen("IdeaReviewInlineDetails", in: app)
        app.buttons["idea-review.save-next"].tap()
        XCTAssertEqual(element(app, "idea-review.position").label, "2 of 6")
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        let done = app.buttons["idea-review.done"]; reveal(done, in: app)
        done.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let advanced = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "3 of 6"), object: element(app, "idea-review.position"))
        XCTAssertEqual(XCTWaiter.wait(for: [advanced], timeout: 5), .completed)
        app.buttons["idea-review.delete"].tap()
        XCTAssertTrue(app.buttons["idea-review.undo-delete"].waitForExistence(timeout: 5))
        app.buttons["idea-review.undo-delete"].tap()
        app.buttons["idea-review.close"].tap()
        let search = app.textFields["inbox.search"]; reveal(search, in: app); search.tap(); search.typeText("Extra detail saved")
        app.buttons["keyboard.done"].firstMatch.tap()
        XCTAssertTrue(element(app, "inbox.details.uncategorized").waitForExistence(timeout: 5))
        recordScreen("CompactInboxSearch", in: app)
    }

    func testPieStaysUsableWhenReviewMergesTheLastUncategorizedSector() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-dated-goals-fixture"]; app.launch()
        app.buttons["Show pie chart"].tap()
        XCTAssertTrue(element(app, "report.pie.chart").waitForExistence(timeout: 5))
        app.buttons["dashboard.review.uncategorized"].tap()
        element(app, "log-review.task").tap(); app.buttons["Prepare SDES lecture"].tap()
        let search = app.textFields["category-search.field"]; search.tap(); search.typeText("work")
        app.buttons["log-review.save-next"].tap()
        XCTAssertTrue(app.buttons["log-review.skip-event"].waitForExistence(timeout: 5))
        app.buttons["log-review.skip-event"].tap()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 5))
        XCTAssertTrue(element(app, "report.pie.chart").exists)
        app.buttons["report.pie.group.work"].tap()
        XCTAssertTrue(element(app, "report.pie.selection").label.contains("Work"))
        recordScreen("PieAfterCategoryMerge", in: app)
    }

}
