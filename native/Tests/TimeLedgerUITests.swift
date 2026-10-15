import XCTest

final class TimeLedgerUITests: XCTestCase {
    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func reveal(_ target: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<6 {
            if target.exists && target.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(target.waitForExistence(timeout: 5))
        XCTAssertTrue(target.isHittable)
    }

    private func log(_ text: String, in app: XCUIApplication, confirmSuggestion: Bool = false) {
        let field = element(app, "checkin.activity")
        reveal(field, in: app); field.tap(); field.typeText(text)
        if confirmSuggestion {
            let use = app.buttons["checkin.confirm-suggestion"]
            reveal(use, in: app); use.tap()
        }
        let save = app.buttons["checkin.save"]
        reveal(save, in: app); save.tap()
        XCTAssertTrue(app.staticTexts["Saved. You can change it anytime."].waitForExistence(timeout: 5))
    }

    private func openLogs(_ app: XCUIApplication) {
        let logs = element(app, "today.logs"); reveal(logs, in: app); logs.tap()
    }

    func testHomePutsBreakdownBeforeLoggingAndProvidesInboxTab() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-grouping-ledger"]; app.launch()
        let header = element(app, "dashboard.breakdown-title")
        let field = element(app, "checkin.activity")
        XCTAssertTrue(header.waitForExistence(timeout: 10))
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertLessThan(header.frame.minY, field.frame.minY)
        XCTAssertEqual(app.tabBars.count, 1)
        XCTAssertTrue(app.tabBars.buttons["Inbox"].exists)
        XCTAssertFalse(app.segmentedControls["day.mode"].exists)
        XCTAssertFalse(app.staticTexts["Unestimated"].exists)
    }

    func testUnconfirmedSuggestionStaysUncategorizedUntilAcceptedInReview() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-empty-ledger"]; app.launch()
        log("Working on app", in: app)
        XCTAssertFalse(app.buttons["dashboard.group.work"].exists)
        let review = app.buttons["dashboard.review.uncategorized"]; reveal(review, in: app); review.tap()
        XCTAssertTrue(app.staticTexts["Suggested: Work"].waitForExistence(timeout: 5))
        let confirm = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "group.confirm.")).firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5)); confirm.tap()
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["dashboard.group.work"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["dashboard.review.uncategorized"].exists)
    }

    func testNewLogCanExplicitlyConfirmTheDisplayedSuggestion() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-empty-ledger"]; app.launch()
        log("Preparing classes", in: app, confirmSuggestion: true)
        XCTAssertTrue(app.buttons["dashboard.group.work"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["dashboard.review.uncategorized"].exists)
    }

    func testDashboardCategorizesAnUnknownActivityAndSupportsUndo() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-grouping-ledger"]; app.launch()
        app.buttons["dashboard.review.uncategorized"].tap()
        XCTAssertTrue(app.staticTexts["Quokka activity fixture"].waitForExistence(timeout: 5))
        app.buttons["Choose group"].tap(); app.buttons["Socializing"].tap()
        let undo = app.buttons["group.undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5)); undo.tap()
        XCTAssertTrue(app.staticTexts["Quokka activity fixture"].waitForExistence(timeout: 5))
        app.buttons["Choose group"].tap(); app.buttons["Socializing"].tap()
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["dashboard.group.social"].waitForExistence(timeout: 5))
    }

    func testDashboardCreatesAndRenamesANewGroup() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-grouping-ledger"]; app.launch()
        app.buttons["dashboard.review.uncategorized"].tap()
        app.buttons["Choose group"].tap(); app.buttons["Create new group…"].tap()
        let field = app.alerts.textFields["Group name"]
        XCTAssertTrue(field.waitForExistence(timeout: 5)); field.typeText("Creative Practice")
        app.alerts.buttons["Create & categorize"].tap()
        app.buttons["Done"].tap(); app.buttons["dashboard.groups"].tap()
        app.swipeUp()
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "groups.rename.", "Creative Practice")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        let groupID = String(row.identifier.dropFirst("groups.rename.".count)); row.tap()
        let rename = app.alerts.textFields["Group name"]
        XCTAssertTrue(rename.waitForExistence(timeout: 5))
        rename.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        rename.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 30))
        rename.typeText("Creative Projects")
        app.alerts.buttons["Save"].tap()
        XCTAssertTrue(app.buttons["groups.rename.\(groupID)"].staticTexts["Creative Projects"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["dashboard.group.\(groupID)"].waitForExistence(timeout: 5))
    }

    func testCalendarOpensOnASeparateScreen() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-grouping-ledger"]; app.launch()
        app.buttons["dashboard.calendar"].tap()
        XCTAssertTrue(app.scrollViews["timeline.grid"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Noon"].exists)
    }

    func testExistingConfirmedLogSurvivesUpgradeAndCanBeEdited() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-legacy-ledger"]; app.launch()
        XCTAssertTrue(app.buttons["dashboard.group.work"].waitForExistence(timeout: 10))
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
        XCTAssertTrue(app.buttons["dashboard.review.uncategorized"].exists)
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

    func testStartupHelperFailureDoesNotBlockLocalLoggingOrLoseItAfterRelaunch() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-empty-ledger", "--ui-companion-unavailable"]
        app.launch()
        XCTAssertTrue(element(app, "checkin.activity").waitForExistence(timeout: 10))
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
        let period = element(app, "report.range")
        XCTAssertTrue(period.waitForExistence(timeout: 10)); period.tap(); app.buttons["Past 7 days"].tap()
        XCTAssertTrue(app.navigationBars["Your time"].waitForExistence(timeout: 5))
        let pages = element(app, "report.pages"); pages.swipeLeft()
        XCTAssertTrue(app.staticTexts["Pie chart"].waitForExistence(timeout: 5))
        pages.swipeLeft()
        XCTAssertTrue(app.staticTexts["Daily trend"].waitForExistence(timeout: 5))
        period.tap(); app.buttons["All time"].tap()
        XCTAssertTrue(app.staticTexts["Daily trend"].exists)
        period.tap(); app.buttons["Custom"].tap()
        XCTAssertTrue(element(app, "report.from").waitForExistence(timeout: 5))
        XCTAssertTrue(element(app, "report.through").exists)
    }

    func testInboxRankingResumesAfterRelaunchAndNewIdeasWaitToBeRanked() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-inbox-fixture"]; app.launch()
        app.tabBars.buttons["Inbox"].tap(); app.buttons["inbox.rank"].tap()
        XCTAssertTrue(app.buttons["ranking.second"].waitForExistence(timeout: 5)); app.buttons["ranking.second"].tap()
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
        app.buttons["backup.confirm-restore"].tap()
        XCTAssertTrue(app.staticTexts["Restored. Your newer edits and existing logs were kept."].waitForExistence(timeout: 5))
        app.tabBars.buttons["Today"].tap()
        element(app, "report.range").tap(); app.buttons["Past 7 days"].tap()
        openLogs(app)
        XCTAssertTrue(app.staticTexts["Restored older activity"].waitForExistence(timeout: 5))
    }

    func testRemainingTimePreferenceSurvivesRelaunch() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-empty-ledger"]; app.launch()
        app.tabBars.buttons["Settings"].tap()
        let toggle = app.switches["settings.remaining"]; reveal(toggle, in: app); toggle.tap()
        XCTAssertEqual(toggle.value as? String, "1")
        app.terminate(); app.launchArguments = []; app.launch(); app.tabBars.buttons["Settings"].tap()
        let restored = app.switches["settings.remaining"]; reveal(restored, in: app)
        XCTAssertEqual(restored.value as? String, "1")
    }
}
