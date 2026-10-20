import XCTest
@testable import LedgerCore

final class TrendPresentationTests: XCTestCase {
    private var calendar: Calendar { var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "Europe/Berlin")!; return cal }
    private func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
    private func report() throws -> HistoryReport {
        var ledger = Ledger()
        ledger.settings.reportingTimeZoneIdentifier = "Europe/Berlin"
        let now = date("2026-10-25T15:00:00Z")
        for (stamp, ids) in [("2026-10-22T08:00:00Z", ["work"]), ("2026-10-22T09:00:00Z", ["social"]),
                             ("2026-10-24T22:30:00Z", ["work", "social"]), ("2026-10-25T12:00:00Z", ["leisure"]), ("2026-10-25T13:00:00Z", ["personal"])] {
            try ledger.saveSample(at: date(stamp), activity: stamp, categoryIDs: ids, writer: "test", now: now)
        }
        return ledger.history(range: .week, now: now, calendar: calendar)
    }

    func testInitialComparisonHasAtMostThreeLargestTopLevelCategories() throws {
        let report = try report()
        XCTAssertEqual(report.rows.count, 4)
        XCTAssertEqual(report.trendRows(selectedIDs: nil), Array(report.rows.prefix(3)))
        XCTAssertLessThanOrEqual(report.trendRows(selectedIDs: nil).count, 3)
    }
    func testExplicitSelectionKeepsOrderRemovesDuplicatesAndIgnoresUnavailableIDs() throws {
        let report = try report()
        XCTAssertEqual(report.trendRows(selectedIDs: ["leisure", "deleted", "social", "leisure"]).map(\.id), ["leisure", "social"])
        XCTAssertTrue(report.trendRows(selectedIDs: []).isEmpty)
        XCTAssertTrue(report.trendRows(selectedIDs: ["no-data-this-period"]).isEmpty)
        XCTAssertEqual(report.trendRows(selectedIDs: ["social"]).first?.name, "Socializing")
    }
    func testFilteringDoesNotRenormalizePercentagesOrChangeGapSegments() throws {
        let report = try report()
        let selected = report.trendPoints(categoryIDs: ["social"])
        XCTAssertEqual(selected, report.dailyTotals.filter { $0.categoryID == "social" })
        XCTAssertTrue(selected.contains { $0.percent > 0 && $0.percent < 100 })
        XCTAssertTrue(report.trendPoints(categoryIDs: ["leisure"]).contains { $0.minutes == 0 })
        XCTAssertEqual(selected.reduce(0) { $0 + $1.minutes }, report.rows.first { $0.id == "social" }?.minutes)
        XCTAssertEqual(Set(selected.map(\.segmentStart)).count, 2)
        XCTAssertEqual(report.trendPoints(categoryIDs: ["social", "social"]), selected)
    }
    func testInspectDayUsesReportingCalendarAcrossDSTAndNeverSubstitutesForMissingDay() throws {
        let report = try report()
        // This instant is already Oct 25 in Berlin; the repeated clock hour on
        // the DST transition belongs to the same represented calendar day.
        let before = report.trendPoints(on: date("2026-10-24T23:30:00Z"), categoryIDs: ["work", "social"], calendar: calendar)
        let after = report.trendPoints(on: date("2026-10-25T01:30:00Z"), categoryIDs: ["work", "social"], calendar: calendar)
        XCTAssertEqual(before, after)
        XCTAssertEqual(before.count, 2)
        XCTAssertTrue(report.trendPoints(on: date("2026-10-23T12:00:00Z"), categoryIDs: ["social"], calendar: calendar).isEmpty)
    }
    func testCategoryPanelsShareScaleFromAllCategoriesAndDoNotMutateReport() throws {
        let report = try report(), rows = report.rows, points = report.dailyTotals
        let maximum = max(1, points.map { $0.minutes / 60 }.max() ?? 0)
        XCTAssertEqual(report.trendMaximumHours, maximum)
        for row in rows {
            XCTAssertTrue(report.trendPoints(categoryIDs: [row.id]).allSatisfy { $0.minutes / 60 <= maximum })
        }
        XCTAssertEqual(report.rows, rows); XCTAssertEqual(report.dailyTotals, points)
    }
}
