import XCTest
@testable import LedgerCore

final class AllocationReferenceTests: XCTestCase {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "Europe/Berlin")!; return cal
    }
    private func stamp(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
    private func fixture() throws -> Ledger {
        var ledger = Ledger(); ledger.categories = [LedgerCategory(id: "work", name: "Work"), LedgerCategory(id: "teaching", name: "Teaching"), LedgerCategory(id: "music", name: "Music"), LedgerCategory(id: "food", name: "Eating")]
        try ledger.moveCategory("teaching", to: "work", writer: "test")
        return ledger
    }
    func testReferenceExcludesTodayAndIncludesPreviousSevenCalendarDates() throws {
        var ledger = try fixture()
        let now = stamp("2026-10-22T10:00:00+02:00")
        for text in ["2026-10-15T08:00:00+02:00", "2026-10-21T20:00:00+02:00", "2026-10-22T09:00:00+02:00", "2026-10-14T08:00:00+02:00"] {
            try ledger.saveSample(at: stamp(text), activity: "Activity", categoryIDs: ["music"], writer: "test", now: now)
        }
        let reference = ledger.completedAllocationReference(now: now, calendar: calendar)
        XCTAssertEqual(reference.period.requestedDays, 7)
        XCTAssertEqual(reference.period.representedDays, 2)
        XCTAssertEqual(reference.period.trackedMinutes, 30, accuracy: 0.001)
        XCTAssertEqual(reference.averageDayMinutes, 15)
    }
    func testNoCompletedDataDoesNotInventHoursOrRoom() throws {
        var ledger = try fixture()
        let now = stamp("2026-10-22T10:00:00+02:00")
        try ledger.saveSample(at: now, activity: "Today only", categoryIDs: ["music"], writer: "test", now: now)
        let ref = ledger.completedAllocationReference(now: now, calendar: calendar)
        XCTAssertNil(ref.averageDayMinutes)
        XCTAssertNil(ref.percentage(forDailyHours: 4))
        XCTAssertNil(ref.dailyMinutes(for: 20))
        let capacity = ledger.allocationCapacity(goals: ["music": 20], reference: ref)
        XCTAssertEqual(capacity.goalsPercentage, 20)
        XCTAssertNil(capacity.otherPercentage)
        XCTAssertNil(capacity.roomPercentage)
    }
    func testHoursAndPercentAreTwoUnitsOfOneFixedGoal() throws {
        var ledger = try fixture()
        var period = AllocationPeriod(); period.trackedMinutes = 14 * 60 * 3; period.representedDays = 3
        let ref = AllocationReference(period: period)
        let percentage = try XCTUnwrap(ref.percentage(forDailyHours: 4))
        XCTAssertEqual(percentage, 100 * 4 / 14, accuracy: 0.0000001)
        XCTAssertEqual(try XCTUnwrap(ref.dailyMinutes(for: percentage)), 240, accuracy: 0.0000001)
        try ledger.updateAllocationGoal(categoryID: "music", percentage: percentage, writer: "test")
        let saved = ledger.currentGoals()
        period.trackedMinutes = 12 * 60 * 3
        XCTAssertEqual(AllocationReference(period: period).dailyMinutes(for: percentage)!, 12 * 60 * 4 / 14, accuracy: 0.0000001)
        XCTAssertEqual(ledger.currentGoals(), saved)
    }
    func testCapacityIncludesUnplannedDirectAndUncategorizedTimeOnce() throws {
        let ledger = try fixture()
        var period = AllocationPeriod(); period.trackedMinutes = 100; period.representedDays = 1
        period.directMinutes = ["teaching": 40, "music": 20, "food": 20, "work": 10, "uncategorized": 10]
        let capacity = ledger.allocationCapacity(goals: ["teaching": 30, "music": 30, "work": 30], reference: AllocationReference(period: period))
        XCTAssertEqual(capacity.goalsPercentage, 60)
        XCTAssertEqual(capacity.otherPercentage, 40)
        XCTAssertEqual(capacity.roomPercentage, 0)
        let changed = ledger.allocationCapacity(goals: ["teaching": 30, "music": 40], reference: AllocationReference(period: period))
        XCTAssertEqual(changed.roomPercentage, -10)
    }
    func testOptionalGoalsDoNotRequire100AndChangingOneDoesNotRedistribute() throws {
        var ledger = try fixture()
        try ledger.saveAllocationGoals(["teaching": 30, "music": 20], writer: "test")
        XCTAssertNil(ledger.currentGoals()["food"])
        var period = AllocationPeriod(); period.trackedMinutes = 100; period.representedDays = 1
        period.directMinutes = ["music": 10, "teaching": 60, "food": 30]
        var capacity = ledger.allocationCapacity(goals: ledger.currentGoals(), reference: AllocationReference(period: period))
        XCTAssertEqual(capacity.roomPercentage, 20)
        try ledger.updateAllocationGoal(categoryID: "music", percentage: 40, writer: "test")
        XCTAssertEqual(ledger.currentGoals()["teaching"], 30)
        capacity = ledger.allocationCapacity(goals: ledger.currentGoals(), reference: AllocationReference(period: period))
        XCTAssertEqual(capacity.roomPercentage, 0)
    }
    func testUneditedRoundedHoursPreserveExactPercentGoal() throws {
        var period = AllocationPeriod(); period.trackedMinutes = 14 * 60; period.representedDays = 1
        let ref = AllocationReference(period: period)
        let exactGoal = 100.0 / 3
        let hours = ref.dailyMinutes(for: exactGoal)! / 60
        let draft = AllocationPlanDraft(["music": hours], maximumFractionDigits: 2)
        XCTAssertEqual(draft.text["music"], "4.67")
        XCTAssertEqual(draft.values?["music"], hours)
        XCTAssertEqual(ref.percentage(forDailyHours: draft.values!["music"]!)!, exactGoal, accuracy: 0.0000001)
    }
    func testDailyAverageUsesRepresentedDaysRatherThanSevenOrToday() {
        var period = AllocationPeriod(); period.representedDays = 4; period.requestedDays = 7; period.trackedMinutes = 4 * 14 * 60
        let ref = AllocationReference(period: period)
        XCTAssertEqual(ref.averageMinutes(4 * 4 * 60), 240)
        XCTAssertEqual(ref.dailyMinutes(for: 100 * 4 / 14), 240)
        XCTAssertNil(ref.averageMinutes(.nan))
        XCTAssertNil(ref.percentage(forDailyHours: -1))
    }
    func testTimeZoneDSTAndOutOfNotificationWindowLogsAreIncluded() throws {
        var ledger = try fixture()
        let now = stamp("2026-10-26T10:00:00+01:00")
        try ledger.saveSample(at: stamp("2026-10-25T02:30:00+02:00"), activity: "Night log", categoryIDs: ["music"], writer: "test", now: now)
        try ledger.saveSample(at: stamp("2026-10-25T02:30:00+01:00"), activity: "After clock change", categoryIDs: ["food"], writer: "test", now: now)
        let ref = ledger.completedAllocationReference(now: now, calendar: calendar)
        XCTAssertEqual(ref.period.representedDays, 1)
        XCTAssertEqual(ref.period.trackedMinutes, 75, accuracy: 0.001)
        XCTAssertEqual(ledger.entries.count, 2)
        let restored = try LedgerBackup.decode(LedgerBackup(ledger: ledger).encoded()).ledger
        XCTAssertEqual(restored.completedAllocationReference(now: now, calendar: calendar), ref)
    }
}
