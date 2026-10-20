import XCTest

final class TimeLedgerUITests: XCTestCase {
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
            if grouping.exists && grouping.isHittable && (!target.exists || (target.identifier != "plan.group-selected" && target.identifier != "plan.clear-selection")) {
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
        XCTAssertTrue(header.waitForExistence(timeout: 5))
        XCTAssertFalse(field.exists)
    }

    func testUnconfirmedSuggestionStaysUncategorizedUntilAcceptedInReview() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-empty-ledger"]; app.launch()
        log("Working on app", in: app)
        let review = app.buttons["dashboard.review.uncategorized"]; reveal(review, in: app); XCTAssertTrue(review.exists); review.tap()
        XCTAssertTrue(app.staticTexts["Suggested: Work"].waitForExistence(timeout: 5))
        let confirm = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "group.confirm.")).firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5)); confirm.tap()
        app.buttons["Done"].tap()
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
        let review = app.buttons["dashboard.review.uncategorized"]; reveal(review, in: app); review.tap()
        XCTAssertTrue(app.staticTexts["Quokka activity fixture"].waitForExistence(timeout: 5))
        app.buttons["Choose group"].tap(); app.buttons["category-select.social"].tap(); app.buttons["group-selection.done"].tap()
        let undo = app.buttons["group.undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5)); undo.tap()
        XCTAssertTrue(app.staticTexts["Quokka activity fixture"].waitForExistence(timeout: 5))
        app.buttons["Choose group"].tap(); app.buttons["category-select.social"].tap(); app.buttons["group-selection.done"].tap()
        app.buttons["Done"].tap()
        XCTAssertTrue(dashboardGroup("social", in: app).waitForExistence(timeout: 5))
    }

    func testGroupPickerKeepsMultipleSelectionsWhileCreatingAndCanCancel() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-grouping-ledger"]; app.launch()
        let review = app.buttons["dashboard.review.uncategorized"]; reveal(review, in: app); review.tap()
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
        let review = app.buttons["dashboard.review.uncategorized"]; reveal(review, in: app); review.tap()
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
        XCTAssertTrue(element(app, "edit.activity").waitForExistence(timeout: 5))
        let save = app.buttons["edit.save"]; reveal(save, in: app); save.tap()
        XCTAssertTrue(app.staticTexts["Legacy sample UI fixture"].waitForExistence(timeout: 5))
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
        app.buttons["Choose group"].tap()
        app.buttons["category-select.work"].tap(); app.buttons["category-select.social"].tap()
        app.buttons["group-selection.done"].tap(); app.buttons["group.done"].tap()
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
        XCTAssertTrue(app.staticTexts["Quokka activity fixture"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Older ungrouped observation"].exists)
        app.buttons["All days"].tap()
        let older = app.staticTexts["Older ungrouped observation"]; reveal(older, in: app)
        XCTAssertTrue(older.exists)
        recordScreen("ReviewVisibleDatesOrAllDays", in: app)
    }

    func testLongEntryStaysVisibleAboveTheCategoryChecklist() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-long-grouping-ledger"]; app.launch()
        let review = app.buttons["dashboard.review.uncategorized"]; reveal(review, in: app); review.tap()
        let choose = app.buttons["Choose group"]; reveal(choose, in: app); choose.tap()
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
        app.buttons["group-selection.done"].tap()
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
        let row = app.buttons["logs.entry.recent"]; reveal(row, in: app); row.swipeLeft()
        if app.buttons["Delete"].exists { app.buttons["Delete"].tap() }
        let undo = app.buttons["logs.undo-delete"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5)); undo.tap()
        XCTAssertTrue(app.buttons["logs.entry.recent"].waitForExistence(timeout: 5))
        let trash = app.buttons["logs.delete.recent"]; reveal(trash, in: app)
        recordScreen("VisibleLogDelete", in: app); trash.tap()
        XCTAssertFalse(app.buttons["logs.entry.recent"].exists)
        XCTAssertFalse(app.navigationBars["Edit log"].exists)
        XCTAssertTrue(undo.waitForExistence(timeout: 5)); undo.tap()
        XCTAssertTrue(app.buttons["logs.entry.recent"].waitForExistence(timeout: 5))
        app.buttons["logs.entry.recent"].tap()
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
        XCTAssertFalse(app.buttons["logs.entry.recent"].exists)
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
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "enable Watch alerts once")).firstMatch.exists)
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
        XCTAssertTrue(element(app, "dashboard.breakdown-title").waitForExistence(timeout: 10))
        XCTAssertFalse(element(app, "plan.total").exists)
        app.tabBars.buttons["Commitments"].tap()
        XCTAssertTrue(element(app, "plan.balance").waitForExistence(timeout: 5))
        XCTAssertEqual(element(app, "plan.balance").label, "55% left to assign")
        let save = app.buttons["categories.save-targets"]
        XCTAssertFalse(save.isEnabled)
        setPlanNumber("categories.target.work", to: "90", in: app)
        showPlanSummary(in: app)
        reveal(save, in: app); XCTAssertFalse(save.isEnabled)
        XCTAssertTrue(element(app, "plan.balance").label.contains("5% over"))
        setPlanNumber("categories.target.work", to: "80", in: app)
        showPlanSummary(in: app)
        reveal(save, in: app); XCTAssertFalse(save.isEnabled)
        XCTAssertTrue(element(app, "plan.balance").label.contains("5% left"))
        setPlanNumber("categories.target.work", to: "85", in: app)
        showPlanSummary(in: app)
        reveal(save, in: app); XCTAssertTrue(save.isEnabled); save.tap()
        XCTAssertEqual(element(app, "plan.balance").label, "100% assigned")
        XCTAssertFalse(save.isEnabled)
        recordScreen("LifeAreaPlan", in: app)
        app.terminate(); app.launchArguments = []; app.launch(); app.tabBars.buttons["Commitments"].tap()
        let work = app.textFields["categories.target.work"]; reveal(work, in: app)
        XCTAssertEqual(work.value as? String, "85")
        let music = app.textFields["categories.target.music"]; reveal(music, in: app)
        XCTAssertEqual(music.value as? String, "15")
    }

    func testMultiCategorySelectionResolvesParentConflictExplicitly() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-allocation-fixture"]; app.launch()
        app.tabBars.buttons["Log"].tap()
        let field = element(app, "checkin.activity"); field.tap(); field.typeText("Two activities")
        let selector = element(app, "checkin.category"); reveal(selector, in: app); selector.tap()
        XCTAssertEqual(element(app, "category-context.activity").label, "Two activities")
        app.buttons["category-select.work"].tap()
        app.buttons["category-select.teaching"].tap()
        XCTAssertTrue(app.alerts["Replace conflicting categories?"].waitForExistence(timeout: 5))
        app.alerts.buttons["Replace"].tap(); app.buttons["category-select.music"].tap()
        recordScreen("MultipleCategories", in: app)
        app.buttons["Done"].tap()
        let save = app.buttons["checkin.save"]; reveal(save, in: app); save.tap()
        XCTAssertTrue(app.staticTexts["Saved. You can change it anytime."].waitForExistence(timeout: 5))
    }

    func testCategoryRemainderKeepsOtherGoalsAndActivityLogs() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-commitments-fixture"]; app.launch()
        app.tabBars.buttons["Commitments"].tap()
        XCTAssertTrue(element(app, "plan.total").waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Weekly minimum"].exists)
        let remaining = app.buttons["plan.remaining.work"]; reveal(remaining, in: app); remaining.tap()
        XCTAssertEqual(app.textFields["categories.target.work"].value as? String, "85")
        let save = app.buttons["categories.save-targets"]; reveal(save, in: app); save.tap()
        let children = element(app, "plan.children.work"); reveal(children, in: app); children.tap()
        XCTAssertTrue(app.staticTexts["Teaching"].waitForExistence(timeout: 5))
        recordScreen("LifeAreaBreakdown", in: app)
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
        let workTarget = app.textFields["categories.target.work"]; reveal(workTarget, in: app)
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
        let goal = app.textFields["Personal projects goal percent"]; reveal(goal, in: app)
        XCTAssertEqual(goal.value as? String, "25")
        recordScreen("GroupedLifeAreas", in: app)
        app.terminate(); app.launchArguments = []; app.launch(); app.tabBars.buttons["Commitments"].tap()
        reveal(goal, in: app); XCTAssertEqual(goal.value as? String, "25")
        showPlanSummary(in: app); XCTAssertEqual(element(app, "plan.balance").label, "100% assigned")
        openLogs(app)
        XCTAssertTrue(app.staticTexts["Guitar practice"].waitForExistence(timeout: 5))
    }

    func testCommitmentsShowsAllRootCategoriesAndExpandsWithoutChangingSelection() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-life-area-fixture"]; app.launch()
        app.tabBars.buttons["Commitments"].tap()
        XCTAssertTrue(element(app, "plan.total").waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["plan.add-area"].exists)
        XCTAssertFalse(element(app, "plan.loose-categories").exists)
        XCTAssertFalse(app.buttons["plan.group-selected"].exists)
        let german = app.textFields["categories.target.german"]; reveal(german, in: app)
        XCTAssertTrue(german.exists)
        selectPlanCategory("german", in: app)
        let group = app.buttons["plan.group-selected"]
        XCTAssertEqual(group.label, "Group 1 selected")
        let work = app.buttons["plan.children.work"]; reveal(work, in: app); work.tap()
        let teaching = app.staticTexts["Teaching"]; reveal(teaching, in: app)
        XCTAssertTrue(teaching.exists)
        XCTAssertFalse(app.buttons["plan.select.teaching"].exists)
        XCTAssertEqual(group.label, "Group 1 selected")
        XCTAssertTrue(app.textFields["categories.target.work"].exists)
        recordScreen("CategoryTreeExpanded", in: app)
        app.buttons["plan.clear-selection"].tap()
        XCTAssertFalse(group.exists)
    }

    func testExpandedCategoryLogButtonsOpenOnlyTheirOwnLogs() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-allocation-fixture", "--ui-category-log-links"]; app.launch()
        app.tabBars.buttons["Commitments"].tap()
        let work = app.buttons["plan.children.work"]; reveal(work, in: app); work.tap()
        for id in ["teaching", "music"] {
            let child = element(app, "dashboard.group.\(id)"); reveal(child, in: app); child.tap()
            XCTAssertFalse(app.buttons["group.done"].exists)
        }
        for (id, name, activity, other) in [
            ("teaching", "Teaching", "Preparing classes", "Guitar practice"),
            ("music", "Music", "Guitar practice", "Preparing classes")
        ] {
            let logs = app.buttons["allocation.logs.\(id)"]; reveal(logs, in: app); logs.tap()
            XCTAssertTrue(app.navigationBars[name].waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts[activity].exists)
            XCTAssertFalse(app.staticTexts[other].exists)
            recordScreen("CategoryLogs-\(id)", in: app)
            let done = app.buttons["group.done"]; done.tap()
            let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: done)
            XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 5), .completed)
            let unexpectedSheet = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true"), object: done)
            unexpectedSheet.isInverted = true
            XCTAssertEqual(XCTWaiter.wait(for: [unexpectedSheet], timeout: 2), .completed)
            XCTAssertTrue(app.navigationBars["Commitments"].exists)
        }
    }

    func testGroupingProtectsUnsavedGoalsAndCancelKeepsSelection() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-life-area-fixture"]; app.launch()
        app.tabBars.buttons["Commitments"].tap()
        setPlanNumber("categories.target.work", to: "35", in: app)
        selectPlanCategory("admin", in: app); selectPlanCategory("music", in: app)
        app.buttons["plan.group-selected"].tap()
        let dialog = app.sheets["Save your goal changes before grouping?"]
        XCTAssertTrue(dialog.waitForExistence(timeout: 5))
        XCTAssertFalse(dialog.buttons["Save and group"].exists)
        dialog.buttons["Keep editing"].tap()
        XCTAssertEqual(app.buttons["plan.group-selected"].label, "Group 2 selected")
        let work = app.textFields["categories.target.work"]; reveal(work, in: app)
        XCTAssertEqual(work.value as? String, "35")
        app.buttons["plan.group-selected"].tap()
        app.sheets.buttons["Discard changes and group"].tap()
        XCTAssertTrue(element(app, "categories.destination").waitForExistence(timeout: 5))
        app.navigationBars["Group categories"].buttons["Cancel"].tap()
        XCTAssertEqual(app.buttons["plan.group-selected"].label, "Group 2 selected")
        reveal(work, in: app); XCTAssertEqual(work.value as? String, "30")
        recordScreen("DirectGroupingCancelled", in: app)
    }

    func testGroupingCanSaveACompleteDraftBeforePreviewingMove() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-life-area-fixture"]; app.launch()
        app.tabBars.buttons["Commitments"].tap()
        setPlanNumber("categories.target.work", to: "35", in: app)
        setPlanNumber("categories.target.music", to: "10", in: app)
        selectPlanCategory("admin", in: app); selectPlanCategory("music", in: app)
        app.buttons["plan.group-selected"].tap()
        let saveAndGroup = app.sheets.buttons["Save and group"]
        XCTAssertTrue(saveAndGroup.waitForExistence(timeout: 5)); saveAndGroup.tap()
        let name = app.textFields["categories.new-parent-name"]; XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap(); name.typeText("Personal projects"); app.buttons["keyboard.done"].tap()
        XCTAssertTrue(app.staticTexts["0% → 20%"].exists)
        app.buttons["categories.apply-move"].tap()
        let goal = app.textFields["Personal projects goal percent"]; reveal(goal, in: app)
        XCTAssertEqual(goal.value as? String, "20")
        app.terminate(); app.launchArguments = []; app.launch(); app.tabBars.buttons["Commitments"].tap()
        let work = app.textFields["categories.target.work"]; reveal(work, in: app)
        XCTAssertEqual(work.value as? String, "35")
        reveal(goal, in: app); XCTAssertEqual(goal.value as? String, "20")
    }

    private func showPlanSummary(in app: XCUIApplication) {
        let total = element(app, "plan.total")
        for _ in 0..<12 {
            if total.exists && total.isHittable { break }
            app.swipeDown()
        }
        reveal(total, in: app)
    }

    private func waitForGroupingToFinish(in app: XCUIApplication) {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.buttons["plan.group-selected"])
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 5), .completed)
    }

    private func selectPlanCategory(_ id: String, in app: XCUIApplication) {
        let button = app.buttons["plan.select.\(id)"]; reveal(button, in: app)
        XCTAssertTrue(button.isHittable); button.tap()
        XCTAssertEqual(button.value as? String, "Selected")
    }

    private func setPlanNumber(_ id: String, to value: String, in app: XCUIApplication) {
        let field = app.textFields[id]; reveal(field, in: app)
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 12)); field.typeText(value)
        XCTAssertEqual(field.value as? String, value)
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
        actions.tap(); app.buttons["Edit idea"].tap()
        let editor = app.textViews["capture.edit-text"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5)); editor.tap(); editor.typeText("\nCorrected details")
        app.buttons["capture.edit-save"].tap()
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
        reveal(actions, in: app); actions.tap(); app.buttons["Edit idea"].tap()
        let notes = app.textViews["capture.edit-notes"]
        XCTAssertTrue(notes.waitForExistence(timeout: 5)); notes.tap(); notes.typeText("Called the shop. Next: book a visit.")
        if app.buttons["keyboard.done"].exists { app.buttons["keyboard.done"].tap() }
        recordScreen("InboxTaskNotes", in: app)
        app.buttons["capture.edit-save"].tap()
        reveal(actions, in: app); actions.tap(); app.buttons["Snooze…"].tap()
        app.buttons["snooze.week"].tap()
        if app.buttons["Keep chosen date"].waitForExistence(timeout: 2) { app.buttons["Keep chosen date"].tap() }
        let snoozed = element(app, "inbox.snoozed")
        reveal(snoozed, in: app); snoozed.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Returns ")).firstMatch.waitForExistence(timeout: 5))
        recordScreen("InboxSnoozed", in: app)
        app.terminate(); app.launchArguments = []; app.launch(); openInbox(app)
        reveal(snoozed, in: app); snoozed.tap()
        reveal(actions, in: app); actions.tap(); app.buttons["Edit idea"].tap()
        XCTAssertEqual(notes.value as? String, "Called the shop. Next: book a visit.")
        app.buttons["Cancel"].tap()
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
        app.buttons["ranking.first.actions"].tap(); app.buttons["Edit idea"].tap()
        let notes = app.textViews["capture.edit-notes"]
        XCTAssertTrue(notes.waitForExistence(timeout: 5)); notes.tap(); notes.typeText("Reviewed during ranking")
        app.buttons["capture.edit-save"].tap()
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
        XCTAssertTrue(app.staticTexts[original].exists)
        recordScreen("InboxReference", in: app)
        app.terminate(); app.launchArguments = []; app.launch(); openInbox(app)
        reveal(header, in: app); XCTAssertTrue(app.staticTexts[original].exists)
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
        XCTAssertEqual(app.buttons["ranking.first"].label, "New manual idea")
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
        XCTAssertEqual(app.buttons["ranking.first"].label, "A new idea during backlog review")
        recordScreen("NewestCaptureScreening", in: app)
    }

    func testOneRejectedNewIdeaEndsReviewAndShowsOptionalBacklogAndStaleness() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-screening-inbox-fixture"]; app.launch()
        openInbox(app, capture: true); openRanking(app)
        XCTAssertEqual(app.buttons["ranking.first"].label, "One quick new idea")
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
        let actions = app.buttons["inbox.actions.open"]; reveal(actions, in: app); actions.tap()
        app.buttons["Edit idea"].tap()
        let notes = app.textViews["capture.edit-notes"]; notes.tap(); notes.typeText("Unique bicycle wheels")
        app.buttons["capture.edit-save"].tap()
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
        app.buttons["category-select.work"].tap(); app.buttons["category-select.social"].tap()
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
        XCTAssertTrue(context.waitForExistence(timeout: 5)); XCTAssertTrue(context.label.contains(firstTitle))
        app.buttons["category-select.work"].tap()
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
}
