import XCTest
@testable import LedgerCore

final class LedgerTests: XCTestCase {
    func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
    var utc: Calendar { var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!; return calendar }

    func testDefaultScheduleHasSixtyOneInstantaneousPrompts() throws {
        let minutes = try Settings().notificationMinutes()
        XCTAssertEqual(minutes.count, 61)
        XCTAssertEqual(minutes.first, 420)
        XCTAssertEqual(minutes.last, 1320)
    }

    func testExcessiveAndOvernightSchedulesRejected() {
        var settings = Settings(); settings.startMinute = 0
        XCTAssertThrowsError(try settings.notificationMinutes())
        settings.startMinute = 1320; settings.endMinute = 420
        XCTAssertThrowsError(try settings.notificationMinutes())
    }

    func testAnytimeSamplesKeepPreciseTimestampsAndDistinctIdentity() throws {
        var ledger = Ledger(); let time = date("2026-10-14T10:03:12Z")
        try ledger.saveSample(at: time, activity: "Preparing classes", categoryID: "work", writer: "phone", now: time)
        try ledger.saveSample(at: time, activity: "Second observation", categoryID: nil, writer: "phone", now: time)
        XCTAssertEqual(ledger.entries.count, 2)
        XCTAssertNotEqual(ledger.entries[0].id, ledger.entries[1].id)
        XCTAssertEqual(ledger.entries[0].end, time)
    }

    func testMidpointUsesHalfwayTransitionAndTrackedTimePercentages() throws {
        var ledger = Ledger(); let first = date("2026-10-14T10:00:00Z")
        let second = date("2026-10-14T10:30:00Z"), now = date("2026-10-14T11:00:00Z")
        try ledger.saveSample(at: first, activity: "Preparing classes", categoryID: "work", writer: "phone", now: now)
        try ledger.saveSample(at: second, activity: "Lunch", categoryID: "personal", writer: "phone", now: now)
        let original = ledger.entries
        let segments = ledger.inferredSegments(on: now, now: now, calendar: utc)
        XCTAssertEqual(segments[0].start, date("2026-10-14T07:00:00Z"))
        XCTAssertEqual(segments[0].end, date("2026-10-14T10:15:00Z"))
        XCTAssertEqual(segments[1].start, segments[0].end)
        XCTAssertEqual(segments[1].end, now)
        let rows = ledger.breakdown(on: now, now: now, calendar: utc)
        XCTAssertEqual(rows.first { $0.id == "work" }?.minutes, 195)
        XCTAssertEqual(rows.first { $0.id == "personal" }?.minutes, 45)
        XCTAssertEqual(rows.first { $0.id == "work" }!.percent, 81.25, accuracy: 0.0001)
        XCTAssertNil(rows.first { $0.id == "unlogged" })
        XCTAssertEqual(rows.reduce(0) { $0 + $1.percent }, 100, accuracy: 0.0001)
        XCTAssertEqual(ledger.entries, original)
    }

    func testIrregularSamplesAndBackdatedInsertionAreOrderedCorrectly() throws {
        var ledger = Ledger(); let now = date("2026-10-14T10:30:00Z")
        try ledger.saveSample(at: date("2026-10-14T10:18:44Z"), activity: "Lunch", categoryID: nil, writer: "phone", now: now)
        try ledger.saveSample(at: date("2026-10-14T10:03:12Z"), activity: "Work", categoryID: "work", writer: "phone", now: now)
        let segments = ledger.inferredSegments(on: now, now: now, calendar: utc)
        XCTAssertEqual(segments.first?.end, date("2026-10-14T10:10:58Z"))
        XCTAssertEqual(segments[0].minutes, 190 + 58.0 / 60, accuracy: 0.0001)
        XCTAssertEqual(segments[1].minutes, 19 + 2.0 / 60, accuracy: 0.0001)
    }

    func testMethodChangeRecalculatesWithoutChangingRawSamples() throws {
        var ledger = Ledger(); let now = date("2026-10-14T11:00:00Z")
        try ledger.saveSample(at: date("2026-10-14T10:00:00Z"), activity: "Work", categoryID: "work", writer: "phone", now: now)
        try ledger.saveSample(at: date("2026-10-14T10:30:00Z"), activity: "Lunch", categoryID: "personal", writer: "phone", now: now)
        let original = ledger.entries
        var settings = ledger.settings; settings.inferenceMethod = .carryForward
        try ledger.saveSettings(settings, writer: "phone")
        let rows = ledger.breakdown(on: now, now: now, calendar: utc)
        XCTAssertEqual(rows.first { $0.id == "work" }?.minutes, 210)
        XCTAssertEqual(rows.first { $0.id == "personal" }?.minutes, 30)
        XCTAssertEqual(ledger.entries, original)
    }

    func testFirstSampleExtendsToWakeUpAndLastStopsAtNow() throws {
        var ledger = Ledger(); let now = date("2026-10-14T14:00:00Z")
        let first = date("2026-10-14T10:00:00Z")
        try ledger.saveSample(at: first, activity: "Work", categoryID: "work", writer: "phone", now: now)
        let segments = ledger.inferredSegments(on: now, now: now, calendar: utc)
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].start, date("2026-10-14T07:00:00Z"))
        XCTAssertEqual(segments[0].end, now)
        XCTAssertEqual(segments[0].minutes, 420)
        XCTAssertEqual(ledger.breakdown(on: now, now: now, calendar: utc).first { $0.id == "work" }?.percent, 100)
    }

    func testCoincidentSamplesRemainStoredButDoNotDoubleCount() throws {
        var ledger = Ledger(); let first = date("2026-10-14T10:00:00Z"), now = date("2026-10-14T11:00:00Z")
        try ledger.saveSample(at: first, activity: "Work", categoryID: "work", writer: "phone", now: now)
        try ledger.saveSample(at: first, activity: "Correction", categoryID: "personal", writer: "phone", now: now)
        let rows = ledger.breakdown(on: now, now: now, calendar: utc)
        XCTAssertEqual(ledger.entries.count, 2)
        XCTAssertEqual(rows.first { $0.id == "work" }?.minutes, 0)
        XCTAssertEqual(rows.first { $0.id == "personal" }?.minutes, 240)
        XCTAssertEqual(rows.reduce(0) { $0 + $1.percent }, 100, accuracy: 0.0001)
    }

    func testEditingSampleTimeAndCategoryKeepsIdentityAndDoesNotDuplicate() throws {
        var ledger = Ledger(); let now = date("2026-10-14T11:00:00Z")
        try ledger.saveSample(at: date("2026-10-14T10:00:00Z"), activity: "Planning", categoryID: nil, writer: "phone", now: now)
        let id = ledger.entries[0].id
        let corrected = date("2026-10-14T10:10:00Z")
        try ledger.saveSample(id: id, at: corrected, activity: "Class planning", categoryID: "work", writer: "phone", now: now)
        XCTAssertEqual(ledger.entries.count, 1)
        XCTAssertEqual(ledger.entries[0].id, id)
        XCTAssertEqual(ledger.entries[0].end, corrected)
        XCTAssertEqual(ledger.breakdown(on: now, now: now, calendar: utc).first { $0.id == "work" }?.minutes, 240)
    }

    func testMidnightSampleBelongsToNewDayAndCompletedDayEndsAtBedtime() throws {
        var ledger = Ledger(); let previous = date("2026-10-14T21:17:00Z")
        let midnight = date("2026-10-15T00:00:00Z"), now = date("2026-10-15T08:00:00Z")
        try ledger.saveSample(at: previous, activity: "Rest", categoryID: "rest", writer: "phone", now: now)
        let last = date("2026-10-14T21:47:00Z")
        try ledger.saveSample(at: last, activity: "Rest", categoryID: "rest", writer: "phone", now: now)
        try ledger.saveSample(at: midnight, activity: "Sleeping", categoryID: "rest", writer: "phone", now: now)
        XCTAssertEqual(ledger.entries(on: previous, calendar: utc).count, 2)
        XCTAssertEqual(ledger.entries(on: midnight, calendar: utc).count, 1)
        let segments = ledger.inferredSegments(on: previous, now: now, calendar: utc)
        XCTAssertEqual(segments.last?.end, date("2026-10-14T22:00:00Z"))
        XCTAssertEqual(segments.reduce(0) { $0 + $1.minutes }, 900)
    }

    func testTodayExtendsToWakeUpWithoutUsingPreviousDaysSamples() throws {
        var ledger = Ledger(); let now = date("2026-10-15T08:00:00Z")
        try ledger.saveSample(at: date("2026-10-14T23:00:00Z"), activity: "Rest", categoryID: "rest", writer: "phone", now: now)
        let firstToday = date("2026-10-15T07:30:00Z")
        try ledger.saveSample(at: firstToday, activity: "Breakfast", categoryID: "personal", writer: "phone", now: now)
        let segments = ledger.inferredSegments(on: now, now: now, calendar: utc)
        XCTAssertEqual(segments.first?.start, date("2026-10-15T07:00:00Z"))
        XCTAssertEqual(segments.first?.minutes, 60)
    }

    func testFutureObservationsAreNotUsedForEarlierSnapshot() throws {
        var ledger = Ledger(); let recordedNow = date("2026-10-14T14:00:00Z")
        try ledger.saveSample(at: date("2026-10-14T10:00:00Z"), activity: "Work", categoryID: "work", writer: "phone", now: recordedNow)
        try ledger.saveSample(at: date("2026-10-14T13:00:00Z"), activity: "Lunch", categoryID: "personal", writer: "phone", now: recordedNow)
        let now = date("2026-10-14T12:00:00Z")
        let rows = ledger.breakdown(on: now, now: now, calendar: utc)
        XCTAssertEqual(rows.first { $0.id == "work" }?.minutes, 300)
        XCTAssertEqual(rows.first { $0.id == "personal" }?.minutes, 0)
    }

    func testEmptyDayAndInboxCapturesDoNotCreateEstimatedTime() throws {
        var ledger = Ledger(); let now = date("2026-10-14T12:00:00Z")
        try ledger.addCapture(text: "Buy milk", writer: "phone", now: now)
        let rows = ledger.breakdown(on: now, now: now, calendar: utc)
        XCTAssertEqual(rows.first { $0.id == "work" }?.minutes, 0)
        XCTAssertEqual(rows.reduce(0) { $0 + $1.percent }, 0)
        XCTAssertFalse(rows.contains { $0.id == "unlogged" })
    }

    func testFutureNonfiniteAndEmptySamplesRejected() {
        var ledger = Ledger(); let now = date("2026-10-14T10:00:00Z")
        XCTAssertThrowsError(try ledger.saveSample(at: now.addingTimeInterval(1), activity: "Future", categoryID: nil, writer: "phone", now: now))
        XCTAssertThrowsError(try ledger.saveSample(at: Date(timeIntervalSince1970: .infinity), activity: "Invalid", categoryID: nil, writer: "phone", now: now))
        XCTAssertThrowsError(try ledger.saveSample(at: now, activity: " ", categoryID: nil, writer: "phone", now: now))
    }

    func testCategoryRenamePreservesAssignments() throws {
        var ledger = Ledger(); let now = date("2026-10-14T10:00:00Z")
        try ledger.saveSample(at: now, activity: "Prep", categoryID: "work", writer: "phone", now: now)
        try ledger.saveCategory(id: "work", name: "Teaching", writer: "phone")
        XCTAssertEqual(ledger.breakdown(on: now, now: now, calendar: utc).first { $0.id == "work" }?.name, "Teaching")
        XCTAssertEqual(ledger.entries.first?.categoryID, "work")
        XCTAssertThrowsError(try ledger.saveCategory(id: nil, name: " teaching ", writer: "phone"))
    }

    func testMergePreservesOfflineCapturesAndNewerEdits() throws {
        var phone = Ledger(), watch = Ledger(); let now = date("2026-10-14T10:00:00Z")
        try phone.saveSample(at: now, activity: "Original", categoryID: nil, writer: "phone", now: now)
        watch.merge(phone)
        try watch.saveSample(id: phone.entries[0].id, at: now, activity: "Edited on Watch", categoryID: "work", writer: "watch", now: now)
        try phone.addCapture(text: "Phone thought", writer: "phone")
        try watch.addCapture(text: "Watch thought", writer: "watch")
        phone.merge(watch); watch.merge(phone)
        XCTAssertEqual(phone, watch)
        XCTAssertEqual(phone.entries.count, 1)
        XCTAssertEqual(phone.entries.first?.activity, "Edited on Watch")
        XCTAssertEqual(phone.captures.count, 2)
    }

    func testMergeIsIdempotentAndResolvesConcurrentSampleEditsConsistently() throws {
        var a = Ledger(), b = Ledger(); let now = date("2026-10-14T10:00:00Z")
        try a.saveSample(id: "shared-sample", at: now, activity: "A", categoryID: nil, writer: "a", now: now)
        try b.saveSample(id: "shared-sample", at: now, activity: "B", categoryID: nil, writer: "b", now: now)
        let originalA = a; a.merge(b); b.merge(originalA)
        XCTAssertEqual(a, b)
        let once = a; a.merge(b); XCTAssertEqual(a, once)
    }

    func testDaylightSavingDaysStillHaveOneHundredPercentTotal() throws {
        var calendar = utc; calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        for (day, expected) in [
            ("2026-03-29T12:00:00Z", 1379.0),
            ("2026-10-25T12:00:00Z", 1499.0)
        ] {
            var ledger = Ledger(); ledger.settings.wakeUpMinute = 0; ledger.settings.bedtimeMinute = 1439; let target = date(day)
            let start = calendar.startOfDay(for: target)
            let cutoff = calendar.date(byAdding: .day, value: 1, to: start)!.addingTimeInterval(-60)
            try ledger.saveSample(at: start, activity: "Rest", categoryID: "rest", writer: "phone", now: cutoff)
            let rows = ledger.breakdown(on: target, now: cutoff, calendar: calendar)
            XCTAssertEqual(rows.first { $0.id == "rest" }?.minutes, expected)
            XCTAssertEqual(rows.reduce(0) { $0 + $1.percent }, 100, accuracy: 0.0001)
        }
    }

    func testLegacyDataDecodesWithoutLosingTimestampTextOrCategory() throws {
        var old = Ledger(); old.schemaVersion = 1
        let time = date("2026-10-14T10:15:00Z")
        old.entries = [CheckIn(end: time, activity: "Existing class prep", categoryID: "work", revision: Revision(counter: 3, writer: "phone"))]
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as! [String: Any]
        var settings = object["settings"] as! [String: Any]; settings.removeValue(forKey: "inferenceMethod"); object["settings"] = settings
        let loaded = try JSONDecoder().decode(Ledger.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(loaded.schemaVersion, 1)
        XCTAssertEqual(loaded.entries[0].end, time)
        XCTAssertEqual(loaded.entries[0].activity, "Existing class prep")
        XCTAssertEqual(loaded.entries[0].categoryID, "work")
        XCTAssertEqual(loaded.entries[0].id, String(Int64(time.timeIntervalSince1970)))
        XCTAssertEqual(loaded.settings.inferenceMethod, .midpoint)
    }

    func testCodingRoundTripKeepsSamplesUncategorizedDataAndCompletion() throws {
        var ledger = Ledger()
        try ledger.saveSample(at: Date(), activity: "Sample", categoryID: nil, writer: "phone")
        try ledger.addCapture(text: "Thought", writer: "phone")
        ledger.setCaptureDone(id: ledger.captures[0].id, done: true, writer: "phone")
        let data = try JSONEncoder().encode(ledger)
        XCTAssertEqual(try JSONDecoder().decode(Ledger.self, from: data), ledger)
    }
}
