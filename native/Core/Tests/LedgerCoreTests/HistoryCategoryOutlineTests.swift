import XCTest
@testable import LedgerCore

final class HistoryCategoryOutlineTests: XCTestCase {
    private var calendar: Calendar { var value = Calendar(identifier: .gregorian); value.timeZone = TimeZone(secondsFromGMT: 0)!; return value }
    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    private var now: Date { date("2026-10-21T13:00:00Z") }
    private func fixture() throws -> Ledger {
        var ledger = Ledger()
        ledger.settings.regularNotificationInterval = 20
        ledger.categories = [LedgerCategory(id: "work", name: "Work"), LedgerCategory(id: "music", name: "Music"),
                             LedgerCategory(id: "teaching", name: "Teaching"), LedgerCategory(id: "admin", name: "Admin"),
                             LedgerCategory(id: "guitar", name: "Guitar"), LedgerCategory(id: "empty", name: "Not logged yet")]
        try ledger.moveCategory("teaching", to: "work", writer: "test")
        try ledger.moveCategory("admin", to: "work", writer: "test")
        try ledger.moveCategory("guitar", to: "music", writer: "test")
        try ledger.moveCategory("empty", to: "teaching", writer: "test")
        for (hour, ids) in [(9, ["teaching"]), (10, ["work", "music"]), (11, ["guitar", "admin"]), (12, [])] {
            try ledger.saveSample(at: date(String(format: "2026-10-21T%02d:00:00Z", hour)), activity: "Sample \(hour)", categoryIDs: ids, writer: "test", now: now)
        }
        return ledger
    }

    func testCollapsedDashboardKeepsExistingTotalsOrderAndChartDenominator() throws {
        let ledger = try fixture(), report = ledger.history(range: .today, now: now, calendar: calendar)
        let rows = report.categoryOutline(in: ledger, expanded: [])
        XCTAssertEqual(rows.map(\.row), report.rows)
        XCTAssertEqual(rows.map(\.id), ["work", "music", "uncategorized"])
        XCTAssertTrue(rows.allSatisfy { $0.depth == 0 && !$0.direct })
        XCTAssertEqual(report.trackedMinutes, 200, accuracy: 0.001)
        XCTAssertEqual(report.rows.reduce(0) { $0 + $1.percent }, 100, accuracy: 0.001)
        XCTAssertEqual(report.rows.map(\.minutes), [100, 60, 40])
    }

    func testExpandedParentIncludesDirectSharesAndEquallySplitDescendantTime() throws {
        let ledger = try fixture(), report = ledger.history(range: .today, now: now, calendar: calendar)
        let rows = report.categoryOutline(in: ledger, expanded: ["work"])
        let children = rows.filter { $0.depth == 1 }
        XCTAssertEqual(Set(children.map(\.id)), ["direct:work", "teaching", "admin"])
        XCTAssertEqual(children.reduce(0) { $0 + $1.row.minutes }, 100, accuracy: 0.001)
        XCTAssertEqual(children.first { $0.id == "direct:work" }?.row.minutes, 30)
        XCTAssertEqual(children.first { $0.id == "teaching" }?.row.minutes, 40)
        XCTAssertEqual(children.first { $0.id == "admin" }?.row.minutes, 30)
        XCTAssertEqual(children.reduce(0) { $0 + $1.row.percent }, 50, accuracy: 0.001)
        XCTAssertEqual(rows.filter { $0.depth == 0 }.map(\.row), report.rows)
        XCTAssertFalse(rows.contains { $0.id == "guitar" || $0.id == "empty" })
    }

    func testNestedBranchesCanExpandIndependentlyAndKeepZeroTimeChildrenVisible() throws {
        let ledger = try fixture(), report = ledger.history(range: .today, now: now, calendar: calendar)
        let rows = report.categoryOutline(in: ledger, expanded: ["work", "teaching", "music"])
        let empty = try XCTUnwrap(rows.first { $0.id == "empty" })
        XCTAssertEqual(empty.depth, 2); XCTAssertEqual(empty.row.minutes, 0)
        XCTAssertEqual(rows.first { $0.id == "direct:teaching" }?.row.minutes, 40)
        XCTAssertEqual(rows.first { $0.id == "guitar" }?.row.minutes, 30)
        XCTAssertEqual(rows.first { $0.id == "direct:music" }?.row.minutes, 30)
        XCTAssertEqual(Set(rows.map(\.id)).count, rows.count)
        let collapsedParent = report.categoryOutline(in: ledger, expanded: ["teaching", "music"])
        XCTAssertFalse(collapsedParent.contains { $0.id == "empty" || $0.id == "teaching" })
        XCTAssertTrue(collapsedParent.contains { $0.id == "guitar" })
    }

    func testMultiDayOutlineUsesTheSelectedHistoryAndRecategorizationRefreshesIt() throws {
        var ledger = try fixture()
        try ledger.saveSample(id: "yesterday", at: date("2026-10-20T10:00:00Z"), activity: "Earlier", categoryIDs: ["guitar"], writer: "test", now: now)
        let today = ledger.history(range: .today, now: now, calendar: calendar)
        let week = ledger.history(range: .week, now: now, calendar: calendar)
        XCTAssertEqual(today.directMinutes["guitar"], 30)
        XCTAssertEqual(week.directMinutes["guitar"], 50)
        XCTAssertEqual(week.categoryOutline(in: ledger, expanded: ["music"]).first { $0.id == "guitar" }?.row.minutes, 50)
        try ledger.confirmCategories(for: "yesterday", categoryIDs: ["teaching"], writer: "test")
        let changed = ledger.history(range: .week, now: now, calendar: calendar)
        XCTAssertEqual(changed.directMinutes["guitar"], 30)
        XCTAssertEqual(changed.categoryOutline(in: ledger, expanded: ["work"]).first { $0.id == "teaching" }?.row.minutes, 60)
        XCTAssertEqual(ledger.entries.count, 5)
    }

    func testZeroFilterHidesEmptyBranchesWithoutChangingTotalsOrLogs() throws {
        var ledger = try fixture()
        ledger.categories.append(LedgerCategory(id: "unused", name: "Unused root"))
        let before = ledger
        let report = ledger.history(range: .today, now: now, calendar: calendar)
        let hidden = report.categoryOutline(in: ledger, expanded: ["work", "teaching", "music"], hideZeroTime: true)
        XCTAssertFalse(hidden.contains { ["empty", "unused"].contains($0.row.id) })
        XCTAssertEqual(hidden.first { $0.id == "teaching" }?.hasChildren, false)
        XCTAssertEqual(hidden.filter { $0.depth == 0 }.map(\.row), report.rows)
        XCTAssertEqual(hidden.first { $0.id == "direct:work" }?.row.minutes, 30)
        XCTAssertTrue(hidden.contains { $0.id == "uncategorized" })
        let shown = report.categoryOutline(in: ledger, expanded: ["work", "teaching"], hideZeroTime: false)
        XCTAssertEqual(shown.first { $0.id == "unused" }?.row.minutes, 0)
        XCTAssertEqual(shown.first { $0.id == "empty" }?.row.minutes, 0)
        XCTAssertEqual(ledger, before)
    }

    func testVisibilityKeepsGoalsEvenWhenZeroAndIncludesAllAncestors() throws {
        let ledger = try fixture()
        let ids = ledger.activeCategoryIDs(in: [], includingGoals: ["empty": 0, "guitar": 15])
        XCTAssertEqual(ids, ["empty", "teaching", "work", "guitar", "music"])
        XCTAssertFalse(ids.contains("admin"))
    }

    func testVisibilityUsesBothPeriodsAndKeepsDirectParentTime() throws {
        let ledger = try fixture()
        let today = AllocationPeriod(directMinutes: ["work": 12, "admin": 0])
        let week = AllocationPeriod(directMinutes: ["guitar": 30, "uncategorized": 8])
        XCTAssertEqual(ledger.activeCategoryIDs(in: [today, week]), ["work", "guitar", "music", "uncategorized"])
        XCTAssertEqual(ledger.activeCategoryIDs(in: [today]), ["work"])
        XCTAssertTrue(ledger.activeCategoryIDs(in: []).isEmpty)
    }

    func testZeroFilterUsesSelectedPeriodRatherThanAllTimeActivity() throws {
        var ledger = try fixture()
        ledger.categories.append(LedgerCategory(id: "older", name: "Only yesterday"))
        try ledger.saveSample(at: date("2026-10-20T10:00:00Z"), activity: "Yesterday", categoryIDs: ["older"], writer: "test", now: now)
        let today = ledger.history(range: .today, now: now, calendar: calendar)
        let week = ledger.history(range: .week, now: now, calendar: calendar)
        XCTAssertFalse(today.categoryOutline(in: ledger, expanded: [], hideZeroTime: true).contains { $0.id == "older" })
        XCTAssertTrue(week.categoryOutline(in: ledger, expanded: [], hideZeroTime: true).contains { $0.id == "older" })
        XCTAssertTrue(today.categoryOutline(in: ledger, expanded: [], hideZeroTime: false).contains { $0.id == "older" && $0.row.minutes == 0 })
    }

    func testEmptyFilteredReportDoesNotInventTimeOrUncategorizedRows() throws {
        let ledger = Ledger()
        let report = ledger.history(range: .today, now: now, calendar: calendar)
        XCTAssertTrue(report.categoryOutline(in: ledger, expanded: [], hideZeroTime: true).isEmpty)
        XCTAssertEqual(report.categoryOutline(in: ledger, expanded: [], hideZeroTime: false).count, ledger.children(of: nil).count)
        XCTAssertEqual(report.trackedMinutes, 0)
        XCTAssertTrue(report.rows.isEmpty)
    }
}
