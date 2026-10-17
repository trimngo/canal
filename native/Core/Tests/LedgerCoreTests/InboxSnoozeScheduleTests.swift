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
    func testNextWeekdaySkipsSaturdayAndSundayAndPreservesTime() throws {
        for day in [16, 17, 18] {
            XCTAssertEqual(InboxSnooze.nextWeekday(after: date(day), calendar: calendar), date(19))
        }
        XCTAssertEqual(InboxSnooze.nextWeekday(after: date(19), calendar: calendar), date(20))
    }
    func testWeekendDateShiftsForwardToMondayWithoutChangingAWeekday() {
        XCTAssertTrue(InboxSnooze.isWeekend(date(17), calendar: calendar))
        XCTAssertTrue(InboxSnooze.isWeekend(date(18), calendar: calendar))
        XCTAssertFalse(InboxSnooze.isWeekend(date(19), calendar: calendar))
        XCTAssertEqual(InboxSnooze.weekdayOnOrAfter(date(17), calendar: calendar), date(19))
        XCTAssertEqual(InboxSnooze.weekdayOnOrAfter(date(18), calendar: calendar), date(19))
        XCTAssertEqual(InboxSnooze.weekdayOnOrAfter(date(19), calendar: calendar), date(19))
    }
    func testNumberOfDaysUsesLocalCalendarAcrossDaylightSavingAndYearBoundaries() throws {
        let before = date(24)
        let after = try XCTUnwrap(InboxSnooze.after(days: 2, from: before, calendar: calendar))
        XCTAssertEqual(after, date(26))
        XCTAssertEqual(after.timeIntervalSince(before), 49 * 3600)
        let december = date(31, month: 12)
        let january = try XCTUnwrap(InboxSnooze.after(days: 1, from: december, calendar: calendar))
        XCTAssertEqual(calendar.component(.year, from: january), 2027)
        XCTAssertEqual(calendar.component(.hour, from: january), 9)
        XCTAssertEqual(calendar.component(.minute, from: january), 15)
    }
    func testZeroAndNegativeDaysAreRejected() {
        XCTAssertNil(InboxSnooze.after(days: 0, from: date(17), calendar: calendar))
        XCTAssertNil(InboxSnooze.after(days: -1, from: date(17), calendar: calendar))
    }
}
