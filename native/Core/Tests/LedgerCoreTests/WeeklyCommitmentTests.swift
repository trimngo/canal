import XCTest
@testable import LedgerCore

final class WeeklyCommitmentTests: XCTestCase {
    private var utc: Calendar { var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(secondsFromGMT: 0)!; return cal }
    private func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
    private var now: Date { date("2026-10-12T11:00:00Z") }
    private func fixture() throws -> Ledger {
        var ledger = Ledger()
        ledger.categories = [LedgerCategory(id: "work", name: "Work"), LedgerCategory(id: "company", name: "Company"), LedgerCategory(id: "music", name: "Music")]
        ledger.settings.inferenceMethod = .carryForward
        ledger.settings.reportingTimeZoneIdentifier = "UTC"
        try ledger.moveCategory("company", to: "work", writer: "test")
        return ledger
    }
    private func add(_ ledger: inout Ledger, _ stamp: String, _ ids: [String], now: Date? = nil) throws {
        try ledger.saveSample(at: date(stamp), activity: ids.isEmpty ? "Uncategorized sample" : ids.joined(separator: "+"), categoryIDs: ids, writer: "test", now: now ?? self.now)
    }

    func testParentDirectTimeAndEqualSplitContributeToWeeklyMinimums() throws {
        var ledger = try fixture()
        try add(&ledger, "2026-10-12T07:00:00Z", ["company"])
        try add(&ledger, "2026-10-12T08:00:00Z", ["work"])
        try add(&ledger, "2026-10-12T09:00:00Z", ["company", "music"])
        try add(&ledger, "2026-10-12T10:00:00Z", ["music"])
        for (id, minimum) in [("work", 120), ("company", 120), ("music", 180)] {
            try ledger.saveWeeklyCommitment(categoryID: id, minimumMinutes: minimum, writer: "test")
        }
        let report = ledger.commitmentWeek(now: now, calendar: utc)
        let rows = Dictionary(uniqueKeysWithValues: report.rows.map { ($0.id, $0) })
        XCTAssertEqual(report.loggedMinutes, 195) // Parent and child commitments never inflate total activity time.
        XCTAssertEqual(rows["work"]?.minutes, 157.5)
        XCTAssertEqual(rows["work"]?.remainingMinutes, 0)
        XCTAssertEqual(rows["work"]?.isMet, true)
        XCTAssertEqual(rows["company"]?.minutes, 97.5)
        XCTAssertEqual(rows["company"]?.remainingMinutes, 22.5)
        XCTAssertEqual(rows["music"]?.minutes, 37.5)
        XCTAssertEqual(rows["music"]?.remainingMinutes, 142.5)
        let before = ledger.entries
        _ = ledger.commitmentWeek(now: now, calendar: utc)
        XCTAssertEqual(ledger.entries, before)
    }

    func testEditsAreIndependentAndDoNotChangePercentageBudgets() throws {
        var ledger = try fixture()
        try ledger.saveTargets(["work": 30, "music": 15], effectiveAt: now, writer: "test")
        try ledger.saveWeeklyCommitment(categoryID: "work", minimumMinutes: 60, writer: "test")
        try ledger.saveWeeklyCommitment(categoryID: "music", minimumMinutes: 30, writer: "test")
        let budgets = ledger.targetBudgets
        try ledger.saveWeeklyCommitment(categoryID: "work", minimumMinutes: 90, writer: "test")
        XCTAssertEqual(ledger.activeWeeklyCommitments.first { $0.id == "work" }?.minimumMinutes, 90)
        XCTAssertEqual(ledger.activeWeeklyCommitments.first { $0.id == "music" }?.minimumMinutes, 30)
        XCTAssertEqual(ledger.targetBudgets, budgets)
        let same = ledger
        try ledger.saveWeeklyCommitment(categoryID: "work", minimumMinutes: 90, writer: "test")
        XCTAssertEqual(ledger, same)
        for value in [0, -1, 10081] {
            XCTAssertThrowsError(try ledger.saveWeeklyCommitment(categoryID: "work", minimumMinutes: value, writer: "test"))
        }
        XCTAssertThrowsError(try ledger.saveWeeklyCommitment(categoryID: "missing", minimumMinutes: 60, writer: "test"))
        XCTAssertEqual(ledger, same)
        // Capacity planning is deferred: independent commitments can exceed a week in total.
        try ledger.saveWeeklyCommitment(categoryID: "work", minimumMinutes: 10080, writer: "test")
        try ledger.saveWeeklyCommitment(categoryID: "music", minimumMinutes: 10080, writer: "test")
        XCTAssertEqual(ledger.activeWeeklyCommitments.count, 2)
    }

    func testCalendarWeekIsMondayThroughSundayNotRollingSevenDays() throws {
        var ledger = try fixture()
        let wednesday = date("2026-10-14T08:00:00Z")
        try add(&ledger, "2026-10-11T07:00:00Z", ["work"], now: wednesday)
        try add(&ledger, "2026-10-12T07:00:00Z", ["work"], now: wednesday)
        try add(&ledger, "2026-10-14T07:00:00Z", ["work"], now: wednesday)
        try ledger.saveWeeklyCommitment(categoryID: "work", minimumMinutes: 60, writer: "test")
        var sundayFirst = utc; sundayFirst.firstWeekday = 1
        let report = ledger.commitmentWeek(now: wednesday, calendar: sundayFirst)
        XCTAssertEqual(report.interval.start, date("2026-10-12T00:00:00Z"))
        XCTAssertEqual(report.interval.end, date("2026-10-19T00:00:00Z"))
        XCTAssertEqual(report.rows.first?.minutes, 30) // Two isolated observations; no invented Tuesday or unsampled evenings.
        let nextWeek = ledger.commitmentWeek(now: date("2026-10-19T09:00:00Z"), calendar: utc)
        XCTAssertEqual(nextWeek.loggedMinutes, 0)
        XCTAssertEqual(nextWeek.rows.first?.remainingMinutes, 60)
        XCTAssertEqual(ledger.entries.count, 3)
    }

    func testMidnightWeekBoundaryStartsAtFirstMondayLogForBothMethods() throws {
        var ledger = try fixture()
        let monday = date("2026-10-12T06:00:00Z")
        try add(&ledger, "2026-10-11T23:00:00Z", ["work"], now: monday)
        try add(&ledger, "2026-10-12T01:00:00Z", ["music"], now: monday)
        for id in ["work", "music"] { try ledger.saveWeeklyCommitment(categoryID: id, minimumMinutes: 600, writer: "test") }
        for method in InferenceMethod.allCases {
            ledger.settings.inferenceMethod = method
            let report = ledger.commitmentWeek(now: monday, calendar: utc)
            XCTAssertEqual(report.loggedMinutes, 15)
            XCTAssertEqual(report.rows.first { $0.id == "work" }?.minutes, 0)
            XCTAssertEqual(report.rows.first { $0.id == "music" }?.minutes, 15)
        }
        let midnight = ledger.commitmentWeek(now: date("2026-10-12T00:00:00Z"), calendar: utc)
        XCTAssertEqual(midnight.loggedMinutes, 0)
    }

    func testReportingTimeZoneAndDaylightSavingWeeksUseElapsedTime() throws {
        for (stamp, first, weekHours, _) in [
            ("2026-10-25T02:00:00Z", "2026-10-24T22:00:00Z", 169.0, 240.0),
            ("2026-03-29T02:00:00Z", "2026-03-28T23:00:00Z", 167.0, 180.0)
        ] {
            var ledger = try fixture(); ledger.settings.reportingTimeZoneIdentifier = "Europe/Berlin"
            let current = date(stamp)
            try add(&ledger, first, ["work"], now: current)
            try ledger.saveWeeklyCommitment(categoryID: "work", minimumMinutes: 600, writer: "test")
            let report = ledger.commitmentWeek(now: current, calendar: utc)
            XCTAssertEqual(report.interval.duration / 3600, weekHours)
            XCTAssertEqual(report.rows.first?.minutes, 7.5)
            XCTAssertEqual(ledger.entries.first?.end, date(first))
        }
    }

    func testMissingAndUncategorizedLogsDoNotInventCommittedTime() throws {
        var ledger = try fixture()
        try ledger.saveWeeklyCommitment(categoryID: "work", minimumMinutes: 60, writer: "test")
        XCTAssertEqual(ledger.commitmentWeek(now: now, calendar: utc).loggedMinutes, 0)
        try add(&ledger, "2026-10-12T07:00:00Z", [])
        let report = ledger.commitmentWeek(now: now, calendar: utc)
        XCTAssertEqual(report.loggedMinutes, 15)
        XCTAssertEqual(report.rows.first?.minutes, 0)
        XCTAssertEqual(report.rows.first?.remainingMinutes, 60)
        XCTAssertEqual(report.rows.first?.isMet, false)
        ledger.setLogDeleted(ledger.entries[0].id, deleted: true, writer: "test")
        XCTAssertEqual(ledger.commitmentWeek(now: now, calendar: utc).loggedMinutes, 0)
    }

    func testRenameMoveAndCategoryDeletionPreserveIdentityAndRawLogs() throws {
        var ledger = try fixture()
        try ledger.saveWeeklyCommitment(categoryID: "company", minimumMinutes: 60, writer: "test")
        try add(&ledger, "2026-10-12T10:00:00Z", ["company"])
        try ledger.saveCategory(id: "company", name: "My business", writer: "test")
        try ledger.moveCategory("company", to: "music", writer: "test")
        let row = try XCTUnwrap(ledger.commitmentWeek(now: now, calendar: utc).rows.first)
        XCTAssertEqual(row.id, "company"); XCTAssertEqual(row.name, "Music › My business"); XCTAssertEqual(row.minutes, 15)
        let raw = ledger.entries[0]
        try ledger.deleteCategory(id: "company", writer: "test")
        XCTAssertTrue(ledger.activeWeeklyCommitments.isEmpty)
        XCTAssertEqual(ledger.weeklyCommitments?.count, 1)
        XCTAssertEqual(ledger.entries[0].end, raw.end); XCTAssertEqual(ledger.entries[0].activity, raw.activity)
        XCTAssertEqual(ledger.allocation(on: now, now: now, calendar: utc).directMinutes["uncategorized"], 15)
    }

    func testBackupWatchAndPartialCloudMergePreserveCommitmentsAndDeletion() throws {
        var phone = try fixture()
        try phone.saveWeeklyCommitment(categoryID: "work", minimumMinutes: 60, writer: "phone")
        let stale = phone
        var watch = try JSONDecoder().decode(Ledger.self, from: JSONEncoder().encode(phone))
        try watch.saveWeeklyCommitment(categoryID: "music", minimumMinutes: 30, writer: "watch")
        try phone.saveWeeklyCommitment(categoryID: "work", minimumMinutes: nil, writer: "phone")
        let original = watch; watch.merge(phone); phone.merge(original)
        XCTAssertEqual(phone, watch)
        phone.merge(stale)
        XCTAssertEqual(phone.activeWeeklyCommitments.map(\.id), ["music"])
        XCTAssertTrue(try XCTUnwrap(phone.weeklyCommitments?.first { $0.id == "work" }).deleted)
        let restored = try LedgerBackup.decode(LedgerBackup(ledger: phone).encoded()).ledger
        XCTAssertEqual(restored, phone)
        var partial = Ledger(); partial.categories = []; partial.weeklyCommitments = restored.weeklyCommitments
        let count = phone.categories.count
        phone.merge(partial)
        XCTAssertEqual(phone.categories.count, count); XCTAssertEqual(phone, restored)
        try phone.saveWeeklyCommitment(categoryID: "work", minimumMinutes: 90, writer: "phone")
        phone.merge(stale)
        XCTAssertEqual(phone.activeWeeklyCommitments.first { $0.id == "work" }?.minimumMinutes, 90)
        XCTAssertGreaterThan(phone.nextRevision(writer: "new").counter, phone.weeklyCommitments!.map(\.revision.counter).max()!)
    }

    func testOldBackupsAndLegacyWatchPayloadsHaveNoCommitmentsWithoutLosingAnything() throws {
        var ledger = try fixture()
        try add(&ledger, "2026-10-12T10:00:00Z", ["company"])
        try ledger.saveTargets(["work": 30], effectiveAt: now, writer: "test")
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(ledger)) as! [String: Any]
        json.removeValue(forKey: "weeklyCommitments")
        let old = try LedgerBackup.decode(JSONSerialization.data(withJSONObject: json)).ledger
        XCTAssertEqual(old, ledger); XCTAssertNil(old.weeklyCommitments)
        try ledger.saveWeeklyCommitment(categoryID: "company", minimumMinutes: 30, writer: "phone")
        ledger.merge(old)
        XCTAssertEqual(ledger.activeWeeklyCommitments.count, 1)
        XCTAssertEqual(ledger.entries, old.entries); XCTAssertEqual(ledger.targetBudgets, old.targetBudgets)
    }

    func testConcurrentEditsOfOneCommitmentConvergeAndDoNotDuplicateIt() throws {
        var a = try fixture(), b = a
        try a.saveWeeklyCommitment(categoryID: "work", minimumMinutes: 30, writer: "a")
        try b.saveWeeklyCommitment(categoryID: "work", minimumMinutes: 60, writer: "b")
        let previousA = a
        a.merge(b); b.merge(previousA)
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.activeWeeklyCommitments.count, 1)
        XCTAssertEqual(a.activeWeeklyCommitments.first?.minimumMinutes, 60)
        let once = a; a.merge(b); XCTAssertEqual(a, once)
    }
}
