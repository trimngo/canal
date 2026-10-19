import XCTest
@testable import LedgerCore

final class InboxSnoozeScheduleTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return value
    }
    private func date(_ day: Int, month: Int = 10) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: 9, minute: 15))!
    }
    func testNextWeekdaySkipsWeekendAndReturnsAtStartOfDay() throws {
        for day in [16, 17, 18] {
            XCTAssertEqual(InboxSnooze.nextWeekday(after: date(day), calendar: calendar), calendar.startOfDay(for: date(19)))
        }
        XCTAssertEqual(InboxSnooze.nextWeekday(after: date(19), calendar: calendar), calendar.startOfDay(for: date(20)))
    }
    func testWeekendDateShiftsForwardToMondayWithoutChangingAWeekday() {
        XCTAssertTrue(InboxSnooze.isWeekend(date(17), calendar: calendar))
        XCTAssertTrue(InboxSnooze.isWeekend(date(18), calendar: calendar))
        XCTAssertFalse(InboxSnooze.isWeekend(date(19), calendar: calendar))
        XCTAssertEqual(InboxSnooze.weekdayOnOrAfter(date(17), calendar: calendar), calendar.startOfDay(for: date(19)))
        XCTAssertEqual(InboxSnooze.weekdayOnOrAfter(date(18), calendar: calendar), calendar.startOfDay(for: date(19)))
        XCTAssertEqual(InboxSnooze.weekdayOnOrAfter(date(19), calendar: calendar), calendar.startOfDay(for: date(19)))
    }
    func testNumberOfDaysUsesLocalCalendarAcrossDaylightSavingAndYearBoundaries() throws {
        let before = date(24)
        let after = try XCTUnwrap(InboxSnooze.after(days: 2, from: before, calendar: calendar))
        XCTAssertEqual(after, calendar.startOfDay(for: date(26)))
        XCTAssertEqual(after.timeIntervalSince(calendar.startOfDay(for: before)), 49 * 3600)
        let december = date(31, month: 12)
        let january = try XCTUnwrap(InboxSnooze.after(days: 1, from: december, calendar: calendar))
        XCTAssertEqual(calendar.component(.year, from: january), 2027)
        XCTAssertEqual(calendar.component(.hour, from: january), 0)
        XCTAssertEqual(calendar.component(.minute, from: january), 0)
    }
    func testLegacyAfternoonSnoozeReturnsAtEightWithoutChangingRawTimestamp() throws {
        let afternoon = date(19), midnight = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: afternoon)!
        var capture = Capture(id: "legacy", text: "Return today", revision: Revision())
        capture.snoozedUntil = afternoon
        let original = capture
        XCTAssertTrue(capture.isSnoozed(at: midnight.addingTimeInterval(-1), calendar: calendar))
        XCTAssertFalse(capture.isSnoozed(at: midnight, calendar: calendar))
        XCTAssertFalse(capture.isSnoozed(at: midnight.addingTimeInterval(60), calendar: calendar))
        XCTAssertEqual(capture, original)
        XCTAssertEqual(try JSONDecoder().decode(Capture.self, from: JSONEncoder().encode(capture)), original)
    }

    func testNewSnoozePersistsMidnightAndRejectsToday() throws {
        let now = date(19)
        var ledger = Ledger()
        try ledger.addCapture(text: "Task", id: "task", writer: "phone", now: now)
        ledger.snoozeCapture("task", until: date(20), writer: "phone", now: now, calendar: calendar)
        XCTAssertEqual(ledger.captures[0].snoozedUntil, calendar.startOfDay(for: date(20)))
        let saved = ledger
        ledger.snoozeCapture("task", until: now.addingTimeInterval(3600), writer: "phone", now: now, calendar: calendar)
        XCTAssertEqual(ledger, saved)
    }

    func testZeroAndNegativeDaysAreRejected() {
        XCTAssertNil(InboxSnooze.after(days: 0, from: date(17), calendar: calendar))
        XCTAssertNil(InboxSnooze.after(days: -1, from: date(17), calendar: calendar))
    }
}
