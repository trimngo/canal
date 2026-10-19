import XCTest
@testable import LedgerCore

final class AllocationPlannerTests: XCTestCase {
    private var utc: Calendar { var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(secondsFromGMT: 0)!; return cal }
    private func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
    private var now: Date { date("2026-10-17T11:00:00Z") }
    private func fixture() throws -> Ledger {
        var ledger = Ledger(); ledger.categories = [LedgerCategory(id: "work", name: "Work"), LedgerCategory(id: "teaching", name: "Teaching"), LedgerCategory(id: "votion", name: "Votion"), LedgerCategory(id: "music", name: "Music")]
        try ledger.moveCategory("teaching", to: "work", writer: "test")
        try ledger.moveCategory("votion", to: "work", writer: "test")
        return ledger
    }
    func testParentAggregatesDescendantsAndDirectLoggingOnce() throws {
        var ledger = try fixture(); ledger.settings.inferenceMethod = .carryForward
        for (hour, id) in [(7, "teaching"), (8, "votion"), (9, "work"), (10, "music")] {
            try ledger.saveSample(at: date("2026-10-17T\(String(format: "%02d", hour)):00:00Z"), activity: id, categoryIDs: [id], writer: "test", now: now)
        }
        let period = ledger.allocation(on: now, now: now, calendar: utc)
        XCTAssertEqual(period.trackedMinutes, 240)
        XCTAssertEqual(period.total(for: "work", ledger: ledger), 180)
        XCTAssertEqual(period.directMinutes["work"], 60)
        XCTAssertEqual(period.total(for: "teaching", ledger: ledger), 60)
        XCTAssertEqual(ledger.breakdown(on: now, now: now, calendar: utc).reduce(0) { $0 + $1.minutes }, 240)
        XCTAssertEqual(ledger.groupEntryCounts(now: now)["work"], 3)
    }
    func testEqualSplitSiblingsAndCrossParentCategories() throws {
        var ledger = try fixture()
        try ledger.saveSample(at: now.addingTimeInterval(-3600), activity: "Two things", categoryIDs: ["teaching", "music", "music"], writer: "test", now: now)
        let period = ledger.allocation(on: now, now: now, calendar: utc)
        XCTAssertEqual(period.directMinutes["teaching"], 30)
        XCTAssertEqual(period.directMinutes["music"], 30)
        XCTAssertEqual(period.total(for: "work", ledger: ledger), 30)
        XCTAssertEqual(period.directMinutes.values.reduce(0, +), 60)
        XCTAssertNoThrow(try ledger.validateCategories(["teaching", "votion"]))
        XCTAssertThrowsError(try ledger.validateCategories(["work", "teaching"]))
        XCTAssertEqual(ledger.categoryConflicts("work", with: ["music", "teaching"]), ["teaching"])
    }
    func testInvalidSelectionDoesNotAlterExistingLog() throws {
        var ledger = try fixture()
        try ledger.saveSample(id: "sample", at: now, activity: "Original", categoryIDs: ["music"], writer: "test", now: now)
        let before = ledger
        XCTAssertThrowsError(try ledger.saveSample(id: "sample", at: now, activity: "Bad", categoryIDs: ["work", "teaching"], writer: "test", now: now))
        XCTAssertEqual(ledger, before)
    }
    func testMovesRetainIdentityPreventCyclesAndConflictingHistoricalSplits() throws {
        var ledger = try fixture()
        XCTAssertThrowsError(try ledger.moveCategory("work", to: "teaching", writer: "test"))
        XCTAssertThrowsError(try ledger.moveCategory("music", to: "music", writer: "test"))
        try ledger.saveSample(at: now, activity: "Shared", categoryIDs: ["work", "music"], writer: "test", now: now)
        let before = ledger
        XCTAssertThrowsError(try ledger.moveCategory("music", to: "work", writer: "test"))
        XCTAssertEqual(ledger, before)
        try ledger.moveCategory("teaching", to: "music", writer: "test")
        XCTAssertTrue(ledger.descendants(of: "music").contains { $0.id == "teaching" })
        XCTAssertEqual(ledger.categories.count, 4)
    }
    func testConcurrentMovesConvergeWithoutCyclesOrDoubleCounting() throws {
        var a = try fixture(), b = a
        try a.moveCategory("work", to: "music", writer: "a")
        try b.moveCategory("music", to: "work", writer: "b")
        let originalA = a; a.merge(b); b.merge(originalA)
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.orderedCategories.count, a.categories.count)
        XCTAssertFalse(a.children(of: nil).isEmpty)
    }
    func testDeletionKeepsRawLogsPromotesChildrenAndPreservesSplitShare() throws {
        var ledger = try fixture()
        try ledger.saveTargets(["work": 30, "music": 15], effectiveAt: now.addingTimeInterval(-3600), writer: "test")
        try ledger.saveSample(at: now.addingTimeInterval(-3600), activity: "Both", categoryIDs: ["work", "music"], writer: "test", now: now)
        let timestamp = ledger.entries[0].end, id = ledger.entries[0].id
        try ledger.deleteCategory(id: "work", writer: "test")
        XCTAssertEqual(ledger.entries[0].end, timestamp); XCTAssertEqual(ledger.entries[0].id, id)
        XCTAssertNil(ledger.categoryParents["teaching"])
        let period = ledger.allocation(on: now, now: now, calendar: utc)
        XCTAssertEqual(period.directMinutes["music"], 30)
        XCTAssertEqual(period.directMinutes["uncategorized"], 30)
        var stale = try fixture(); stale.merge(ledger); ledger.merge(stale)
        XCTAssertEqual(ledger.allocation(on: now, now: now, calendar: utc), period)
    }
    func testIndependentTargetsRemainderValidationAndHistoricalVersions() throws {
        var ledger = try fixture()
        let earlier = now.addingTimeInterval(-86400)
        try ledger.saveTargets(["work": 30, "music": 15], effectiveAt: earlier, writer: "test")
        var targets = ledger.currentTargets(at: now); targets["music"] = 20
        try ledger.saveTargets(targets, effectiveAt: now, writer: "test")
        XCTAssertEqual(ledger.currentTargets(at: now)["work"], 30)
        XCTAssertEqual(ledger.currentBudget(at: now)?.unallocated, 50)
        XCTAssertEqual(ledger.currentBudget(at: earlier)?.percentages["music"], 15)
        XCTAssertEqual(ledger.targetBudgets?.count, 2)
        let before = ledger
        XCTAssertThrowsError(try ledger.saveTargets(["work": 90, "music": 20], effectiveAt: now, writer: "test"))
        XCTAssertThrowsError(try ledger.saveTargets(["teaching": 20], effectiveAt: now, writer: "test"))
        XCTAssertThrowsError(try Ledger.validateTargets(["work": .nan]))
        XCTAssertThrowsError(try Ledger.validateTargets(["work": -1]))
        XCTAssertEqual(ledger, before)
        try ledger.saveTargets([:], effectiveAt: now.addingTimeInterval(1), writer: "test")
        XCTAssertEqual(ledger.currentBudget(at: now.addingTimeInterval(1))?.unallocated, 100)
    }
    func testMidpointAndCarryForwardStartAtFirstLogAndCapToday() throws {
        var ledger = try fixture()
        try ledger.saveSample(at: date("2026-10-17T09:00:00Z"), activity: "Teaching", categoryIDs: ["teaching"], writer: "test", now: now)
        try ledger.saveSample(at: date("2026-10-17T10:00:00Z"), activity: "Music", categoryIDs: ["music"], writer: "test", now: now)
        var segments = ledger.inferredSegments(on: now, now: now, calendar: utc)
        XCTAssertEqual(segments.first?.start, date("2026-10-17T09:00:00Z"))
        XCTAssertEqual(segments.first?.end, date("2026-10-17T09:30:00Z"))
        XCTAssertEqual(segments.last?.end, now)
        segments = ledger.inferredSegments(on: now, now: now, calendar: utc, method: .carryForward)
        XCTAssertEqual(segments.first?.minutes, 60)
        let completed = ledger.allocation(on: now, now: now.addingTimeInterval(86400), calendar: utc)
        XCTAssertEqual(completed.trackedMinutes, 900)
        XCTAssertEqual(completed.directMinutes.values.reduce(0, +), 900)
        XCTAssertEqual(ledger.allocation(on: now, now: date("2026-10-17T06:00:00Z"), calendar: utc).trackedMinutes, 0)
    }
    func testRollingSevenCalendarDaysUseWeightedTrackedHoursAndExcludeEmptyDays() throws {
        var ledger = try fixture()
        try ledger.saveSample(at: date("2026-10-16T09:00:00Z"), activity: "Work", categoryIDs: ["work"], writer: "test", now: now)
        try ledger.saveSample(at: now.addingTimeInterval(-3600), activity: "Music", categoryIDs: ["music"], writer: "test", now: now)
        try ledger.saveSample(at: date("2026-10-10T10:00:00Z"), activity: "Outside window", categoryIDs: ["music"], writer: "test", now: now)
        let period = ledger.rollingAllocation(now: now, calendar: utc)
        XCTAssertEqual(period.representedDays, 2); XCTAssertEqual(period.requestedDays, 7)
        XCTAssertEqual(period.trackedMinutes, 960)
        XCTAssertEqual(period.percent(period.directMinutes["work", default: 0]), 900.0 / 960 * 100, accuracy: 0.0001)
        XCTAssertFalse(ledger.allocation(on: date("2026-10-15T11:00:00Z"), now: now, calendar: utc).sufficient)
        XCTAssertEqual(ledger.history(range: .week, now: now, calendar: utc).trackedMinutes, period.trackedMinutes)
    }
    func testUncategorizedDaysAreSufficientAndCoincidentSamplesCountOnce() throws {
        var ledger = Ledger()
        try ledger.saveSample(at: now.addingTimeInterval(-3600), activity: "First", categoryIDs: ["work"], writer: "test", now: now)
        try ledger.saveSample(at: now.addingTimeInterval(-3600), activity: "Correction", categoryIDs: [], writer: "test", now: now)
        let period = ledger.allocation(on: now, now: now, calendar: utc)
        XCTAssertEqual(ledger.entries.count, 2)
        XCTAssertEqual(period.representedDays, 1)
        XCTAssertEqual(period.directMinutes["uncategorized"], 60)
        XCTAssertEqual(period.directMinutes.values.reduce(0, +), 60)
    }
    func testMidnightStartsANewDayWithoutCarryingPreviousDayActivity() throws {
        var ledger = Ledger()
        let morning = date("2026-10-18T02:00:00Z"), previous = date("2026-10-17T12:00:00Z")
        try ledger.saveSample(at: date("2026-10-17T23:00:00Z"), activity: "Evening", categoryIDs: ["leisure"], writer: "test", now: morning)
        try ledger.saveSample(at: date("2026-10-18T01:00:00Z"), activity: "Night work", categoryIDs: ["work"], writer: "test", now: morning)
        XCTAssertEqual(ledger.reportingDay(containing: morning, calendar: utc), date("2026-10-18T00:00:00Z"))
        XCTAssertEqual(ledger.allocation(on: previous, now: morning, calendar: utc).trackedMinutes, 60)
        XCTAssertEqual(ledger.allocation(on: morning, now: morning, calendar: utc).trackedMinutes, 60)
        XCTAssertEqual(ledger.history(range: .today, now: morning, calendar: utc).rows.map(\.id), ["work"])
    }

    func testDSTAndPinnedTimeZoneUseRealElapsedMinutesAndKeepTimestamps() throws {
        var ledger = Ledger(); ledger.settings.reportingTimeZoneIdentifier = "Europe/Berlin"
        for (day, expected) in [("2026-03-29T12:00:00Z", 1380.0), ("2026-10-25T12:00:00Z", 1500.0)] {
            let bounds = try XCTUnwrap(ledger.dayBounds(on: date(day), calendar: utc))
            XCTAssertEqual(bounds.duration / 60, expected)
            try ledger.saveSample(at: bounds.start, activity: "Observation", categoryIDs: [], writer: "test", now: bounds.end)
            XCTAssertEqual(ledger.allocation(on: bounds.start, now: bounds.end, calendar: utc).trackedMinutes, expected)
            XCTAssertTrue(ledger.entries.contains { $0.end == bounds.start })
        }
    }

    func testLegacySingleCategoryMigrationAndBackupSyncRetainAllPlannerData() throws {
        var ledger = try fixture()
        ledger.entries = [CheckIn(end: now, activity: "Legacy", categoryID: "teaching", revision: Revision(counter: 10, writer: "old"))]
        let oldID = ledger.entries[0].id
        let decoded = try JSONDecoder().decode(Ledger.self, from: JSONEncoder().encode(ledger))
        XCTAssertEqual(decoded.confirmedCategoryIDs(for: decoded.entries[0]), ["teaching"])
        XCTAssertEqual(decoded.entries[0].id, oldID)
        try ledger.saveSample(id: oldID, at: now, activity: "Legacy", categoryIDs: ["teaching", "music"], writer: "phone", now: now)
        try ledger.saveTargets(["work": 30, "music": 15], effectiveAt: now, writer: "phone")
        let restored = try LedgerBackup.decode(LedgerBackup(ledger: ledger).encoded()).ledger
        XCTAssertEqual(restored, ledger)
        var watch = decoded; watch.merge(restored); ledger.merge(watch)
        XCTAssertEqual(watch, ledger)
        XCTAssertEqual(ledger.entries[0].id, oldID)
        XCTAssertEqual(ledger.confirmedCategoryIDs(for: ledger.entries[0]), ["music", "teaching"])
        let once = watch; watch.merge(restored); XCTAssertEqual(watch, once)
        XCTAssertEqual(ledger.targetBudgets?.count, 1)
    }
    func testAllSevenDaysAreRepresentedAndOlderSamplesCannotFillMissingDays() throws {
        var ledger = Ledger()
        for offset in -7...0 {
            let stamp = utc.date(byAdding: .day, value: offset, to: now.addingTimeInterval(-3600))!
            try ledger.saveSample(at: stamp, activity: "Work", categoryIDs: ["work"], writer: "test", now: now)
        }
        let period = ledger.rollingAllocation(now: now, calendar: utc)
        XCTAssertEqual(period.representedDays, 7)
        XCTAssertEqual(period.trackedMinutes, 6 * 840 + 60)
        XCTAssertEqual(period.percent(period.directMinutes["work", default: 0]), 100)
        for entry in ledger.activeEntries where utc.isDate(entry.end, inSameDayAs: now) { ledger.setLogDeleted(entry.id, deleted: true, writer: "test") }
        XCTAssertFalse(ledger.allocation(on: now, now: now, calendar: utc).sufficient)
        XCTAssertEqual(ledger.rollingAllocation(now: now, calendar: utc).representedDays, 6)
    }
    func testMovingTargetedCategoryVersionsBudgetAndKeepsOtherTargets() throws {
        var ledger = try fixture()
        let effective = Date().addingTimeInterval(-60)
        try ledger.saveTargets(["work": 30, "music": 15], effectiveAt: effective, writer: "test")
        try ledger.moveCategory("work", to: "music", writer: "test")
        XCTAssertEqual(ledger.currentTargets(), ["music": 15])
        XCTAssertEqual(ledger.currentBudget(at: effective)?.percentages, ["work": 30, "music": 15])
        XCTAssertEqual(ledger.targetBudgets?.count, 2)
    }
    func testConcurrentBudgetRecordsConvergeAndPartialCloudMergePreservesCategories() throws {
        var a = try fixture(), b = a
        try a.saveTargets(["work": 30], effectiveAt: now, writer: "a")
        try b.saveTargets(["music": 15], effectiveAt: now, writer: "b")
        let originalB = b; b.merge(a); a.merge(originalB)
        XCTAssertEqual(a, b); XCTAssertEqual(a.targetBudgets?.count, 2)
        XCTAssertEqual(a.currentTargets(at: now), b.currentTargets(at: now))
        var partial = Ledger(); partial.categories = []; partial.targetBudgets = [try XCTUnwrap(a.targetBudgets?.first)]
        a.merge(partial)
        XCTAssertEqual(a.categories.count, 4); XCTAssertEqual(a.targetBudgets?.count, 2)
    }

    func testOldJSONMissingPlannerFieldsUsesSafeDefaultsWithoutChangingRawLog() throws {
        var ledger = Ledger()
        ledger.entries = [CheckIn(end: now.addingTimeInterval(-3600), activity: "Existing", categoryID: "work", revision: Revision(counter: 1, writer: "old"))]
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(ledger)) as! [String: Any]
        for key in ["targetBudgets", "wakingOverrides"] { json.removeValue(forKey: key) }
        var settings = json["settings"] as! [String: Any]
        for key in ["wakeUpMinute", "wakingTimeZoneIdentifier"] { settings.removeValue(forKey: key) }
        json["settings"] = settings
        let restored = try LedgerBackup.decode(JSONSerialization.data(withJSONObject: json)).ledger
        XCTAssertEqual(restored.entries, ledger.entries)
        XCTAssertNil(restored.targetBudgets); XCTAssertNil(restored.settings.reportingTimeZoneIdentifier)
        XCTAssertEqual(restored.allocation(on: now, now: now, calendar: utc).directMinutes["work"], 60)
    }

}
