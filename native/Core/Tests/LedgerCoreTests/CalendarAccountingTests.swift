import XCTest
@testable import LedgerCore

final class CalendarAccountingTests: XCTestCase {
    private var utc: Calendar { var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(secondsFromGMT: 0)!; return cal }
    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }

    func testEarlyAndLateSamplesContributeForBothMethods() throws {
        let now = date("2026-10-19T23:30:00Z")
        var ledger = Ledger()
        for (stamp, category) in [("01:00", "work"), ("03:00", "social"), ("23:00", "leisure")] {
            try ledger.saveSample(at: date("2026-10-19T\(stamp):00Z"), activity: category, categoryID: category, writer: "test", now: now)
        }
        for method in InferenceMethod.allCases {
            ledger.settings.inferenceMethod = method
            let period = ledger.allocation(on: now, now: now, calendar: utc)
            let report = ledger.history(range: .today, now: now, calendar: utc)
            XCTAssertEqual(ledger.daySamples(on: now, now: now, calendar: utc).count, 3)
            XCTAssertEqual(report.samples.count, 3)
            XCTAssertEqual(period.trackedMinutes, 1350)
            XCTAssertEqual(report.trackedMinutes, 1350)
            XCTAssertEqual(period.directMinutes["work"], method == .midpoint ? 60 : 120)
            XCTAssertEqual(period.directMinutes["social"], method == .midpoint ? 660 : 1200)
            XCTAssertEqual(period.directMinutes["leisure"], method == .midpoint ? 630 : 30)
            XCTAssertEqual(report.rows.reduce(0) { $0 + $1.percent }, 100, accuracy: 0.00001)
            XCTAssertEqual(report.dailyTotals.reduce(0) { $0 + $1.minutes }, 1350)
        }
    }

    func testMidnightIsExclusiveForCompletedDaysAndInclusiveForToday() throws {
        let now = date("2026-10-19T00:15:00Z"), previous = date("2026-10-18T00:00:00Z")
        var ledger = Ledger(); ledger.settings.inferenceMethod = .carryForward
        for (stamp, category) in [("2026-10-18T00:00:00Z", "work"), ("2026-10-18T23:59:00Z", "leisure"), ("2026-10-19T00:00:00Z", "social")] {
            try ledger.saveSample(at: date(stamp), activity: category, categoryID: category, writer: "test", now: now)
        }
        let completed = ledger.allocation(on: previous, now: now, calendar: utc)
        XCTAssertEqual(completed.trackedMinutes, 1440)
        XCTAssertEqual(completed.directMinutes["leisure"], 1)
        let today = ledger.history(range: .today, now: now, calendar: utc)
        XCTAssertEqual(today.samples.count, 1)
        XCTAssertEqual(today.rows.first?.id, "social")
        XCTAssertEqual(today.trackedMinutes, 15)
        let custom = ledger.history(range: .custom, start: previous, end: previous, now: now, calendar: utc)
        XCTAssertEqual(custom.samples.count, 2)
        XCTAssertEqual(custom.end, date("2026-10-19T00:00:00Z"))
    }

    func testSevenDaysIncludeEarlyAndLateLogsWithoutFillingMissingDays() throws {
        let now = date("2026-10-19T02:00:00Z")
        var ledger = Ledger()
        for (stamp, category) in [("2026-10-12T23:00:00Z", "leisure"), ("2026-10-18T23:00:00Z", "work"), ("2026-10-19T01:00:00Z", "social")] {
            try ledger.saveSample(at: date(stamp), activity: category, categoryID: category, writer: "test", now: now)
        }
        let period = ledger.rollingAllocation(now: now, calendar: utc)
        XCTAssertEqual(period.representedDays, 2)
        XCTAssertEqual(period.trackedMinutes, 120)
        XCTAssertEqual(period.percent(period.directMinutes["work", default: 0]), 50)
        let report = ledger.history(range: .week, now: now, calendar: utc)
        XCTAssertEqual(report.trackedMinutes, period.trackedMinutes)
        XCTAssertEqual(Set(report.dailyTotals.map(\.day)).count, 2)
        XCTAssertEqual(Set(report.rows.map(\.id)), ["work", "social"])
    }

    func testLegacySleepSettingsAndOverridesAreIgnoredWithoutLosingData() throws {
        let now = date("2026-10-19T05:00:00Z")
        var ledger = Ledger()
        ledger.settings.reportingTimeZoneIdentifier = "Europe/Berlin"
        try ledger.saveSample(at: now.addingTimeInterval(-3600), activity: "Before old wake time", categoryIDs: ["work", "social"], writer: "watch", now: now)
        try ledger.addCapture(text: "Original idea", id: "idea", writer: "phone", now: now)
        try ledger.saveTargets(["work": 30], effectiveAt: now, writer: "phone")
        try ledger.saveWeeklyCommitment(categoryID: "work", minimumMinutes: 60, writer: "phone")
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(ledger)) as! [String: Any]
        var settings = json["settings"] as! [String: Any]
        settings["wakeUpMinute"] = 600; settings["bedtimeMinute"] = 660; settings["showRemainingTime"] = true
        json["settings"] = settings
        json["wakingOverrides"] = [["id": "2026-10-19", "wakeMinute": 900, "bedMinute": 960, "reset": false, "revision": ["counter": 8, "writer": "legacy"]]]
        let restored = try LedgerBackup.decode(JSONSerialization.data(withJSONObject: json)).ledger
        XCTAssertEqual(restored, ledger)
        XCTAssertEqual(restored.settings.reportingTimeZoneIdentifier, "Europe/Berlin")
        let report = restored.history(range: .today, now: now, calendar: utc)
        XCTAssertEqual(report.samples, ledger.entries)
        XCTAssertEqual(report.trackedMinutes, 60)
        XCTAssertTrue(report.rows.allSatisfy { abs($0.percent - 50) < 0.00001 })
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(restored)) as! [String: Any]
        let savedSettings = encoded["settings"] as! [String: Any]
        for key in ["wakeUpMinute", "bedtimeMinute", "showRemainingTime"] { XCTAssertNil(savedSettings[key]) }
        XCTAssertNil(encoded["wakingOverrides"])
        XCTAssertEqual(savedSettings["wakingTimeZoneIdentifier"] as? String, "Europe/Berlin")
        var watch = try JSONDecoder().decode(Ledger.self, from: JSONEncoder().encode(restored))
        try watch.saveSample(at: now.addingTimeInterval(-60), activity: "New watch sample", categoryID: "work", writer: "watch", now: now)
        var phone = restored; phone.merge(watch); watch.merge(phone)
        XCTAssertEqual(phone, watch)
        XCTAssertEqual(phone.entries.count, 2)
        XCTAssertEqual(try LedgerBackup.decode(LedgerBackup(ledger: phone).encoded()).ledger, phone)
    }

    func testNotificationWindowCannotFilterTimeAccounting() throws {
        let now = date("2026-10-19T02:00:00Z")
        var ledger = Ledger()
        var settings = ledger.settings; settings.startMinute = 420; settings.endMinute = 1320
        try ledger.saveSettings(settings, writer: "phone")
        try ledger.saveSample(at: now.addingTimeInterval(-3600), activity: "Night log", categoryID: nil, writer: "watch", now: now)
        XCTAssertEqual(ledger.allocation(on: now, now: now, calendar: utc).directMinutes["uncategorized"], 60)
        XCTAssertEqual(ledger.history(range: .today, now: now, calendar: utc).rows.first?.percent, 100)
    }
}
