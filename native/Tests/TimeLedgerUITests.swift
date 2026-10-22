import XCTest

final class TimeLedgerUITests: XCTestCase {
    override func tearDownWithError() throws {
        if testRun?.hasSucceeded == false { recordScreen("Failure", in: XCUIApplication()) }
        try super.tearDownWithError()
    }

    private func recordScreen(_ name: String, in app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
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
        app.tabBars.buttons["Log"].tap()
        let field = element(app, "checkin.activity")
        reveal(field, in: app); field.tap(); field.typeText(text)
        if confirmSuggestion {
            let use = app.buttons["checkin.confirm-suggestion"]
            reveal(use, in: app); use.tap()
        }
        let save = app.buttons["checkin.save"]
        reveal(save, in: app); save.tap()
        XCTAssertTrue(app.staticTexts["Saved. You can change it anytime."].waitForExistence(timeout: 5))
        app.tabBars.buttons["Today"].tap()
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

    private func openLogs(_ app: XCUIApplication) {
        app.tabBars.buttons["Log"].tap()
        let logs = element(app, "today.logs"); reveal(logs, in: app); logs.tap()
    }

    func testHomeShowsDashboardAndKeepsLoggingOnItsOwnTab() {
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
        XCTAssertGreaterThan(pages.frame.height, app.frame.height * 0.55)
        XCTAssertEqual(pages.frame.width, app.frame.width, accuracy: 2)
        let calendar = app.buttons["dashboard.calendar"]
        XCTAssertTrue(calendar.isHittable)
        XCTAssertLessThan(calendar.frame.maxY, header.frame.minY)
        XCTAssertFalse(app.buttons["dashboard.undo"].exists)
        let initialHeight = pages.frame.height
        app.buttons["Show pie chart"].tap()
        XCTAssertTrue(element(app, "report.pie.chart").waitForExistence(timeout: 5))
        XCTAssertEqual(pages.frame.height, initialHeight, accuracy: 2)
        XCTAssertTrue(app.tabBars.buttons["Log"].isHittable)
        app.buttons["Show breakdown"].tap()
        recordScreen("Dashboard", in: app)
        app.tabBars.buttons["Log"].tap()
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
        XCTAssertTrue(app.staticTexts["Quokka activity fixture"].waitForExistence(timeout: 5))
        app.buttons["Choose group"].tap(); tapCategory("social", in: app); app.buttons["group-selection.done"].tap()
        let undo = app.buttons["group.undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5)); undo.tap()
        XCTAssertTrue(app.staticTexts["Quokka activity fixture"].waitForExistence(timeout: 5))
        app.buttons["Choose group"].tap(); tapCategory("social", in: app); app.buttons["group-selection.done"].tap()
        app.buttons["Done"].tap()
        XCTAssertTrue(dashboardGroup("social", in: app).waitForExistence(timeout: 5))
    }

    func testGroupPickerKeepsMultipleSelectionsWhileCreatingAndCanCancel() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-grouping-ledger"]; app.launch()
        let review = dashboardGroup("uncategorized", in: app); reveal(review, in: app); review.tap()
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
        app.buttons["group.done"].tap()
        let row = dashboardGroup("work", in: app); reveal(row, in: app); row.tap()
        let choose = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "group.choose.")).firstMatch
        reveal(choose, in: app); choose.tap()
        XCTAssertEqual(work.value as? String, "Selected")
        XCTAssertEqual(personal.value as? String, "Selected")
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
        app.buttons["Choose group"].tap(); app.buttons["Create new group…"].tap()
        let field = app.alerts.textFields["Group name"]
        XCTAssertTrue(field.waitForExistence(timeout: 5)); field.typeText("Creative Practice")
        app.alerts.buttons["Create"].tap()
        app.buttons["group-selection.done"].tap()
        app.buttons["Done"].tap(); app.buttons["dashboard.groups"].tap()
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "groups.open.", "Creative Practice")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        let groupID = String(row.identifier.dropFirst("groups.open.".count)); reveal(row, in: app); row.tap()
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
        XCTAssertTrue(app.staticTexts["After former bedtime"].waitForExistence(timeout: 5))
        app.buttons["group.done"].tap()
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
        XCTAssertTrue(app.textFields.matching(NSPredicate(format: "identifier BEGINSWITH %@", "logs.entry.")).firstMatch.waitForExistence(timeout: 5))
        app.buttons["keyboard.done"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Legacy sample UI fixture"].exists)
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
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 5))
        openInbox(app)
        XCTAssertTrue(app.staticTexts["Follow up with a client UI test"].waitForExistence(timeout: 5))
    }

    func testQuickNotificationReplySavesWithoutEditorConfirmationAndSurvivesRelaunch() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-empty-ledger", "--ui-quick-reply"]; app.launch()
        openLogs(app)
        XCTAssertTrue(app.staticTexts["Direct notification reply UI fixture"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Today"].tap()
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
        let allow = app.buttons["reminders.allow"]
        if allow.waitForExistence(timeout: 2) {
            allow.tap()
            let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
            let permission = springboard.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Allow")).firstMatch
            if permission.waitForExistence(timeout: 5) { permission.tap() }
        }
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
        let actions = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "inbox.actions.")).firstMatch
        actions.tap(); app.buttons["Delete idea"].tap()
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
            XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Back from snooze")).firstMatch.exists)
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
        populated.tap()
        XCTAssertTrue(selection.label.contains("Work")); XCTAssertTrue(selection.label.contains("%"))
        recordScreen("FullScreenHeatmapPercentages", in: app)
        units.buttons["Hours"].tap()
        XCTAssertTrue(selection.label.contains("%")) // Details always retain both measures.
        XCTAssertTrue(app.buttons["dashboard.calendar"].isHittable)
        recordScreen("FullScreenHeatmapHours", in: app)
        work.tap()
        XCTAssertTrue(app.buttons["group.done"].waitForExistence(timeout: 5)); app.buttons["group.done"].tap()
        app.buttons["dashboard.calendar"].tap()
        XCTAssertTrue(element(app, "timeline.grid").waitForExistence(timeout: 5))
    }

    func testGroupCountsAndDeletionPreserveAllTimeLogsAfterRelaunch() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-group-history"]; app.launch()
        app.buttons["dashboard.groups"].tap()
        let group = app.buttons["groups.open.work"]; reveal(group, in: app)
        XCTAssertTrue(group.staticTexts["2"].exists); recordScreen("CategoryCounts", in: app); group.tap()
        app.buttons["View all logs (2)"].tap()
        XCTAssertTrue(app.staticTexts["Older work observation"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Recent work observation"].exists)
        app.buttons["group.done"].tap()
        app.buttons["group.delete"].tap(); app.sheets.buttons["Cancel"].firstMatch.tap()
        XCTAssertTrue(app.textFields["categories.name"].exists)
        app.buttons["group.delete"].tap()
        app.buttons.matching(NSPredicate(format: "label == %@ AND identifier != %@", "Delete category", "group.delete")).firstMatch.tap()
        XCTAssertFalse(app.buttons["groups.open.work"].exists)
        let uncategorized = app.buttons["groups.open.uncategorized"]; reveal(uncategorized, in: app); uncategorized.tap()
        XCTAssertTrue(app.staticTexts["Older work observation"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Recent work observation"].exists)
        app.terminate(); app.launchArguments = []; app.launch(); app.buttons["dashboard.groups"].tap()
        XCTAssertFalse(app.buttons["groups.open.work"].exists)
        reveal(uncategorized, in: app); uncategorized.tap()
        XCTAssertTrue(app.staticTexts["Older work observation"].waitForExistence(timeout: 5))
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
        let menu = app.buttons["inbox.actions.a"]; reveal(menu, in: app); menu.tap()
        app.buttons["Delete idea"].tap()
        XCTAssertFalse(app.staticTexts["First idea"].exists)
        app.buttons["inbox.undo-delete"].tap()
        XCTAssertTrue(app.staticTexts["First idea"].waitForExistence(timeout: 5))
        let restored = app.buttons["inbox.actions.a"]; reveal(restored, in: app); restored.tap()
        app.buttons["Delete idea"].tap()
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
        app.tabBars.buttons["Today"].tap()
        openHistory(app)
        element(app, "report.range").tap(); app.buttons["Past 7 days"].tap()
        app.tabBars.buttons["Log"].tap()
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
        app.tabBars.buttons["Today"].tap(); app.buttons["dashboard.groups"].tap()
        let work = app.buttons["groups.open.work"]; reveal(work, in: app); work.tap()
        app.buttons["View all logs (1)"].tap()
        XCTAssertTrue(app.staticTexts["Older work observation"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Recent work observation"].exists)
    }

    func testCategoryLogDeleteButtonUpdatesDashboardAndCanUndo() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-group-history"]; app.launch()
        dashboardGroup("work", in: app).tap()
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
        trash.tap(); app.buttons["group.done"].tap()
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
        app.tabBars.buttons["Today"].tap(); openInbox(app)
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
        app.tabBars.buttons["Settings"].tap()
        let timing = element(app, "settings.notification-timing")
        let interval = element(app, "settings.notification-interval")
        XCTAssertTrue(timing.waitForExistence(timeout: 5))
        XCTAssertTrue(timing.label.contains("Regular") || timing.value as? String == "Regular")
        interval.tap(); app.buttons["30 minutes"].tap()
        timing.tap(); app.buttons["Randomized"].tap()
        XCTAssertTrue(interval.label.contains("15 minutes") || interval.value as? String == "15 minutes")
        interval.tap(); app.buttons["20 minutes"].tap()
        let explanation = element(app, "settings.notification-explanation")
        XCTAssertTrue(explanation.label.contains("13.3–26.7"))
        let save = app.buttons["settings.save-notifications"]; reveal(save, in: app); save.tap()
        recordScreen("RandomizedNotificationSettings", in: app)
        app.terminate(); app.launchArguments = []; app.launch(); app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(timing.label.contains("Randomized") || timing.value as? String == "Randomized")
        XCTAssertTrue(interval.label.contains("20 minutes") || interval.value as? String == "20 minutes")
        timing.tap(); app.buttons["Regular"].tap()
        XCTAssertTrue(interval.label.contains("30 minutes") || interval.value as? String == "30 minutes")
        reveal(save, in: app); save.tap()
        app.terminate(); app.launch(); app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(interval.label.contains("30 minutes") || interval.value as? String == "30 minutes")
        XCTAssertTrue(timing.label.contains("Regular") || timing.value as? String == "Regular")
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
        app.tabBars.buttons["Commitments"].tap()
        XCTAssertFalse(app.buttons["categories.save-targets"].exists)
        setPlanNumber("categories.target.teaching", to: "90", in: app)
        setPlanNumber("categories.target.teaching", to: "80", in: app)
        setPlanNumber("categories.target.teaching", to: "85", in: app)
        app.terminate(); app.launchArguments = []; app.launch(); app.tabBars.buttons["Commitments"].tap()
        XCTAssertEqual(element(app, "categories.calculated-goal.work").value as? String, "85")
        XCTAssertEqual(app.textFields["categories.target.music"].value as? String, "15")
    }

    func testMultiCategorySelectionResolvesParentConflictExplicitly() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-allocation-fixture"]; app.launch()
        app.tabBars.buttons["Log"].tap()
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
        app.tabBars.buttons["Commitments"].tap()
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
        app.tabBars.buttons["Commitments"].tap()
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
        app.tabBars.buttons["Commitments"].tap()
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
        app.terminate(); app.launchArguments = []; app.launch(); app.tabBars.buttons["Commitments"].tap()
        reveal(goal, in: app); XCTAssertEqual(goal.value as? String, "25")
        openLogs(app)
        XCTAssertTrue(app.staticTexts["Guitar practice"].waitForExistence(timeout: 5))
    }

    func testCommitmentsShowsAllRootCategoriesAndExpandsWithoutChangingSelection() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-life-area-fixture"]; app.launch()
        app.tabBars.buttons["Commitments"].tap()
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
        app.tabBars.buttons["Commitments"].tap()
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
        // Leaf names and totals have no navigation action.
        guitar.tap()
        XCTAssertTrue(app.navigationBars["Commitments"].exists)
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
        app.tabBars.buttons["Commitments"].tap()
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
        app.tabBars.buttons["Commitments"].tap()
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
        XCTAssertTrue(app.staticTexts["Mood: 4/5"].waitForExistence(timeout: 5))
        let change = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "group.choose.")).firstMatch
        reveal(change, in: app); change.tap()
        let selectedMood = app.buttons["mood.4"]; reveal(selectedMood, in: app)
        XCTAssertEqual(selectedMood.value as? String, "Selected")
        app.buttons["mood.clear"].tap(); app.buttons["group-selection.done"].tap()
        XCTAssertFalse(app.staticTexts["Mood: 4/5"].exists)
        app.buttons["group.done"].tap()
        app.terminate(); app.launchArguments = []; app.launch()
        XCTAssertFalse(app.buttons["dashboard.review.uncategorized"].exists)
        app.tabBars.buttons["Log"].tap()
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
        XCTAssertTrue(app.staticTexts["Preparing classes"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Guitar practice"].exists)
        app.buttons["group.done"].tap()
        reveal(work, in: app); work.tap()
        XCTAssertFalse(app.buttons["dashboard.group.teaching"].exists)
        XCTAssertFalse(app.buttons["dashboard.group.guitar"].exists)
        app.buttons["Show pie chart"].tap()
        XCTAssertTrue(app.buttons["report.pie.group.work"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["report.pie.group.teaching"].exists)
    }

    func testCategoryPickerShowsAllHierarchyLevelsWithoutExpansionAndKeepsEntryVisible() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-allocation-fixture", "--ui-category-outline"]; app.launch()
        app.tabBars.buttons["Log"].tap()
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
        XCTAssertFalse(app.buttons["log-review.close"].exists)
        XCTAssertFalse(app.staticTexts["Review complete"].exists)
        XCTAssertFalse(app.buttons["dashboard.review.uncategorized"].exists)
    }

    func testReviewTextEditRetainsSearchSelectedCategoriesMoodAndPosition() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-review-range-fixture"]; app.launch()
        let review = app.buttons["dashboard.review.uncategorized"]; reveal(review, in: app); review.tap()
        app.buttons["mood.4"].tap(); tapCategory("work", in: app); tapCategory("social", in: app)
        let search = app.textFields["category-search.field"]; search.tap(); search.typeText("work")
        editInline("category-context.activity", adding: " corrected", in: app)
        XCTAssertTrue(element(app, "category-context.activity").label.contains("corrected"))
        XCTAssertEqual(search.value as? String, "work")
        XCTAssertEqual(element(app, "log-review.position").label, "1 of 1")
        XCTAssertTrue(app.buttons["category-tag.work"].exists); XCTAssertTrue(app.buttons["category-tag.social"].exists)
        app.buttons["category-search.clear"].tap()
        let mood = app.buttons["mood.4"]; reveal(mood, in: app); XCTAssertEqual(mood.value as? String, "Selected")
        recordScreen("InlineLogReview", in: app)
        app.buttons["log-review.save-next"].tap()
        let group = dashboardGroup("work", in: app); reveal(group, in: app); group.tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "corrected")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Mood: 4/5"].exists)
    }

    func testCategoryAssignmentCanEditTextOrCancelWithoutLosingDraftChoices() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-grouping-ledger"]; app.launch()
        let group = dashboardGroup("uncategorized", in: app); reveal(group, in: app); group.tap()
        app.buttons["Choose group"].tap()
        app.buttons["mood.3"].tap(); tapCategory("work", in: app)
        editInline("category-context.activity", adding: " corrected", in: app)
        XCTAssertTrue(element(app, "category-context.activity").label.contains("corrected"))
        XCTAssertTrue(app.buttons["category-tag.work"].exists)
        app.buttons["group-selection.done"].tap(); app.buttons["group.done"].tap()
        XCTAssertTrue(dashboardGroup("work", in: app).waitForExistence(timeout: 5))
    }

    func testCategorySearchKeepsHierarchyAndSelectionsAndCanCreateFromNoResults() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-allocation-fixture", "--ui-category-outline"]; app.launch()
        app.tabBars.buttons["Log"].tap()
        let field = element(app, "checkin.activity"); field.tap(); field.typeText("Activity to categorize")
        let picker = element(app, "checkin.category"); reveal(picker, in: app); picker.tap()
        let search = app.textFields["category-search.field"]
        search.tap(); search.typeText("guitar")
        XCTAssertTrue(app.buttons["category-select.work"].exists)
        XCTAssertTrue(app.buttons["category-select.music"].exists)
        XCTAssertFalse(app.buttons["category-select.teaching"].exists)
        let guitar = app.buttons["category-select.guitar"]; reveal(guitar, in: app); guitar.tap()
        XCTAssertTrue(element(app, "category-context.activity").isHittable)
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        app.buttons["category-search.clear"].tap()
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
        app.tabBars.buttons["Commitments"].tap()
        XCTAssertFalse(app.buttons["plan.manage-categories"].exists)
        XCTAssertFalse(app.buttons["plan.select.work"].exists)
        selectPlanCategory("work", in: app)
        app.buttons["plan.create-child"].tap()
        let name = app.textFields["category-name.field"]; XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap(); name.typeText("Hygiene"); app.buttons["category-name.save"].tap()
        XCTAssertFalse(app.buttons["plan.selection-done"].exists)
        let arrow = app.buttons["plan.children.work"]; reveal(arrow, in: app); arrow.tap()
        selectPlanCategory("teaching", in: app)
        recordScreen("CategorySelectionActions", in: app)
        app.buttons["plan.view-logs"].tap()
        XCTAssertTrue(app.staticTexts["Preparing classes"].waitForExistence(timeout: 5))
        app.buttons["group.select"].tap()
        element(app, "group.log.today-teaching").tap()
        app.buttons["group.move-logs"].tap()
        let destination = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "log-move.", "Hygiene")).firstMatch
        XCTAssertTrue(destination.waitForExistence(timeout: 5)); destination.tap()
        XCTAssertTrue(app.staticTexts["There are no logs in this group for this view."].waitForExistence(timeout: 5))
        app.buttons["group.done"].tap()
        XCTAssertFalse(app.buttons["plan.selection-done"].exists)
        let child = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label == %@", "plan.name.", "Hygiene")).firstMatch
        reveal(child, in: app); child.tap()
        app.buttons["plan.view-logs"].tap()
        XCTAssertTrue(app.staticTexts["Preparing classes"].waitForExistence(timeout: 5))
        app.buttons["group.done"].tap()
        XCUIDevice.shared.press(.home); app.activate()
        XCTAssertTrue(app.navigationBars["Commitments"].exists)
        recordScreen("CategoryOutlineAfterMove", in: app)
    }

    func testSelectingCategoriesAtAnyDepthOffersOnlyMoveForMultiple() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-allocation-fixture", "--ui-category-outline"]; app.launch()
        app.tabBars.buttons["Commitments"].tap()
        app.buttons["plan.hide-blank-goals"].tap()
        let arrow = app.buttons["plan.children.work"]; reveal(arrow, in: app); arrow.tap()
        selectPlanCategory("work", in: app); selectPlanCategory("teaching", in: app)
        XCTAssertTrue(app.buttons["plan.group-selected"].exists)
        XCTAssertFalse(app.buttons["plan.delete"].exists); XCTAssertFalse(app.buttons["plan.rename"].exists)
        XCTAssertFalse(app.buttons["plan.create-child"].exists); XCTAssertFalse(app.buttons["plan.view-logs"].exists)
        app.buttons["plan.selection-done"].tap()
        XCTAssertFalse(app.buttons["plan.group-selected"].exists)
    }

    func testCategoryRenameAndDeleteKeepLogsAndPromoteChildren() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-allocation-fixture"]; app.launch()
        app.tabBars.buttons["Commitments"].tap(); selectPlanCategory("work", in: app)
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
        XCTAssertFalse(app.buttons["plan.selection-done"].exists)
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
        if app.buttons["plan.selection-done"].exists && app.buttons["plan.select"].exists { app.buttons["plan.select"].tap() }
        let row = element(app, "plan.name.\(id)"); reveal(row, in: app); row.tap()
        XCTAssertEqual(row.value as? String, "Selected")
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
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "From Reminders")).firstMatch.exists)
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
        let allow = app.buttons["reminders.allow"]
        if allow.waitForExistence(timeout: 2) {
            allow.tap()
            let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
            let permission = springboard.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Allow")).firstMatch
            if permission.waitForExistence(timeout: 5) { permission.tap() }
        }
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
        let actions = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "inbox.actions.")).firstMatch
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
        let actions = app.buttons["inbox.actions.open"]
        editNotes("inbox.notes.open", adding: "Called the shop. Next: book a visit.", in: app)
        recordScreen("InboxTaskNotes", in: app)
        reveal(actions, in: app); actions.tap(); app.buttons["Snooze…"].tap()
        app.buttons["snooze.week"].tap()
        if app.buttons["Keep chosen date"].waitForExistence(timeout: 2) { app.buttons["Keep chosen date"].tap() }
        let snoozed = element(app, "inbox.snoozed")
        reveal(snoozed, in: app); snoozed.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Returns ")).firstMatch.waitForExistence(timeout: 5))
        recordScreen("InboxSnoozed", in: app)
        app.terminate(); app.launchArguments = []; app.launch(); openInbox(app)
        reveal(snoozed, in: app); snoozed.tap()
        let expandNotes = element(app, "inbox.notes.open.expand"); reveal(expandNotes, in: app); expandNotes.tap()
        XCTAssertEqual(element(app, "inbox.notes.open").label, "Called the shop. Next: book a visit.")
        reveal(actions, in: app); actions.tap(); app.buttons["Bring back now"].tap()
        let returned = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Back from snooze")).firstMatch
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
        app.buttons["ranking.first.actions"].tap()
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
        let actions = app.buttons["inbox.actions.open"]; reveal(actions, in: app)
        actions.tap(); app.buttons["Snooze…"].tap()
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
        XCTAssertEqual(app.buttons["ranking.second"].label, "Priority 20")
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
        if app.buttons["keyboard.done"].exists { app.buttons["keyboard.done"].tap() }
        editNotes("inbox.notes.open", adding: "Unique bicycle wheels", in: app)
        reveal(search, in: app); search.tap(); search.typeText("BICYCLE")
        XCTAssertTrue(app.staticTexts["Idea to analyze\nKeep every line"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Completed idea"].exists)
        recordScreen("InboxSearchNotes", in: app)
        app.buttons["inbox.search-clear"].tap()
        if app.buttons["keyboard.done"].exists { app.buttons["keyboard.done"].tap() }
        XCTAssertTrue(element(app, "inbox.waiting-title").exists)
        XCTAssertFalse(app.navigationBars["Rank ideas"].exists)
    }

    func testInboxUsesJournalCategoriesAndCombinesCategoryAndTextSearch() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-inbox-fixture"]; app.launch()
        openInbox(app)
        let categorize = app.buttons["inbox.category.a"]; reveal(categorize, in: app); categorize.tap()
        let context = element(app, "category-context.activity")
        XCTAssertTrue(context.waitForExistence(timeout: 5)); XCTAssertTrue(context.label.contains("First idea"))
        tapCategory("work", in: app); tapCategory("social", in: app)
        XCTAssertTrue(context.isHittable)
        app.buttons["idea-categories.done"].tap()
        XCTAssertTrue(categorize.label.contains("Work")); XCTAssertTrue(categorize.label.contains("Socializing"))
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
        app.tabBars.buttons["Today"].tap()
        reveal(element(app, "report.range"), in: app)
    }
    private func editNotes(_ id: String, adding text: String, in app: XCUIApplication) {
        let expand = element(app, "\(id).expand"); reveal(expand, in: app); expand.tap()
        editInline(id, adding: text, in: app)
    }

    private func editInline(_ id: String, adding suffix: String, in app: XCUIApplication) {
        let label = element(app, id); reveal(label, in: app); label.tap()
        let field = element(app, id)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        field.typeText(suffix)
        let done = app.buttons["keyboard.done"].firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 5)); done.tap()
        XCTAssertFalse(app.navigationBars["Edit idea"].exists)
        XCTAssertFalse(app.navigationBars["Edit log text"].exists)
    }

    private func switchGoalUnit(_ label: String, in app: XCUIApplication) {
        let picker = app.segmentedControls["plan.unit"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5)); picker.buttons[label].tap()
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
        app.tabBars.buttons["Commitments"].tap()
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
        app.tabBars.buttons["Commitments"].tap()
        XCTAssertEqual(app.buttons["plan.hide-blank-goals"].value as? String, "Off")
        let unused = element(app, "plan.name.unused-1"); reveal(unused, in: app); XCTAssertTrue(unused.exists)
    }

    func testCommitmentsUnitPickerStaysPinnedWhileScrollingAndSwitchingUnits() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-zero-category-fixture"]; app.launch()
        app.tabBars.buttons["Commitments"].tap()
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
        app.tabBars.buttons["Commitments"].tap()
        let weekMusic = element(app, "plan.actual.week.music"); reveal(weekMusic, in: app)
        XCTAssertTrue(weekMusic.label.contains("7.1%")); XCTAssertFalse(weekMusic.label.contains("1h"))
        switchGoalUnit("Time", in: app)
        reveal(weekMusic, in: app); XCTAssertTrue(weekMusic.label.contains("1h per day")); XCTAssertFalse(weekMusic.label.contains("%"))
        XCTAssertEqual(app.textFields["categories.target.music"].value as? String, "1.4")
        setPlanNumber("categories.target.teaching", to: "4", in: app)
        XCTAssertEqual(element(app, "categories.calculated-goal.work").value as? String, "4")
        XCTAssertEqual(app.textFields["categories.target.music"].value as? String, "1.4")
        recordScreen("GoalsTimeOnly", in: app)
        switchGoalUnit("%", in: app)
        let teaching = app.textFields["categories.target.teaching"]; reveal(teaching, in: app)
        XCTAssertEqual(teaching.value as? String, "28.57")
        XCTAssertEqual(app.textFields["categories.target.music"].value as? String, "10")
        recordScreen("GoalsPercentOnly", in: app)
        switchGoalUnit("Time", in: app)
        app.terminate(); app.launchArguments = []; app.launch(); app.tabBars.buttons["Commitments"].tap()
        XCTAssertTrue(app.segmentedControls["plan.unit"].buttons["Time"].isSelected)
        let expand = app.buttons["plan.children.work"]; reveal(expand, in: app); expand.tap()
        let restored = app.textFields["categories.target.teaching"]; reveal(restored, in: app)
        XCTAssertEqual(restored.value as? String, "4")
    }

    func testOptionalGoalsRemainEditableWithoutBalanceSummary() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-goal-hours-fixture"]; app.launch()
        app.tabBars.buttons["Commitments"].tap()
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
        app.tabBars.buttons["Commitments"].tap()
        setPlanNumber("categories.target.work", to: "30", in: app)
        switchGoalUnit("Time", in: app)
        let work = app.textFields["categories.target.work"]; reveal(work, in: app)
        XCTAssertFalse(work.isEnabled)
        XCTAssertFalse(app.buttons["plan.copy-week"].exists)
        switchGoalUnit("%", in: app)
        reveal(work, in: app); XCTAssertEqual(work.value as? String, "30")
    }

    func testInvalidHoursStayEditableAndUnitSwitchDoesNotDiscardThem() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-goal-hours-fixture"]; app.launch()
        app.tabBars.buttons["Commitments"].tap(); switchGoalUnit("Time", in: app)
        setPlanNumber("categories.target.teaching", to: "20", in: app)
        let error = element(app, "plan.error"); reveal(error, in: app); XCTAssertTrue(error.exists)
        switchGoalUnit("%", in: app)
        XCTAssertTrue(app.segmentedControls["plan.unit"].buttons["Time"].isSelected)
        let teaching = app.textFields["categories.target.teaching"]; reveal(teaching, in: app)
        XCTAssertEqual(teaching.value as? String, "20")
        setPlanNumber("categories.target.teaching", to: "4", in: app)
        XCTAssertEqual(element(app, "categories.calculated-goal.work").value as? String, "4")
        XCTAssertFalse(element(app, "plan.error").exists)
    }

    func testHistoricalAverageUsesCompletedDaysWhileTodayStaysLive() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-goal-hours-fixture"]; app.launch()
        app.tabBars.buttons["Commitments"].tap()
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
        app.tabBars.buttons["Commitments"].tap()
        XCTAssertFalse(app.buttons["categories.save-targets"].exists)
        XCTAssertFalse(app.textFields["categories.target.work"].exists)
        setPlanNumber("categories.target.teaching", to: "80", in: app)
        XCTAssertEqual(element(app, "categories.calculated-goal.work").value as? String, "80")
        setPlanNumber("categories.target.music", to: "30", in: app)
        setPlanNumber("categories.target.music", to: "20", in: app)
        recordScreen("CalculatedParentGoals", in: app)
        app.terminate(); app.launchArguments = []; app.launch(); app.tabBars.buttons["Commitments"].tap()
        XCTAssertEqual(element(app, "categories.calculated-goal.work").value as? String, "80")
        app.buttons["plan.children.work"].tap()
        XCTAssertEqual(app.textFields["categories.target.teaching"].value as? String, "80")
        XCTAssertEqual(app.textFields["categories.target.music"].value as? String, "20")
    }

    func testIndividualGoalCopyAndContextualHelpRemainWithoutBulkCopy() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-allocation-fixture"]; app.launch()
        app.tabBars.buttons["Commitments"].tap()
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
        XCTAssertFalse(app.buttons["plan.copy-selected-week"].exists)
        app.buttons["plan.selection-done"].tap()
        app.buttons["plan.help"].tap()
        XCTAssertTrue(app.staticTexts["Goals & categories"].waitForExistence(timeout: 5))
        recordScreen("CalculatedGoalHelp", in: app)
    }

    func testNestedCalculatedGoalsAndDirectRowsHaveNoEditableTarget() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-allocation-fixture", "--ui-category-outline"]; app.launch()
        app.tabBars.buttons["Commitments"].tap()
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
        app.tabBars.buttons["Commitments"].tap()
        element(app, "plan.name.work").tap()
        XCTAssertTrue(app.buttons["plan.rename"].exists); XCTAssertTrue(app.buttons["plan.create-child"].exists)
        app.buttons["plan.select"].tap()
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
        app.buttons["keyboard.done"].firstMatch.tap()
        app.buttons["log-review.save-next"].tap()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 5))
        XCTAssertTrue(dashboardGroup("social", in: app).exists)
    }

    func testInboxUsesSamePinnedTagsAndInlineTextEditing() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-inbox-fixture"]; app.launch()
        openInbox(app)
        editInline("inbox.details.a", adding: " updated", in: app)
        let categorize = app.buttons["inbox.category.a"]; reveal(categorize, in: app); categorize.tap()
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
        XCTAssertTrue(element(app, "inbox.details.a").label.contains("categorized"))
        XCTAssertTrue(categorize.label.contains("Work")); XCTAssertTrue(categorize.label.contains("Socializing"))
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

}
