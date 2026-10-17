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
        for _ in 0..<10 {
            let top = app.navigationBars.firstMatch.exists ? app.navigationBars.firstMatch.frame.maxY : app.frame.minY
            var bottom = app.tabBars.firstMatch.exists ? app.tabBars.firstMatch.frame.minY : app.frame.maxY
            if app.keyboards.firstMatch.exists { bottom = min(bottom, app.keyboards.firstMatch.frame.minY) }
            let frame = target.exists ? target.frame : .zero
            if target.exists, !frame.isEmpty, frame.minY >= top, frame.maxY <= bottom - 8 { return }
            // Short drags keep lazy Form rows from being skipped by momentum.
            let height = max(100, bottom - top)
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let high = origin.withOffset(CGVector(dx: app.frame.midX, dy: top + height * 0.3))
            let low = origin.withOffset(CGVector(dx: app.frame.midX, dy: top + height * 0.75))
            if !frame.isEmpty, frame.maxY < top { high.press(forDuration: 0.01, thenDragTo: low) }
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
        XCTAssertFalse(element(app, "report.range").exists)
        XCTAssertFalse(field.exists)
        XCTAssertFalse(element(app, "today.logs").exists)
        XCTAssertEqual(app.tabBars.count, 1)
        XCTAssertTrue(app.tabBars.buttons["Inbox"].exists)
        XCTAssertFalse(app.segmentedControls["day.mode"].exists)
        XCTAssertFalse(app.staticTexts["Unestimated"].exists)
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
        app.buttons["Choose group"].tap(); app.buttons["Socializing"].tap()
        let undo = app.buttons["group.undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5)); undo.tap()
        XCTAssertTrue(app.staticTexts["Quokka activity fixture"].waitForExistence(timeout: 5))
        app.buttons["Choose group"].tap(); app.buttons["Socializing"].tap()
        app.buttons["Done"].tap()
        XCTAssertTrue(dashboardGroup("social", in: app).waitForExistence(timeout: 5))
    }

    func testDashboardCreatesAndRenamesANewGroup() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-grouping-ledger"]; app.launch()
        let review = app.buttons["dashboard.review.uncategorized"]; reveal(review, in: app); review.tap()
        app.buttons["Choose group"].tap(); app.buttons["Create new group…"].tap()
        let field = app.alerts.textFields["Group name"]
        XCTAssertTrue(field.waitForExistence(timeout: 5)); field.typeText("Creative Practice")
        app.alerts.buttons["Create & categorize"].tap()
        app.buttons["Done"].tap(); app.buttons["dashboard.groups"].tap()
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "groups.open.", "Creative Practice")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        let groupID = String(row.identifier.dropFirst("groups.open.".count)); row.tap()
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
        app.tabBars.buttons["Inbox"].tap()
        let field = element(app, "inbox.text")
        XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap(); field.typeText("Follow up with a client UI test")
        let save = app.buttons["inbox.save"]; reveal(save, in: app); save.tap()
        XCUIDevice.shared.press(.home); app.activate()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Inbox"].tap()
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
        app.tabBars.buttons["Inbox"].tap()
        XCTAssertTrue(app.staticTexts["One sentence Siri UI fixture"].waitForExistence(timeout: 5))
        app.terminate(); app.launchArguments = []; app.launch()
        app.tabBars.buttons["Inbox"].tap()
        XCTAssertTrue(app.staticTexts["One sentence Siri UI fixture"].waitForExistence(timeout: 5))
    }

    func testSiriRoutesIdeasAndActivitiesSeparatelyAndPersistsBoth() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-empty-ledger", "--ui-siri-routes"]; app.launch()
        app.tabBars.buttons["Inbox"].tap()
        XCTAssertTrue(app.staticTexts["Bicycle idea UI fixture"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Bicycle activity UI fixture"].exists)
        openLogs(app)
        XCTAssertTrue(app.staticTexts["Bicycle activity UI fixture"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Bicycle idea UI fixture"].exists)
        app.terminate(); app.launchArguments = []; app.launch()
        openLogs(app)
        XCTAssertTrue(app.staticTexts["Bicycle activity UI fixture"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Inbox"].tap()
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
        recordScreen("RemindersSetup", in: app)
        app.tabBars.buttons["Inbox"].tap()
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
        app.tabBars.buttons["Inbox"].tap()
        XCTAssertFalse(app.staticTexts["Reminders bicycle idea UI fixture"].exists)
        app.tabBars.buttons["Settings"].tap()
        let disconnect = app.buttons["reminders.disconnect"]; reveal(disconnect, in: app); disconnect.tap()
        XCTAssertFalse(importNow.exists)
    }

    func testCopyAllIdeasPastesFullInboxIncludingCompletedButNotDeleted() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-inbox-export-fixture"]; app.launch()
        app.tabBars.buttons["Inbox"].tap()
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

    func testPieSlicesAndLegendSelectLabelsInsideChart() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-grouping-ledger"]; app.launch()
        openHistory(app)
        app.buttons["Show pie chart"].tap()
        let chart = element(app, "report.pie.chart")
        XCTAssertTrue(chart.waitForExistence(timeout: 5))
        // The fixture is 75% Uncategorized, starting clockwise from twelve.
        chart.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).withOffset(CGVector(dx: 70, dy: 0)).tap()
        let selection = element(app, "report.pie.selection")
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "Uncategorized"), object: selection)
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 5), .completed)
        recordScreen("SelectedPieSlice", in: app)
        let work = app.buttons["report.pie.group.work"]; reveal(work, in: app); work.tap()
        XCTAssertTrue(selection.label.contains("Work"))
        XCTAssertTrue(selection.label.contains("%"))
        chart.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).withOffset(CGVector(dx: 70, dy: 0)).tap()
        XCTAssertTrue(selection.label.contains("Uncategorized"))
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
        app.tabBars.buttons["Inbox"].tap(); app.buttons["inbox.rank"].tap()
        XCTAssertTrue(app.buttons["ranking.second"].waitForExistence(timeout: 5))
        recordScreen("Ranking", in: app); app.buttons["ranking.second"].tap()
        app.buttons["Done"].tap(); app.terminate(); app.launchArguments = []; app.launch()
        app.tabBars.buttons["Inbox"].tap(); app.buttons["inbox.rank"].tap()
        XCTAssertTrue(app.buttons["ranking.first"].waitForExistence(timeout: 5)); app.buttons["ranking.first"].tap()
        app.buttons["ranking.second"].tap()
        XCTAssertTrue(app.staticTexts["All ideas ranked"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        let field = element(app, "inbox.text"); field.tap(); field.typeText("New idea")
        app.buttons["inbox.save"].tap()
        XCTAssertTrue(app.staticTexts["3 ranked · 1 waiting to rank"].waitForExistence(timeout: 5))
    }

    func testInboxDeletionHasUndoAndPersistsAfterRelaunch() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-inbox-fixture"]; app.launch()
        app.tabBars.buttons["Inbox"].tap()
        recordScreen("Inbox", in: app)
        let menu = app.buttons["inbox.actions.a"]; reveal(menu, in: app); menu.tap()
        app.buttons["Delete idea"].tap()
        XCTAssertFalse(app.staticTexts["First idea"].exists)
        app.buttons["inbox.undo-delete"].tap()
        XCTAssertTrue(app.staticTexts["First idea"].waitForExistence(timeout: 5))
        let restored = app.buttons["inbox.actions.a"]; reveal(restored, in: app); restored.tap()
        app.buttons["Delete idea"].tap()
        app.terminate(); app.launchArguments = []; app.launch(); app.tabBars.buttons["Inbox"].tap()
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

    func testRankingCanDeleteEitherIdeaUndoAndContinue() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-inbox-fixture"]; app.launch()
        app.tabBars.buttons["Inbox"].tap(); app.buttons["inbox.rank"].tap()
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
        app.buttons["ranking.first"].tap()
        XCTAssertTrue(app.staticTexts["All ideas ranked"].waitForExistence(timeout: 5))
        recordScreen("RankingCleanup", in: app)
    }

    func testInboxKeyboardDismissesOutsideAndPreservesDraftAcrossTabs() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-empty-ledger"]; app.launch()
        app.tabBars.buttons["Inbox"].tap()
        let field = element(app, "inbox.text"); field.tap(); field.typeText("Keep my draft")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        app.navigationBars["Inbox"].tap()
        let hidden = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.keyboards.firstMatch)
        XCTAssertEqual(XCTWaiter.wait(for: [hidden], timeout: 5), .completed)
        XCTAssertEqual(field.value as? String, "Keep my draft")
        app.tabBars.buttons["Today"].tap(); app.tabBars.buttons["Inbox"].tap()
        XCTAssertEqual(field.value as? String, "Keep my draft")
        field.tap()
        let done = app.buttons["keyboard.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5)); done.tap()
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        app.buttons["inbox.save"].tap()
        XCTAssertTrue(app.staticTexts["Keep my draft"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.keyboards.firstMatch.exists)
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

    func testWakingScheduleAndTargetsAreAccessibleAndPersist() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-allocation-fixture"]; app.launch()
        XCTAssertTrue(element(app, "dashboard.breakdown-title").waitForExistence(timeout: 10))
        XCTAssertTrue(dashboardGroup("work", in: app).exists)
        XCTAssertTrue(dashboardGroup("music", in: app).exists)
        XCTAssertFalse(element(app, "allocation.periods").exists)
        recordScreen("TodayRestored", in: app)
        app.tabBars.buttons["Commitments"].tap()
        app.buttons["commitments.more"].tap()
        app.buttons["Percentage targets"].tap()
        XCTAssertTrue(element(app, "allocation.periods").waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Rolling 7 days"].exists)
        recordScreen("AllocationDashboard", in: app)
        app.navigationBars.buttons["Commitments"].tap()
        app.tabBars.buttons["Today"].tap()
        XCTAssertTrue(element(app, "dashboard.breakdown-title").waitForExistence(timeout: 5))
        XCTAssertFalse(element(app, "allocation.periods").exists)
        app.buttons["dashboard.groups"].tap()
        let work = app.textFields["categories.target.work"]; reveal(work, in: app); work.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        work.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 8)); work.typeText("90")
        XCTAssertEqual(work.value as? String, "90")
        let save = app.buttons["categories.save-targets"]; reveal(save, in: app)
        XCTAssertFalse(save.isEnabled)
        XCTAssertTrue(app.staticTexts["Over-allocated"].exists)
        reveal(work, in: app); work.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap(); work.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 8)); work.typeText("35")
        XCTAssertEqual(work.value as? String, "35")
        reveal(save, in: app); XCTAssertTrue(save.isEnabled); save.tap()
        recordScreen("AllocationCategories", in: app)
        app.terminate(); app.launchArguments = []; app.launch(); app.buttons["dashboard.groups"].tap()
        reveal(work, in: app); XCTAssertEqual(work.value as? String, "35")
        let music = app.textFields["categories.target.music"]; reveal(music, in: app); XCTAssertEqual(music.value as? String, "15")
    }

    func testMultiCategorySelectionResolvesParentConflictExplicitly() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-allocation-fixture"]; app.launch()
        app.tabBars.buttons["Log"].tap()
        let field = element(app, "checkin.activity"); field.tap(); field.typeText("Two activities")
        let selector = element(app, "checkin.category"); reveal(selector, in: app); selector.tap()
        app.buttons["category-select.work"].tap()
        app.buttons["category-select.teaching"].tap()
        XCTAssertTrue(app.alerts["Replace conflicting categories?"].waitForExistence(timeout: 5))
        app.alerts.buttons["Replace"].tap(); app.buttons["category-select.music"].tap()
        recordScreen("MultipleCategories", in: app)
        app.buttons["Done"].tap()
        let save = app.buttons["checkin.save"]; reveal(save, in: app); save.tap()
        XCTAssertTrue(app.staticTexts["Saved. You can change it anytime."].waitForExistence(timeout: 5))
    }

    func testWeeklyCommitmentsCanBeCreatedEditedRemovedAndPersistWithoutDeletingLogs() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-allocation-fixture"]; app.launch()
        app.tabBars.buttons["Commitments"].tap()
        XCTAssertTrue(app.staticTexts["Make time for what matters"].waitForExistence(timeout: 5))
        app.buttons["commitments.add"].tap()
        element(app, "commitment.category").tap(); app.buttons["Work"].tap()
        setCommitmentNumber("commitment.hours", to: "0", in: app)
        setCommitmentNumber("commitment.minutes", to: "0", in: app)
        XCTAssertFalse(app.buttons["commitment.save"].isEnabled)
        setCommitmentNumber("commitment.minutes", to: "30", in: app)
        app.buttons["commitment.save"].tap()
        let work = app.buttons["commitments.edit.work"]
        XCTAssertTrue(work.waitForExistence(timeout: 5)); XCTAssertTrue(work.label.contains("of 30m this week"))
        work.tap()
        setCommitmentNumber("commitment.hours", to: "1", in: app)
        setCommitmentNumber("commitment.minutes", to: "0", in: app)
        recordScreen("WeeklyCommitmentEditor", in: app)
        app.buttons["commitment.save"].tap()
        XCTAssertTrue(work.waitForExistence(timeout: 5)); XCTAssertTrue(work.label.contains("of 1h 0m this week"))
        app.terminate(); app.launchArguments = []; app.launch()
        XCTAssertTrue(element(app, "dashboard.breakdown-title").waitForExistence(timeout: 5))
        app.tabBars.buttons["Commitments"].tap()
        XCTAssertTrue(work.waitForExistence(timeout: 5)); XCTAssertTrue(work.label.contains("of 1h 0m this week"))
        work.tap(); app.buttons["commitment.remove"].tap()
        app.sheets.buttons["Remove commitment"].tap()
        XCTAssertTrue(app.staticTexts["Make time for what matters"].waitForExistence(timeout: 5))
        app.terminate(); app.launchArguments = []; app.launch(); app.tabBars.buttons["Commitments"].tap()
        XCTAssertFalse(work.exists)
        openLogs(app)
        XCTAssertTrue(app.staticTexts["Preparing classes"].waitForExistence(timeout: 5))
    }

    func testWeeklyCommitmentsUseCategoryLogsAndHaveADirectBottomTab() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-commitments-fixture"]; app.launch()
        XCTAssertTrue(element(app, "dashboard.breakdown-title").waitForExistence(timeout: 5))
        XCTAssertFalse(element(app, "allocation.periods").exists)
        app.tabBars.buttons["Commitments"].tap()
        let work = app.buttons["commitments.edit.work"], music = app.buttons["commitments.edit.music"]
        XCTAssertTrue(work.waitForExistence(timeout: 5)); XCTAssertTrue(music.exists)
        XCTAssertTrue(work.label.contains("of 1h 0m this week"))
        XCTAssertTrue(music.label.contains("of 10h 0m this week"))
        XCTAssertFalse(element(app, "allocation.periods").exists)
        recordScreen("WeeklyCommitments", in: app)
        app.tabBars.buttons["Today"].tap()
        XCTAssertTrue(element(app, "dashboard.breakdown-title").exists)
    }

    private func setCommitmentNumber(_ id: String, to value: String, in app: XCUIApplication) {
        let field = app.textFields[id]
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 8)); field.typeText(value)
        XCTAssertEqual(field.value as? String, value)
        app.buttons["keyboard.done"].tap()
    }

    private func openHistory(_ app: XCUIApplication) {
        let history = app.buttons["dashboard.history"]; reveal(history, in: app); history.tap()
    }
}
