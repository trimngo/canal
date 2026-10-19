import XCTest
@testable import LedgerCore

final class HistoryAndBackupTests: XCTestCase {
    private var calendar: Calendar { var value = Calendar(identifier: .gregorian); value.timeZone = TimeZone(secondsFromGMT: 0)!; return value }
    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    private func fixture() throws -> Ledger {
        var ledger = Ledger()
        let now = date("2026-10-15T11:00:00Z")
        for (stamp, group) in [("2026-10-01T09:00:00Z", "leisure"), ("2026-10-01T10:00:00Z", "leisure"), ("2026-10-14T09:00:00Z", "work"), ("2026-10-14T10:00:00Z", "social"), ("2026-10-15T09:00:00Z", "work"), ("2026-10-15T10:00:00Z", "social")] {
            try ledger.saveSample(at: date(stamp), activity: stamp, categoryID: group, writer: "test", now: now)
        }
        return ledger
    }
    func testMultiDayPercentagesAreWeightedByTrackedTime() throws {
        let ledger = try fixture(), now = date("2026-10-15T11:00:00Z")
        let week = ledger.history(range: .week, now: now, calendar: calendar)
        XCTAssertEqual(week.samples.count, 4)
        XCTAssertEqual(week.trackedMinutes, 1020, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(week.rows.first { $0.id == "work" }).minutes, 60, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(week.rows.first { $0.id == "work" }).percent, 60.0 / 1020 * 100, accuracy: 0.001)
        XCTAssertEqual(week.rows.reduce(0) { $0 + $1.percent }, 100, accuracy: 0.001)
        XCTAssertEqual(ledger.history(range: .allTime, now: now, calendar: calendar).trackedMinutes, 1920, accuracy: 0.001)
        XCTAssertEqual(ledger.entries.count, 6)
    }
    func testCustomRangeIncludesWholeSelectedDatesAndExcludesNextMidnight() throws {
        var ledger = try fixture(), now = date("2026-10-15T11:00:00Z")
        try ledger.saveSample(at: date("2026-10-15T00:00:00Z"), activity: "Boundary", categoryID: nil, writer: "test", now: now)
        let report = ledger.history(range: .custom, start: date("2026-10-14T23:00:00Z"), end: date("2026-10-14T01:00:00Z"), now: now, calendar: calendar)
        XCTAssertEqual(report.samples.count, 2)
        XCTAssertEqual(report.trackedMinutes, 900, accuracy: 0.001)
        XCTAssertFalse(report.samples.contains { $0.activity == "Boundary" })
    }
    func testLegacyRemainingTimePreferenceDoesNotChangeTrackedPercentages() throws {
        var ledger = Ledger()
        var berlin = calendar; berlin.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let now = date("2026-10-25T12:00:00Z")
        try ledger.saveSample(at: now.addingTimeInterval(-3600), activity: "Reading", categoryID: "leisure", writer: "test", now: now)
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(ledger)) as! [String: Any]
        var settings = json["settings"] as! [String: Any]; settings["showRemainingTime"] = true; json["settings"] = settings
        ledger = try JSONDecoder().decode(Ledger.self, from: JSONSerialization.data(withJSONObject: json))
        let report = ledger.history(range: .today, now: now, calendar: berlin)
        XCTAssertEqual(report.trackedMinutes, 60, accuracy: 0.001)
        XCTAssertFalse(report.rows.contains { $0.id == "remaining" })
        XCTAssertEqual(report.rows.first?.percent, 100)
    }
    func testCategoryTrendUsesPerDayDenominatorsAndZerosOnlyOnRepresentedDays() throws {
        let ledger = try fixture(), now = date("2026-10-15T11:00:00Z")
        let report = ledger.history(range: .allTime, now: now, calendar: calendar)
        let days = Dictionary(grouping: report.dailyTotals, by: \.day)
        XCTAssertEqual(days.count, 3)
        for (_, points) in days {
            XCTAssertEqual(Set(points.map(\.categoryID)), Set(report.rows.map(\.id)))
            XCTAssertEqual(points.reduce(0) { $0 + $1.percent }, 100, accuracy: 0.0001)
            XCTAssertEqual(points.reduce(0) { $0 + $1.minutes }, points[0].dayMinutes, accuracy: 0.0001)
        }
        let today = try XCTUnwrap(days[date("2026-10-15T00:00:00Z")])
        XCTAssertEqual(try XCTUnwrap(today.first { $0.categoryID == "leisure" }).minutes, 0)
        XCTAssertEqual(try XCTUnwrap(today.first { $0.categoryID == "work" }).percent, 25, accuracy: 0.001)
        XCTAssertFalse(report.dailyTotals.contains { $0.day == date("2026-10-13T00:00:00Z") })
        XCTAssertNotEqual(report.dailyTotals.first { $0.day == date("2026-10-01T00:00:00Z") }?.segmentStart,
                          report.dailyTotals.first { $0.day == date("2026-10-14T00:00:00Z") }?.segmentStart)
        XCTAssertEqual(report.dailyTotals.first { $0.day == date("2026-10-14T00:00:00Z") }?.segmentStart,
                       report.dailyTotals.first { $0.day == date("2026-10-15T00:00:00Z") }?.segmentStart)
    }

    func testCategorizingRefreshesSummaryAndTrendWithoutMovingTheLog() throws {
        var ledger = Ledger()
        let now = date("2026-10-15T11:00:00Z")
        try ledger.saveSample(id: "unlabeled", at: now.addingTimeInterval(-3600), activity: "Original", categoryID: nil, writer: "phone", now: now)
        XCTAssertEqual(ledger.history(range: .today, now: now, calendar: calendar).rows.first?.id, "uncategorized")
        let original = ledger.entries[0]
        try ledger.confirmCategories(for: "unlabeled", categoryIDs: ["work", "social"], writer: "phone")
        let report = ledger.history(range: .today, now: now, calendar: calendar)
        XCTAssertEqual(Set(report.rows.map(\.id)), ["work", "social"])
        XCTAssertTrue(report.rows.allSatisfy { abs($0.percent - 50) < 0.001 })
        XCTAssertTrue(report.dailyTotals.allSatisfy { abs($0.percent - 50) < 0.001 })
        XCTAssertEqual(ledger.entries[0].end, original.end)
        XCTAssertEqual(ledger.entries[0].activity, original.activity)
    }

    func testBackupRoundTripRetainsYearsOfRawLogsAndRankingProgress() throws {
        var ledger = try fixture()
        let now = date("2026-10-15T11:00:00Z")
        try ledger.saveSample(at: date("2020-01-01T09:01:23Z"), activity: "Original old sample", categoryID: nil, writer: "test", now: now)
        try ledger.addCapture(text: "A", id: "a", writer: "test", now: now)
        try ledger.addCapture(text: "B", id: "b", writer: "test", now: now)
        ledger.prepareRanking(writer: "test")
        let restored = try LedgerBackup.decode(LedgerBackup(ledger: ledger, savedAt: now).encoded())
        XCTAssertEqual(restored.savedAt, now)
        XCTAssertEqual(restored.ledger, ledger)
        XCTAssertEqual(restored.ledger.entries.first { $0.activity == "Original old sample" }?.end, date("2020-01-01T09:01:23Z"))
    }
    func testRestoreMergesHistoryWithoutRevertingNewerEditsOrResurrectingDeletedIdeas() throws {
        var original = try fixture()
        let idea = try original.addCapture(text: "Old idea", writer: "phone")
        let backup = try LedgerBackup(ledger: original).encoded()
        var current = original
        current.setCaptureDeleted(idea.id, deleted: true, writer: "phone")
        try current.saveQuickSample(id: "new", at: Date(), activity: "Newest log", writer: "phone")
        current.merge(try LedgerBackup.decode(backup).ledger)
        XCTAssertEqual(current.entries.count, original.entries.count + 1)
        XCTAssertTrue(current.activeCaptures.isEmpty)
        XCTAssertNotNil(current.captures.first?.deletedAt)
        var staleWatch = original; staleWatch.merge(current)
        XCTAssertNotNil(staleWatch.captures.first?.deletedAt)
        current.setCaptureDeleted(idea.id, deleted: false, writer: "phone")
        staleWatch.merge(current)
        XCTAssertEqual(staleWatch.activeCaptures.count, 1)
    }
    func testLegacyExportsDecodeWithSafeDefaultsAndUnsupportedBackupsFail() throws {
        let ledger = try fixture()
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(ledger)) as! [String: Any]
        var settings = json["settings"] as! [String: Any]
        settings.removeValue(forKey: "showRemainingTime"); settings.removeValue(forKey: "bedtimeMinute"); json["settings"] = settings
        let old = try LedgerBackup.decode(JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(old.ledger.entries, ledger.entries)
        var unsupported = LedgerBackup(ledger: ledger); unsupported.formatVersion = 99
        XCTAssertThrowsError(try LedgerBackup.decode(unsupported.encoded()))
        XCTAssertThrowsError(try LedgerBackup.decode(Data("not a backup".utf8)))
    }
}
