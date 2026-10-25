import XCTest
@testable import LedgerCore

final class FocusTasksTests: XCTestCase {
    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    private var start: Date { date("2026-10-19T07:00:00Z") }
    private var deadline: Date { date("2026-10-22T22:00:00Z") }
    private var now: Date { date("2026-10-20T22:00:00Z") }
    private func task(_ ledger: inout Ledger, id: String = "prep", categories: [String] = ["work"]) throws -> Capture {
        ledger.settings.reportingTimeZoneIdentifier = "UTC"
        try ledger.addCapture(text: "Lecture prep", id: id, writer: "p", now: start)
        try ledger.categorizeCapture(id: id, categoryIDs: categories, writer: "p")
        try ledger.setCaptureTiming(id, timing: .due(deadline), writer: "p")
        try ledger.setTaskPlan(id, estimatedMinutes: 240, startDate: nil, writer: "p")
        return ledger.captures.first { $0.id == id }!
    }
    private func log(_ ledger: inout Ledger, taskID: String?, categories: [String] = ["work"]) throws {
        let event = CalendarEventSnapshot(id: "prep", calendarID: "c", calendarName: "Classes", title: "Prep", start: date("2026-10-19T08:00:00Z"), end: date("2026-10-19T09:00:00Z"))
        ledger.collectCalendarEvents([event], writer: "p", now: now)
        try ledger.decideCalendarEvent(event.id, confirm: true, categoryIDs: categories, writer: "p", now: now)
        try ledger.assignTask(taskID, to: "calendar-prep", writer: "p")
    }
    func testFocusNeedsDueDateAndEstimateButStartDefaultsToCreation() throws {
        var ledger = Ledger(); let capture = try task(&ledger)
        XCTAssertNil(capture.workPlan?.startDate)
        XCTAssertEqual(ledger.focusTasks(now: now).map(\.id), [capture.id])
        let progress = try XCTUnwrap(ledger.focusTaskProgress(now: now).first)
        XCTAssertEqual(progress.goal.startDate, start)
        XCTAssertEqual(progress.expectedMinutes, 120, accuracy: 0.001)
        try ledger.setCaptureTiming(capture.id, timing: .asap, writer: "p")
        XCTAssertTrue(ledger.focusTasks(now: now).isEmpty)
        try ledger.setCaptureTiming(capture.id, timing: .due(deadline), writer: "p")
        try ledger.setTaskPlan(capture.id, estimatedMinutes: nil, startDate: nil, writer: "p")
        XCTAssertTrue(ledger.focusTasks(now: now).isEmpty)
    }
    func testClosedReferenceSnoozedAndDeletedTasksLeaveFocusWithoutLosingPlans() throws {
        var ledger = Ledger(); _ = try task(&ledger)
        ledger.captures[0].isDone = true; XCTAssertTrue(ledger.focusTasks(now: now).isEmpty)
        ledger.captures[0].isDone = false; ledger.captures[0].isReference = true
        XCTAssertTrue(ledger.focusTasks(now: now).isEmpty)
        ledger.captures[0].isReference = false; ledger.captures[0].snoozedUntil = deadline
        XCTAssertTrue(ledger.focusTasks(now: now).isEmpty)
        ledger.captures[0].snoozedUntil = nil; ledger.captures[0].deletedAt = now
        XCTAssertTrue(ledger.focusTasks(now: now).isEmpty)
        XCTAssertNotNil(ledger.captures[0].workPlan)
    }
    func testAnyInboxItemCanReceiveLoggedTimeWithoutAPlan() throws {
        var ledger = Ledger()
        try ledger.addCapture(text: "Ordinary idea", id: "plain", writer: "p", now: start)
        try log(&ledger, taskID: "plain")
        XCTAssertEqual(ledger.taskLoggedMinutes(now: now)["plain"], 60)
        XCTAssertTrue(ledger.focusTasks(now: now).isEmpty)
        XCTAssertEqual(ledger.entries[0].goalID, "plain")
    }
    func testTaskTimeCountsInItsCategoryOnceAndSplitsWithOtherCategories() throws {
        var ledger = Ledger(); _ = try task(&ledger)
        try log(&ledger, taskID: "prep", categories: ["work", "social"])
        XCTAssertEqual(ledger.taskLoggedMinutes(now: now)["prep"], 30)
        let report = ledger.allocation(on: start, now: now)
        XCTAssertEqual(report.trackedMinutes, 60)
        XCTAssertEqual(report.total(for: "work", ledger: ledger), 30)
        try ledger.confirmCategories(for: "calendar-prep", categoryIDs: ["work"], writer: "p")
        XCTAssertEqual(ledger.taskLoggedMinutes(now: now)["prep"], 60)
    }
    func testAssignmentAddsTaskCategoryAndKeepsAnExistingDescendant() throws {
        var ledger = Ledger(); _ = try task(&ledger)
        try ledger.saveCategory(id: nil, name: "Teaching", writer: "p")
        let child = ledger.categories.last!.id
        try ledger.moveCategory(child, to: "work", writer: "p")
        try log(&ledger, taskID: "prep", categories: [child])
        XCTAssertEqual(ledger.entries[0].categoryIDs, [child])
        XCTAssertEqual(ledger.focusTaskProgress(now: now).first?.actualMinutes, 60)
    }
    func testMigrationPreservesIDsLinkedCreditAndIsIdempotent() throws {
        var ledger = Ledger(); ledger.settings.reportingTimeZoneIdentifier = "UTC"
        let id = try ledger.saveDatedGoal(name: "Old lecture goal", categoryID: "work", targetMinutes: 240, startDate: start, deadline: deadline, writer: "p")
        let event = CalendarEventSnapshot(id: "old", calendarID: "c", calendarName: "C", title: "Prep", start: start, end: start.addingTimeInterval(3600))
        ledger.collectCalendarEvents([event], writer: "p", now: now)
        try ledger.decideCalendarEvent(event.id, confirm: true, goalID: id, writer: "p", now: now)
        let entries = ledger.entries
        ledger.migrateGoalsToTasks(writer: "p")
        XCTAssertEqual(ledger.captures.map(\.id), [id])
        XCTAssertEqual(ledger.captures[0].workPlan?.estimatedMinutes, 240)
        XCTAssertEqual(ledger.entries, entries)
        XCTAssertTrue(ledger.activeDatedGoals.isEmpty)
        XCTAssertEqual(ledger.focusTaskProgress(now: now).first?.actualMinutes, 60)
        let once = ledger; ledger.migrateGoalsToTasks(writer: "p"); XCTAssertEqual(ledger, once)
    }
    func testIndependentDeviceMigrationMergeAndBackupNeverDuplicateTasks() throws {
        var phone = Ledger()
        _ = try phone.saveDatedGoal(name: "Legacy", categoryID: nil, targetMinutes: 60, startDate: start, deadline: deadline, writer: "p")
        var watch = phone
        phone.migrateGoalsToTasks(writer: "p"); watch.migrateGoalsToTasks(writer: "w")
        phone.merge(watch); watch.merge(phone)
        XCTAssertEqual(phone, watch); XCTAssertEqual(phone.captures.count, 1)
        let restored = try LedgerBackup.decode(LedgerBackup(ledger: phone).encoded()).ledger
        XCTAssertEqual(phone, restored)
        XCTAssertEqual(restored.focusTasks(now: now).count, 1)
        var delivery = CompanionQuickDelivery()
        let packet = try JSONDecoder().decode(CompanionQuickPacket.self, from: XCTUnwrap(delivery.prepare(restored, id: "p")))
        XCTAssertEqual(packet.ledger.captures.first?.workPlan, restored.captures.first?.workPlan)
    }
    func testCloudTombstoneBeforeCaptureCannotDeleteMigratedTask() throws {
        var phone = Ledger()
        let id = try phone.saveDatedGoal(name: "Legacy", categoryID: nil, targetMinutes: 60, startDate: start, deadline: deadline, writer: "p")
        try phone.saveSample(id: "sample", at: start, activity: "Prep", categoryID: nil, writer: "p", now: now)
        try phone.assignGoal(id, to: "sample", writer: "p")
        phone.migrateGoalsToTasks(writer: "p")
        var watch = Ledger(); watch.entries = phone.entries
        var goalPacket = Ledger(); goalPacket.datedGoals = phone.datedGoals
        watch.merge(goalPacket); watch.migrateGoalsToTasks(writer: "w")
        XCTAssertTrue(watch.captures.isEmpty)
        var taskPacket = Ledger(); taskPacket.captures = phone.captures
        watch.merge(taskPacket); watch.migrateGoalsToTasks(writer: "w")
        XCTAssertNil(watch.captures[0].deletedAt)
        XCTAssertEqual(watch.focusTasks(now: now).map(\.id), [id])
    }
    func testEditedTaskKeepsLogLinkAndArchivedTaskRetainsCredit() throws {
        var ledger = Ledger(); _ = try task(&ledger); try log(&ledger, taskID: "prep")
        try ledger.updateCaptureText(id: "prep", text: "Revised lecture", writer: "p")
        XCTAssertEqual(ledger.focusTaskProgress(now: now).first?.goal.name, "Revised lecture")
        ledger.captures[0].deletedAt = now
        XCTAssertNoThrow(try ledger.assignTask("prep", to: "calendar-prep", writer: "p"))
        XCTAssertEqual(ledger.taskLoggedMinutes(now: now)["prep"], 60)
    }
    func testFutureStartPaceAndFrozenWindowDoNotFilterActualTime() throws {
        var ledger = Ledger(); _ = try task(&ledger); try log(&ledger, taskID: "prep")
        try ledger.setTaskPlan("prep", estimatedMinutes: 240, startDate: date("2026-10-21T07:00:00Z"), writer: "p")
        let before = ledger.focusTaskProgress(now: now)[0]
        XCTAssertEqual(before.actualMinutes, 60); XCTAssertEqual(before.expectedMinutes, 0)
        ledger.settings.startMinute = 600; ledger.settings.endMinute = 660
        XCTAssertEqual(ledger.focusTaskProgress(now: now)[0], before)
    }
    func testInvalidEstimateAndLegacyNoPlanDecode() throws {
        var ledger = Ledger(); _ = try task(&ledger)
        for bad in [0.0, -1, .infinity, .nan] {
            XCTAssertThrowsError(try ledger.setTaskPlan("prep", estimatedMinutes: bad, startDate: nil, writer: "p"))
        }
        var old = Ledger(); try old.addCapture(text: "Keep", writer: "w", now: start)
        let restored = try LedgerBackup.decode(LedgerBackup(ledger: old).encoded()).ledger
        XCTAssertNil(restored.captures[0].workPlan); XCTAssertEqual(old, restored)
    }
    func testOptionalStartCanBeSavedBeforeAnEstimateWithoutEnteringFocus() throws {
        var ledger = Ledger(); _ = try task(&ledger)
        let workStart = start.addingTimeInterval(86400)
        try ledger.setTaskPlan("prep", estimatedMinutes: nil, startDate: workStart, writer: "p")
        XCTAssertEqual(ledger.captures[0].workPlan?.startDate, workStart)
        XCTAssertNil(ledger.captures[0].workPlan?.estimatedMinutes)
        XCTAssertTrue(ledger.focusTasks(now: now).isEmpty)
        let restored = try LedgerBackup.decode(LedgerBackup(ledger: ledger).encoded()).ledger
        XCTAssertEqual(restored.captures[0].workPlan?.startDate, workStart)
    }
    func testReviewAfterMovingTaskKeepsHistoricalCategoriesAndCredit() throws {
        var ledger = Ledger(); _ = try task(&ledger); try log(&ledger, taskID: "prep")
        try ledger.categorizeCapture(id: "prep", categoryIDs: ["social"], writer: "p")
        let before = ledger.entries[0]
        try ledger.assignTask("prep", to: before.id, writer: "p")
        XCTAssertEqual(ledger.entries[0], before)
        XCTAssertEqual(ledger.taskLoggedMinutes(now: now)["prep"], 60)
        try ledger.confirmCategories(for: before.id, categoryIDs: ["work", "social"], writer: "p")
        try ledger.assignTask("prep", to: before.id, writer: "p")
        XCTAssertEqual(ledger.taskLoggedMinutes(now: now)["prep"], 30)
    }
    func testAnOverdueDateBeforeCreationStillAppearsAndIsBehindPace() throws {
        var ledger = Ledger(); _ = try task(&ledger)
        try ledger.setCaptureTiming("prep", timing: .due(start.addingTimeInterval(-3600)), writer: "p")
        let row = try XCTUnwrap(ledger.focusTaskProgress(now: now).first)
        XCTAssertEqual(row.expectedMinutes, 240)
        XCTAssertEqual(row.differenceMinutes, -240)
        XCTAssertTrue(ledger.inboxExport.text.contains("Focus: Yes"))
        XCTAssertTrue(ledger.inboxExport.text.contains("Work estimate: 240"))
    }
}
