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
        let grid = HistoryHeatmap(report: report, calendar: calendar)
        XCTAssertEqual(grid.rows, report.rows); XCTAssertEqual(grid.rows.count, 4)
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
        let grid = HistoryHeatmap(report: report, calendar: calendar)
        XCTAssertEqual(grid.days, [date("2026-10-23T22:00:00Z"), date("2026-10-24T22:00:00Z"), date("2026-10-25T23:00:00Z")])
        XCTAssertEqual(grid.days[2].timeIntervalSince(grid.days[1]), 25 * 3600)
        XCTAssertTrue(grid.rows.isEmpty); XCTAssertEqual(grid.maximumMinutes, 0)
        XCTAssertTrue(grid.days.allSatisfy { grid.point(on: $0, categoryID: "work") == nil })
    }

    func testEmptyTodayStillHasOneDateColumnAndNoInventedActivities() {
        let now = date("2026-10-26T12:00:00Z"), ledger = Ledger()
        let report = ledger.history(range: .today, now: now, calendar: calendar)
        let grid = HistoryHeatmap(report: report, calendar: calendar)
        XCTAssertEqual(grid.days, [calendar.startOfDay(for: now)])
        XCTAssertTrue(grid.rows.isEmpty); XCTAssertEqual(grid.maximumMinutes, 0)
    }
}
