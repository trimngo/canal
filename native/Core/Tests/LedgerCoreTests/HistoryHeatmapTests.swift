import XCTest
@testable import LedgerCore

final class HistoryHeatmapTests: XCTestCase {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "Europe/Berlin")!; return cal
    }
    private func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }

    func testGridIncludesEveryReportedCategoryWithoutFilteringOrRenormalizing() throws {
        var ledger = Ledger(); ledger.settings.reportingTimeZoneIdentifier = calendar.timeZone.identifier
        let now = date("2026-10-26T12:00:00Z")
        for (stamp, category) in [("2026-10-24T08:00:00Z", "work"), ("2026-10-24T09:00:00Z", "social"),
                                  ("2026-10-26T08:00:00Z", "leisure"), ("2026-10-26T09:00:00Z", "personal")] {
            try ledger.saveSample(at: date(stamp), activity: category, categoryID: category, writer: "test", now: now)
        }
        let report = ledger.history(range: .week, now: now, calendar: calendar)
        let grid = HistoryHeatmap(report: report, ledger: ledger, calendar: calendar)
        XCTAssertEqual(grid.rows.map(\.row), report.rows); XCTAssertEqual(grid.rows.count, 4)
        XCTAssertEqual(grid.days.count, 7)
        for point in report.dailyTotals {
            XCTAssertEqual(grid.point(on: point.day, categoryID: point.categoryID), point)
        }
        let today = calendar.startOfDay(for: now)
        XCTAssertEqual(grid.point(on: today, categoryID: "work")?.minutes, 0)
        XCTAssertEqual(grid.rows.reduce(0) { $0 + (grid.point(on: today, categoryID: $1.id)?.percent ?? 0) }, 100, accuracy: 0.001)
        XCTAssertEqual(grid.maximumMinutes, report.dailyTotals.map(\.minutes).max())
        let missing = calendar.startOfDay(for: date("2026-10-25T12:00:00Z"))
        XCTAssertTrue(grid.days.contains(missing))
        XCTAssertNil(grid.point(on: missing, categoryID: "work"))
        XCTAssertNil(grid.point(on: today, categoryID: "deleted-category"))
    }

    func testDatesFollowReportingCalendarAcrossDSTAndExclusiveCustomEnd() throws {
        var ledger = Ledger(); ledger.settings.reportingTimeZoneIdentifier = calendar.timeZone.identifier
        let now = date("2026-10-27T12:00:00Z")
        let report = ledger.history(range: .custom, start: date("2026-10-24T12:00:00Z"), end: date("2026-10-26T12:00:00Z"), now: now, calendar: calendar)
        let grid = HistoryHeatmap(report: report, ledger: ledger, calendar: calendar)
        XCTAssertEqual(grid.days, [date("2026-10-23T22:00:00Z"), date("2026-10-24T22:00:00Z"), date("2026-10-25T23:00:00Z")])
        XCTAssertEqual(grid.days[2].timeIntervalSince(grid.days[1]), 25 * 3600)
        XCTAssertTrue(grid.rows.isEmpty); XCTAssertEqual(grid.maximumMinutes, 0)
        XCTAssertTrue(grid.days.allSatisfy { grid.point(on: $0, categoryID: "work") == nil })
    }

    func testEmptyTodayStillHasOneDateColumnAndNoInventedActivities() {
        let now = date("2026-10-26T12:00:00Z"), ledger = Ledger()
        let report = ledger.history(range: .today, now: now, calendar: calendar)
        let grid = HistoryHeatmap(report: report, ledger: ledger, calendar: calendar)
        XCTAssertEqual(grid.days, [calendar.startOfDay(for: now)])
        XCTAssertTrue(grid.rows.isEmpty); XCTAssertEqual(grid.maximumMinutes, 0)
    }

    private func hierarchyFixture() throws -> Ledger {
        var ledger = Ledger(); ledger.settings.reportingTimeZoneIdentifier = calendar.timeZone.identifier
        ledger.settings.regularNotificationInterval = 20
        ledger.categories = [LedgerCategory(id: "work", name: "Work"), LedgerCategory(id: "music", name: "Music"),
            LedgerCategory(id: "teaching", name: "Teaching"), LedgerCategory(id: "admin", name: "Admin"), LedgerCategory(id: "guitar", name: "Guitar")]
        try ledger.moveCategory("teaching", to: "work", writer: "test")
        try ledger.moveCategory("admin", to: "work", writer: "test")
        try ledger.moveCategory("guitar", to: "music", writer: "test")
        let now = date("2026-10-26T13:00:00Z")
        for (hour, ids) in [(9, ["teaching"]), (10, ["work", "music"]), (11, ["guitar", "admin"]), (12, [])] {
            try ledger.saveSample(id: "sample-\(hour)", at: date(String(format: "2026-10-26T%02d:00:00Z", hour)),
                activity: "Sample \(hour)", categoryIDs: ids, writer: "test", now: now)
        }
        return ledger
    }

    func testExpandedChildrenAndDirectTimeHaveOwnRowsWithoutDuplicateParentValues() throws {
        let ledger = try hierarchyFixture(), now = date("2026-10-26T13:00:00Z")
        let report = ledger.history(range: .today, now: now, calendar: calendar)
        let grid = HistoryHeatmap(report: report, ledger: ledger, calendar: calendar), day = grid.days[0]
        XCTAssertEqual(grid.rows.map(\.id), ["work", "direct:work", "teaching", "admin", "music", "direct:music", "guitar", "uncategorized"])
        XCTAssertEqual(grid.rows.filter(\.hasChildren).map(\.id), ["work", "music"])
        XCTAssertNil(grid.point(on: day, categoryID: "work")); XCTAssertNil(grid.point(on: day, categoryID: "music"))
        for (id, minutes) in ["direct:work": 30.0, "admin": 30, "teaching": 40, "direct:music": 30, "guitar": 30, "uncategorized": 40] {
            XCTAssertEqual(grid.point(on: day, categoryID: id)?.minutes, minutes)
        }
        XCTAssertEqual(grid.rows.reduce(0) { $0 + (grid.point(on: day, categoryID: $1.id)?.percent ?? 0) }, 100, accuracy: 0.001)
        XCTAssertEqual(grid.maximumMinutes, 40)
        XCTAssertEqual(Set(grid.rows.map(\.id)).count, grid.rows.count)
        // The other charts retain the existing root rollups and denominator.
        XCTAssertEqual(report.rows.map(\.minutes), [100, 60, 40])
        XCTAssertEqual(report.dailyTotals.reduce(0) { $0 + $1.minutes }, report.trackedMinutes)
    }

    func testNestedHeadingsOnlyIndentLabelsMetadataAndIncludeDirectShares() throws {
        var ledger = try hierarchyFixture()
        try ledger.confirmCategories(for: "sample-10", categoryIDs: ["music"], writer: "test")
        try ledger.moveCategory("music", to: "work", writer: "test")
        let report = ledger.history(range: .today, now: date("2026-10-26T13:00:00Z"), calendar: calendar)
        let grid = HistoryHeatmap(report: report, ledger: ledger, calendar: calendar)
        XCTAssertEqual(grid.rows.first { $0.id == "guitar" }?.depth, 2)
        XCTAssertEqual(grid.rows.first { $0.id == "direct:music" }?.depth, 2)
        XCTAssertEqual(grid.rows.first { $0.id == "music" }?.depth, 1)
        XCTAssertTrue(grid.rows.first { $0.id == "music" }?.hasChildren == true)
        XCTAssertEqual(grid.rows.reduce(0) { $0 + (grid.point(on: grid.days[0], categoryID: $1.id)?.minutes ?? 0) }, report.trackedMinutes)
    }

    func testDirectRowsKeepRepresentedZerosAndMissingDaysDistinct() throws {
        var ledger = try hierarchyFixture(), now = date("2026-10-26T13:00:00Z")
        try ledger.saveSample(at: date("2026-10-24T10:00:00Z"), activity: "Earlier teaching", categoryIDs: ["teaching"], writer: "test", now: now)
        let report = ledger.history(range: .week, now: now, calendar: calendar)
        let grid = HistoryHeatmap(report: report, ledger: ledger, calendar: calendar)
        let earlier = calendar.startOfDay(for: date("2026-10-24T10:00:00Z"))
        let missing = calendar.startOfDay(for: date("2026-10-25T10:00:00Z"))
        XCTAssertEqual(grid.point(on: earlier, categoryID: "direct:work")?.minutes, 0)
        XCTAssertEqual(grid.point(on: earlier, categoryID: "teaching")?.minutes, 20)
        XCTAssertNil(grid.point(on: missing, categoryID: "direct:work"))
        XCTAssertNil(grid.point(on: missing, categoryID: "teaching"))
    }

    func testRecategorizingDirectLogsRefreshesRowsAndKeepsRawTimes() throws {
        var ledger = try hierarchyFixture()
        let times = ledger.entries.map(\.end), now = date("2026-10-26T13:00:00Z")
        try ledger.confirmCategories(for: "sample-10", categoryIDs: ["teaching", "guitar"], writer: "test")
        let report = ledger.history(range: .today, now: now, calendar: calendar)
        let grid = HistoryHeatmap(report: report, ledger: ledger, calendar: calendar)
        XCTAssertFalse(grid.rows.contains { $0.direct })
        XCTAssertEqual(grid.point(on: grid.days[0], categoryID: "teaching")?.minutes, 70)
        XCTAssertEqual(grid.point(on: grid.days[0], categoryID: "guitar")?.minutes, 60)
        XCTAssertEqual(ledger.entries.map(\.end), times)
        XCTAssertEqual(report.trackedMinutes, 200)
    }

    func testParentWithOnlyDirectTimeHasADataRowAndEmptyChildrenStayHidden() throws {
        var ledger = try hierarchyFixture(); ledger.entries = []
        let now = date("2026-10-26T13:00:00Z")
        try ledger.saveSample(at: now.addingTimeInterval(-3600), activity: "Work", categoryIDs: ["work"], writer: "test", now: now)
        let report = ledger.history(range: .today, now: now, calendar: calendar)
        let grid = HistoryHeatmap(report: report, ledger: ledger, calendar: calendar)
        XCTAssertEqual(grid.rows.map(\.id), ["work", "direct:work"])
        XCTAssertTrue(grid.rows[0].hasChildren)
        XCTAssertEqual(grid.point(on: grid.days[0], categoryID: "direct:work")?.minutes, 20)
        XCTAssertEqual(grid.rows[1].row.name, "Work (direct)")
    }
}
