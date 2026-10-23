import XCTest
@testable import LedgerCore

final class DatedGoalsTests: XCTestCase {
    private func date(_ s: String) -> Date { ISO8601DateFormatter().date(from: s)! }
    private var utc: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 0)!; return c }
    private func goal(_ ledger: inout Ledger, name: String = "DIGS", category: String? = "work", start: String = "2026-10-19T07:00:00Z", end: String = "2026-10-22T22:00:00Z") throws -> String {
        ledger.settings.reportingTimeZoneIdentifier = "UTC"
        return try ledger.saveDatedGoal(name: name, categoryID: category, targetMinutes: 240, startDate: date(start), deadline: date(end), writer: "phone")
    }
    private func period(_ ledger: inout Ledger, id: String, start: String, end: String, goalID: String?, categories: [String] = []) throws {
        let snapshot = CalendarEventSnapshot(id: id, calendarID: "c", calendarName: "Classes", title: "Prep", start: date(start), end: date(end))
        ledger.collectCalendarEvents([snapshot], writer: "phone", now: date("2026-11-01T12:00:00Z"))
        try ledger.decideCalendarEvent(id, confirm: true, categoryIDs: categories, goalID: goalID, writer: "phone", now: date("2026-11-01T12:00:00Z"))
    }
    func testSeparateGoalsCreditOnlyAssignedWorkAndParentTotals() throws {
        var ledger = Ledger()
        let digs = try goal(&ledger), sdes = try goal(&ledger, name: "SDES")
        try ledger.saveCategory(id: nil, name: "Teaching", writer: "phone")
        let child = ledger.categories.last!.id
        try ledger.moveCategory(child, to: "work", writer: "phone")
        try period(&ledger, id: "d", start: "2026-10-19T08:00:00Z", end: "2026-10-19T09:00:00Z", goalID: digs, categories: [child])
        let now = date("2026-10-19T12:00:00Z"), rows = ledger.datedGoalProgress(now: now, calendar: utc)
        XCTAssertEqual(rows.first { $0.id == digs }?.actualMinutes, 60)
        XCTAssertEqual(rows.first { $0.id == sdes }?.actualMinutes, 0)
        XCTAssertEqual(ledger.entries.first?.categoryIDs, [child])
        let totals = ledger.allocation(on: now, now: now, calendar: utc)
        XCTAssertEqual(totals.trackedMinutes, 60)
        XCTAssertEqual(totals.total(for: "work", ledger: ledger), 60)
    }
    func testFixedPaceAndDynamicCatchupAheadAndBehind() throws {
        var ledger = Ledger(); let id = try goal(&ledger)
        try period(&ledger, id: "p", start: "2026-10-19T08:00:00Z", end: "2026-10-19T11:00:00Z", goalID: id)
        let now = date("2026-10-20T22:00:00Z")
        var row = try XCTUnwrap(ledger.datedGoalProgress(now: now, calendar: utc).first)
        XCTAssertEqual(row.expectedMinutes, 120, accuracy: 0.001)
        XCTAssertEqual(row.actualMinutes, 180)
        XCTAssertEqual(row.differenceMinutes, 60)
        XCTAssertEqual(row.dailyMinutesNeeded!, 30, accuracy: 0.001)
        ledger.setLogDeleted("calendar-p", deleted: true, writer: "phone")
        row = try XCTUnwrap(ledger.datedGoalProgress(now: now, calendar: utc).first)
        XCTAssertEqual(row.expectedMinutes, 120)
        XCTAssertEqual(row.differenceMinutes, -120)
        XCTAssertEqual(row.dailyMinutesNeeded!, 120, accuracy: 0.001)
    }
    func testMultiCategoryGoalUsesItsShareNotTheFullDuration() throws {
        var ledger = Ledger(); let id = try goal(&ledger)
        try period(&ledger, id: "p", start: "2026-10-19T08:00:00Z", end: "2026-10-19T09:00:00Z", goalID: id, categories: ["work", "social"])
        let now = date("2026-10-20T12:00:00Z")
        XCTAssertEqual(ledger.datedGoalProgress(now: now, calendar: utc).first?.actualMinutes, 30)
        XCTAssertEqual(ledger.allocation(on: date("2026-10-19T12:00:00Z"), now: now, calendar: utc).trackedMinutes, 60)
    }
    func testWeekendWorkCountsAndFrozenWindowSurvivesSettingsChanges() throws {
        var ledger = Ledger(); let id = try goal(&ledger, start: "2026-10-23T07:00:00Z", end: "2026-10-26T22:00:00Z")
        try period(&ledger, id: "p", start: "2026-10-24T02:00:00Z", end: "2026-10-24T03:00:00Z", goalID: id)
        let now = date("2026-10-25T12:00:00Z")
        let before = ledger.datedGoalProgress(now: now, calendar: utc).first!
        XCTAssertEqual(before.actualMinutes, 60)
        XCTAssertEqual(before.expectedMinutes, 120)
        XCTAssertEqual(before.remainingWorkdays, 1)
        ledger.settings.startMinute = 600; ledger.settings.endMinute = 660
        ledger.settings.reportingTimeZoneIdentifier = "Europe/Berlin"
        let after = ledger.datedGoalProgress(now: now, calendar: utc).first!
        XCTAssertEqual(after.expectedMinutes, before.expectedMinutes)
        XCTAssertEqual(after.remainingWorkdays, before.remainingWorkdays)
        XCTAssertEqual(after.actualMinutes, 60)
    }
    func testDeadlineTimePartialDaysAndZeroWorkdaysAreFinite() throws {
        var ledger = Ledger(); let id = try goal(&ledger, start: "2026-10-23T07:00:00Z", end: "2026-10-26T07:00:00Z")
        let row = ledger.datedGoalProgress(now: date("2026-10-23T14:30:00Z"), calendar: utc).first!
        XCTAssertEqual(row.expectedMinutes, 120)
        XCTAssertEqual(row.remainingWorkdays, 1)
        XCTAssertEqual(row.dailyMinutesNeeded, 240)
        let weekend = try goal(&ledger, name: "Song", category: nil, start: "2026-10-24T07:00:00Z", end: "2026-10-25T22:00:00Z")
        let rows = ledger.datedGoalProgress(now: date("2026-10-25T12:00:00Z"), calendar: utc)
        XCTAssertNil(rows.first { $0.id == id }?.dailyMinutesNeeded)
        XCTAssertNil(rows.first { $0.id == weekend }?.dailyMinutesNeeded)
        XCTAssertTrue(rows.allSatisfy { $0.expectedMinutes.isFinite })
    }
    func testGoalAssignmentPreservedBySampleEditsBackupAndOfflineMerge() throws {
        var phone = Ledger(); let id = try goal(&phone, category: nil)
        let now = date("2026-10-20T12:00:00Z")
        try phone.saveSample(id: "s", at: now, activity: "Practice", categoryID: nil, writer: "watch", now: now)
        try phone.assignGoal(id, to: "s", writer: "phone")
        try phone.saveSample(id: "s", at: now, activity: "Practice guitar", categoryID: "leisure", writer: "phone", now: now)
        XCTAssertEqual(phone.entries.first?.goalID, id)
        var watch = try LedgerBackup.decode(LedgerBackup(ledger: phone).encoded()).ledger
        try watch.addCapture(text: "Unrelated idea", writer: "watch", now: now)
        phone.deleteDatedGoal(id, writer: "phone")
        watch.merge(phone); phone.merge(watch)
        XCTAssertEqual(phone, watch)
        XCTAssertTrue(phone.activeDatedGoals.isEmpty)
        XCTAssertEqual(phone.entries.first?.goalID, id)
        XCTAssertEqual(phone.captures.count, 1)
    }
    func testLegacyJSONAndValidationPreserveData() throws {
        var ledger = Ledger()
        try ledger.addCapture(text: "Keep me", writer: "phone")
        let decoded = try JSONDecoder().decode(Ledger.self, from: JSONEncoder().encode(ledger))
        XCTAssertNil(decoded.datedGoals); XCTAssertNil(decoded.calendarEvents)
        XCTAssertEqual(decoded, ledger)
        XCTAssertThrowsError(try ledger.saveDatedGoal(name: "", categoryID: nil, targetMinutes: 240, startDate: Date(), deadline: Date().addingTimeInterval(100), writer: "p"))
        XCTAssertThrowsError(try ledger.saveDatedGoal(name: "Bad", categoryID: "missing", targetMinutes: 240, startDate: Date(), deadline: Date().addingTimeInterval(100), writer: "p"))
        XCTAssertTrue(ledger.activeDatedGoals.isEmpty)
    }
    func testDeletingCategoryKeepsGoalAndRawTime() throws {
        var ledger = Ledger(); let id = try goal(&ledger)
        try period(&ledger, id: "p", start: "2026-10-19T08:00:00Z", end: "2026-10-19T09:00:00Z", goalID: id)
        try ledger.deleteCategory(id: "work", writer: "phone")
        let now = date("2026-10-20T12:00:00Z")
        XCTAssertEqual(ledger.datedGoalProgress(now: now, calendar: utc).first?.actualMinutes, 60)
        XCTAssertEqual(ledger.allocation(on: date("2026-10-19T12:00:00Z"), now: now, calendar: utc).directMinutes["uncategorized"], 60)
    }
    func testMovingGoalKeepsPastCreditAndRecategorizingUpdatesItsShare() throws {
        var ledger = Ledger(); let id = try goal(&ledger)
        try period(&ledger, id: "p", start: "2026-10-19T08:00:00Z", end: "2026-10-19T09:00:00Z", goalID: id)
        let now = date("2026-10-20T12:00:00Z")
        let original = ledger.datedGoals!.first!
        try ledger.saveDatedGoal(id: id, name: original.name, categoryID: "social", targetMinutes: original.targetMinutes,
            startDate: original.startDate, deadline: original.deadline, writer: "phone")
        XCTAssertEqual(ledger.datedGoalProgress(now: now, calendar: utc).first?.actualMinutes, 60)
        XCTAssertEqual(ledger.entries.first?.categoryIDs, ["work"])
        try ledger.saveSample(id: "calendar-p", at: date("2026-10-19T09:00:00Z"), activity: "Corrected prep", categoryIDs: ["work"], writer: "p", now: now)
        XCTAssertEqual(ledger.datedGoalProgress(now: now, calendar: utc).first?.actualMinutes, 60)
        try ledger.confirmCategories(for: "calendar-p", categoryIDs: ["work", "social"], writer: "phone")
        XCTAssertEqual(ledger.datedGoalProgress(now: now, calendar: utc).first?.actualMinutes, 30)
    }

    func testQuickSyncCarriesGoalCalendarAndLogReferences() throws {
        var phone = Ledger(); let id = try goal(&phone)
        try period(&phone, id: "p", start: "2026-10-19T08:00:00Z", end: "2026-10-19T09:00:00Z", goalID: id)
        var delivery = CompanionQuickDelivery()
        let data = try XCTUnwrap(delivery.prepare(phone, id: "packet"))
        let packet = try JSONDecoder().decode(CompanionQuickPacket.self, from: data)
        var watch = Ledger(); watch.merge(packet.ledger)
        XCTAssertEqual(watch.datedGoals, phone.datedGoals)
        XCTAssertEqual(watch.calendarEvents, phone.calendarEvents)
        XCTAssertEqual(watch.entries, phone.entries)
        XCTAssertTrue(delivery.finish(id: "packet", saved: true))
        XCTAssertNil(try delivery.prepare(phone, id: "already-saved"))
    }

    func testWorkdayPaceAcrossDSTHasNoExtraOrMissingDay() throws {
        var ledger = Ledger(); ledger.settings.reportingTimeZoneIdentifier = "Europe/Berlin"
        let start = date("2026-10-23T05:00:00Z"), end = date("2026-10-26T21:00:00Z")
        try ledger.saveDatedGoal(name: "Autumn", categoryID: nil, targetMinutes: 240, startDate: start, deadline: end, writer: "p")
        let goal = ledger.activeDatedGoals[0]
        XCTAssertEqual(Ledger.workdayUnits(from: start, to: end, goal: goal), 2, accuracy: 0.001)
        let row = ledger.datedGoalProgress(now: date("2026-10-25T12:00:00Z"), calendar: utc)[0]
        XCTAssertEqual(row.expectedMinutes, 120, accuracy: 0.001)
        XCTAssertEqual(row.remainingWorkdays, 1, accuracy: 0.001)
    }

    func testDatedGoalNeverChangesPercentageTargetsAndDeletedGoalDoesNotBlockLogReview() throws {
        var ledger = Ledger()
        try ledger.saveAllocationGoals(["work": 30, "social": 20], writer: "p")
        let budget = ledger.currentBudget()
        let id = try goal(&ledger)
        try period(&ledger, id: "p", start: "2026-10-19T08:00:00Z", end: "2026-10-19T09:00:00Z", goalID: id)
        XCTAssertEqual(ledger.currentBudget(), budget)
        ledger.deleteDatedGoal(id, writer: "p")
        XCTAssertNoThrow(try ledger.assignGoal(id, to: "calendar-p", writer: "p"))
        XCTAssertEqual(ledger.entries.first?.goalID, id)
        try ledger.assignGoal(nil, to: "calendar-p", writer: "p")
        XCTAssertNil(ledger.entries.first?.goalID)
        XCTAssertNil(ledger.entries.first?.goalShare)
        XCTAssertEqual(ledger.currentBudget(), budget)
    }

    func testShortFirstAndLastDaysCountAsDatesForTheDailyAverage() throws {
        var ledger = Ledger()
        _ = try goal(&ledger, start: "2026-10-23T20:00:00Z", end: "2026-10-26T09:00:00Z")
        let row = ledger.datedGoalProgress(now: date("2026-10-23T20:00:00Z"), calendar: utc)[0]
        XCTAssertEqual(row.remainingWorkdays, 2)
        XCTAssertEqual(row.dailyMinutesNeeded, 120)
        XCTAssertEqual(row.expectedMinutes, 0)
        let next = ledger.datedGoalProgress(now: date("2026-10-23T21:00:00Z"), calendar: utc)[0]
        XCTAssertEqual(next.expectedMinutes, 60, accuracy: 0.001)
    }

}
