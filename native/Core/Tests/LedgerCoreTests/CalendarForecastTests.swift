import XCTest
@testable import LedgerCore

final class CalendarForecastTests: XCTestCase {
    private var utc: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 0)!; return c }
    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    private var noon: Date { date("2026-10-29T12:00:00Z") }
    private func event(_ id: String, _ start: String, _ end: String, _ ids: [String]) -> CategorizedCalendarEvent {
        CategorizedCalendarEvent(snapshot: CalendarEventSnapshot(id: id, calendarID: "selected", calendarName: "Calendar", title: id,
            start: date(start), end: date(end)), categoryIDs: ids)
    }

    func testOnlyRemainingTimeOnSelectedDayCounts() {
        let ledger = Ledger()
        let input = [event("ongoing", "2026-10-29T11:00:00Z", "2026-10-29T13:00:00Z", ["work"]),
                     event("past", "2026-10-29T09:00:00Z", "2026-10-29T10:00:00Z", ["work"]),
                     event("overnight", "2026-10-29T23:30:00Z", "2026-10-30T01:00:00Z", ["social"]),
                     event("tomorrow", "2026-10-30T12:00:00Z", "2026-10-30T13:00:00Z", ["work"])]
        let forecast = ledger.calendarForecast(input, on: noon, now: noon, calendar: utc)
        XCTAssertEqual(forecast.minutes, 90)
        XCTAssertEqual(forecast.directMinutes["work"], 60)
        XCTAssertEqual(forecast.directMinutes["social"], 30)
        XCTAssertEqual(forecast.events.first?.snapshot.start, noon)
        XCTAssertEqual(forecast.events.last?.snapshot.end, date("2026-10-30T00:00:00Z"))
    }

    func testOverlapsShareClockTimeAndMultipleCategoriesShareTheirEvent() {
        let ledger = Ledger()
        let input = [event("a", "2026-10-29T12:00:00Z", "2026-10-29T13:00:00Z", ["work", "social"]),
                     event("b", "2026-10-29T12:30:00Z", "2026-10-29T13:30:00Z", ["work"])]
        let forecast = ledger.calendarForecast(input, on: noon, now: noon, calendar: utc)
        XCTAssertEqual(forecast.minutes, 90)
        XCTAssertEqual(forecast.directMinutes["work"], 67.5)
        XCTAssertEqual(forecast.directMinutes["social"], 22.5)
    }

    func testDuplicateOccurrencesAreCountedOnceAndInputOrderDoesNotMatter() {
        let ledger = Ledger(), first = event("same", "2026-10-29T13:00:00Z", "2026-10-29T14:00:00Z", ["work"])
        let later = event("next-occurrence", "2026-10-29T15:00:00Z", "2026-10-29T16:00:00Z", ["work"])
        let forward = ledger.calendarForecast([first, first, later], on: noon, now: noon, calendar: utc)
        let reverse = ledger.calendarForecast([later, first, first], on: noon, now: noon, calendar: utc)
        XCTAssertEqual(forward, reverse)
        XCTAssertEqual(forward.events.count, 2)
        XCTAssertEqual(forward.minutes, 120)
    }

    func testChildPrecedenceUnknownCategoriesAndParentRollups() throws {
        var ledger = Ledger()
        ledger.categories.append(LedgerCategory(id: "teaching", name: "Teaching"))
        try ledger.moveCategory("teaching", to: "work", writer: "test")
        let input = [event("class", "2026-10-29T13:00:00Z", "2026-10-29T14:00:00Z", ["work", "teaching"]),
                     event("unknown", "2026-10-29T14:00:00Z", "2026-10-29T14:30:00Z", []),
                     event("deleted", "2026-10-29T15:00:00Z", "2026-10-29T16:00:00Z", ["teaching", "deleted"])]
        let forecast = ledger.calendarForecast(input, on: noon, now: noon, calendar: utc)
        XCTAssertNil(forecast.directMinutes["work"])
        XCTAssertEqual(forecast.directMinutes["teaching"], 90)
        XCTAssertEqual(forecast.directMinutes["uncategorized"], 60)
        XCTAssertEqual(forecast.minutes(for: "work", in: ledger), 90)
        XCTAssertEqual(forecast.minutes(for: "work", in: ledger, direct: true), 0)
    }

    func testPreviewNeverChangesActualLedgerHistoryOrGoalAccounting() throws {
        var ledger = Ledger()
        let ended = event("recorded", "2026-10-29T09:00:00Z", "2026-10-29T10:00:00Z", ["work"])
        ledger.collectCalendarEvents([ended.snapshot], writer: "test", now: noon)
        try ledger.decideCalendarEvent(ended.id, confirm: true, categoryIDs: ["work"], writer: "test", now: noon)
        let original = ledger, actual = ledger.history(range: .today, now: noon, calendar: utc)
        let forecast = ledger.calendarForecast([event("future", "2026-10-29T13:00:00Z", "2026-10-29T14:00:00Z", ["social"])], on: noon, now: noon, calendar: utc)
        let preview = forecast.preview(of: actual, in: ledger)
        XCTAssertEqual(actual.trackedMinutes, 60)
        XCTAssertEqual(preview.trackedMinutes, 120)
        XCTAssertEqual(preview.rows.reduce(0) { $0 + $1.percent }, 100, accuracy: 0.00001)
        XCTAssertEqual(preview.samples, actual.samples)
        XCTAssertEqual(preview.dailyTotals, actual.dailyTotals)
        XCTAssertEqual(ledger, original)
        XCTAssertEqual(ledger.history(range: .today, now: noon, calendar: utc).trackedMinutes, 60)
        XCTAssertEqual(ledger.allocation(on: noon, now: noon, calendar: utc).trackedMinutes, 60)
    }

    func testEndedEventLeavesForecastAndRequiresExplicitConfirmation() throws {
        var ledger = Ledger()
        let planned = event("meeting", "2026-10-29T12:00:00Z", "2026-10-29T13:00:00Z", ["work"])
        XCTAssertEqual(ledger.calendarForecast([planned], on: noon, now: noon, calendar: utc).minutes, 60)
        let after = date("2026-10-29T13:01:00Z")
        ledger.collectCalendarEvents([planned.snapshot], writer: "test", now: after)
        XCTAssertEqual(ledger.calendarEvents?.first?.decision, .pending)
        XCTAssertTrue(ledger.entries.isEmpty)
        XCTAssertEqual(ledger.calendarForecast([planned], on: noon, now: after, calendar: utc).minutes, 0)
        XCTAssertEqual(ledger.history(range: .today, now: after, calendar: utc).trackedMinutes, 0)
        try ledger.decideCalendarEvent(planned.id, confirm: true, categoryIDs: ["work"], writer: "test", now: after)
        XCTAssertEqual(ledger.history(range: .today, now: after, calendar: utc).trackedMinutes, 60)
        XCTAssertEqual(ledger.calendarForecast([planned], on: noon, now: after, calendar: utc).minutes, 0)
    }

    func testReportingTimeZoneAndDSTUseCalendarBoundaries() {
        var ledger = Ledger(); ledger.settings.reportingTimeZoneIdentifier = "Europe/Berlin"
        let now = date("2026-10-25T00:00:00Z")
        let input = [event("fall-back", "2026-10-25T00:00:00Z", "2026-10-25T03:00:00Z", ["work"]),
                     event("midnight", "2026-10-25T22:30:00Z", "2026-10-26T01:00:00Z", ["social"])]
        let forecast = ledger.calendarForecast(input, on: now, now: now, calendar: utc)
        XCTAssertEqual(forecast.end, date("2026-10-25T23:00:00Z"))
        XCTAssertEqual(forecast.minutes, 210)
        XCTAssertEqual(forecast.end.timeIntervalSince(forecast.start) / 3600, 25)
    }

    func testInvalidReversedPastAndEmptyInputsDoNotInventTime() {
        let ledger = Ledger()
        var input = [event("reverse", "2026-10-29T14:00:00Z", "2026-10-29T13:00:00Z", ["work"]),
                     event("zero", "2026-10-29T13:00:00Z", "2026-10-29T13:00:00Z", ["work"])]
        var invalid = input[0]; invalid.snapshot.start = Date(timeIntervalSince1970: .nan); input.append(invalid)
        XCTAssertEqual(ledger.calendarForecast(input, on: noon, now: noon, calendar: utc).minutes, 0)
        XCTAssertEqual(ledger.calendarForecast([], on: noon, now: noon, calendar: utc).minutes, 0)
        XCTAssertEqual(ledger.calendarForecast([event("past", "2026-10-28T12:00:00Z", "2026-10-28T13:00:00Z", ["work"])],
            on: date("2026-10-28T12:00:00Z"), now: noon, calendar: utc).minutes, 0)
    }
}
