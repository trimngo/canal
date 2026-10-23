import XCTest
@testable import LedgerCore

final class ConfirmedCalendarTests: XCTestCase {
    private func date(_ s: String) -> Date { ISO8601DateFormatter().date(from: s)! }
    private var utc: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 0)!; return c }
    private let now = ISO8601DateFormatter().date(from: "2026-10-27T12:00:00Z")!
    private func event(_ id: String = "event", start: String = "2026-10-19T10:00:00Z", end: String = "2026-10-19T11:00:00Z") -> CalendarEventSnapshot {
        CalendarEventSnapshot(id: id, calendarID: "cal", calendarName: "Classes", title: "Lecture", start: date(start), end: date(end))
    }
    func testPendingAndSkippedNeverCountAndRepeatedRefreshDoesNotReopen() throws {
        var ledger = Ledger(); let snapshot = event()
        ledger.collectCalendarEvents([snapshot, snapshot], writer: "phone", now: now)
        XCTAssertEqual(ledger.calendarEvents?.count, 1)
        XCTAssertEqual(ledger.allocation(on: snapshot.start, now: now, calendar: utc).trackedMinutes, 0)
        try ledger.decideCalendarEvent(snapshot.id, confirm: false, writer: "phone", now: now)
        ledger.collectCalendarEvents([snapshot], writer: "phone", now: now)
        XCTAssertEqual(ledger.calendarEvents?.first?.decision, .skipped)
        XCTAssertTrue(ledger.entries.isEmpty)
    }
    func testConfirmedReplacesOverlappingEstimatesWithoutDeletingSamplesBothMethods() throws {
        for method in InferenceMethod.allCases {
            var ledger = Ledger(); ledger.settings.inferenceMethod = method
            try ledger.saveSample(id: "a", at: date("2026-10-19T09:45:00Z"), activity: "Prep", categoryID: "work", writer: "watch", now: now)
            try ledger.saveSample(id: "b", at: date("2026-10-19T10:45:00Z"), activity: "Shopping", categoryID: "personal", writer: "watch", now: now)
            let originals = ledger.entries
            ledger.collectCalendarEvents([event()], writer: "phone", now: now)
            try ledger.decideCalendarEvent("event", confirm: true, categoryIDs: ["social"], writer: "phone", now: now)
            let segments = ledger.inferredSegments(on: event().start, now: now, calendar: utc)
            XCTAssertEqual(segments.filter { $0.sampleID == "calendar-event" }.reduce(0) { $0 + $1.minutes }, 60)
            XCTAssertTrue(segments.filter { $0.sampleID != "calendar-event" }.allSatisfy { $0.end <= event().start || $0.start >= event().end })
            XCTAssertEqual(ledger.entries.filter { $0.intervalStart == nil }, originals)
            let period = ledger.allocation(on: event().start, now: now, calendar: utc)
            XCTAssertEqual(period.trackedMinutes, 82.5)
            XCTAssertEqual(period.directMinutes["social"], 60)
            XCTAssertEqual(period.directMinutes.values.reduce(0,+), period.trackedMinutes)
            try ledger.decideCalendarEvent("event", confirm: true, writer: "phone", now: now)
            XCTAssertEqual(ledger.entries.count, 3)
            ledger.setLogDeleted("calendar-event", deleted: true, writer: "phone")
            XCTAssertEqual(ledger.allocation(on: event().start, now: now, calendar: utc).trackedMinutes, 75)
        }
    }
    func testCrossMidnightAndCalendarOnlyDaysAppearInHistory() throws {
        var ledger = Ledger(); let snapshot = event(start: "2026-10-19T23:30:00Z", end: "2026-10-20T01:30:00Z")
        ledger.collectCalendarEvents([snapshot], writer: "p", now: now)
        try ledger.decideCalendarEvent(snapshot.id, confirm: true, categoryIDs: ["work"], writer: "p", now: now)
        XCTAssertEqual(ledger.allocation(on: snapshot.start, now: now, calendar: utc).trackedMinutes, 30)
        XCTAssertEqual(ledger.allocation(on: snapshot.end, now: now, calendar: utc).trackedMinutes, 90)
        let report = ledger.history(range: .allTime, now: now, calendar: utc)
        XCTAssertEqual(report.trackedMinutes, 120)
        XCTAssertEqual(Set(report.dailyTotals.map(\.day)).count, 2)
        XCTAssertEqual(ledger.entries(on: snapshot.start, calendar: utc).count, 1)
        XCTAssertTrue(ledger.daySamples(on: snapshot.end, now: now, calendar: utc).isEmpty)
    }
    func testOverlappingEventsNeverCountTwiceAndDSTUsesActualElapsedTime() throws {
        var ledger = Ledger()
        let snapshots = [event("a"), event("b", start: "2026-10-19T10:30:00Z", end: "2026-10-19T11:30:00Z")]
        ledger.collectCalendarEvents(snapshots, writer: "p", now: now)
        for e in snapshots { try ledger.decideCalendarEvent(e.id, confirm: true, categoryIDs: ["work"], writer: "p", now: now) }
        XCTAssertEqual(ledger.allocation(on: snapshots[0].start, now: now, calendar: utc).trackedMinutes, 90)
        XCTAssertEqual(ledger.inferredSegments(on: snapshots[0].start, now: now, calendar: utc).filter { $0.sampleID == "calendar-b" }.reduce(0) { $0 + $1.minutes }, 60)
        var berlin = utc; berlin.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let dst = event("dst", start: "2026-10-25T00:30:00Z", end: "2026-10-25T02:30:00Z")
        ledger.collectCalendarEvents([dst], writer: "p", now: now)
        try ledger.decideCalendarEvent(dst.id, confirm: true, writer: "p", now: now)
        XCTAssertEqual(ledger.allocation(on: dst.start, now: now, calendar: berlin).trackedMinutes, 120)
    }
    func testReceiptMergeBackupFutureValidationAndGoalAssignment() throws {
        var phone = Ledger(); let snapshot = event()
        let future = event("future", start: "2026-11-01T10:00:00Z", end: "2026-11-01T11:00:00Z")
        phone.collectCalendarEvents([snapshot, future], writer: "p", now: now)
        XCTAssertEqual(phone.calendarEvents?.count, 1)
        var watch = try LedgerBackup.decode(LedgerBackup(ledger: phone).encoded()).ledger
        try phone.decideCalendarEvent(snapshot.id, confirm: true, categoryIDs: ["work", "social"], writer: "p", now: now)
        watch.merge(phone); phone.merge(watch)
        XCTAssertEqual(phone, watch)
        XCTAssertEqual(try LedgerBackup.decode(LedgerBackup(ledger: phone).encoded()).ledger, phone)
        let totals = phone.allocation(on: snapshot.start, now: now, calendar: utc)
        XCTAssertEqual(totals.directMinutes["work"], 30)
        XCTAssertEqual(totals.directMinutes["social"], 30)
        let before = phone
        XCTAssertThrowsError(try phone.decideCalendarEvent(snapshot.id, confirm: true, writer: "p", now: date("2026-10-19T10:30:00Z")))
        XCTAssertEqual(phone, before)
    }
    func testIdentitySurvivesDeviceCalendarIDsAndSeparatesRecurringOccurrences() {
        let a = CalendarEventSnapshot.identityKey(calendarID: "phone-cal", itemID: "phone-id", externalID: "event-uid", occurrence: nil)
        let b = CalendarEventSnapshot.identityKey(calendarID: "new-phone-cal", itemID: "new-phone-id", externalID: "event-uid", occurrence: nil)
        XCTAssertEqual(a, b)
        let monday = CalendarEventSnapshot.identityKey(calendarID: "c", itemID: "i", externalID: "series", occurrence: date("2026-10-19T10:00:00Z"))
        let wednesday = CalendarEventSnapshot.identityKey(calendarID: "c", itemID: "i", externalID: "series", occurrence: date("2026-10-21T10:00:00Z"))
        XCTAssertNotEqual(monday, wednesday)
    }

}
