import XCTest
@testable import LedgerCore

final class LedgerTests: XCTestCase {
    func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
    var utc: Calendar { var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!; return calendar }

    func testDefaultScheduleHasSixtyPromptsAndCorrectBoundaries() throws {
        let minutes = try Settings().notificationMinutes()
        XCTAssertEqual(minutes.count, 60)
        XCTAssertEqual(minutes.first, 435)
        XCTAssertEqual(minutes.last, 1320)
    }

    func testExcessiveAndOvernightSchedulesRejected() {
        var settings = Settings(); settings.startMinute = 0
        XCTAssertThrowsError(try settings.notificationMinutes())
        settings.startMinute = 1320; settings.endMinute = 420
        XCTAssertThrowsError(try settings.notificationMinutes())
    }

    func testMissedIntervalsRemainUnloggedAndCaptureDoesNotInflateTime() throws {
        var ledger = Ledger(); let now = date("2026-10-14T10:00:00Z")
        try ledger.saveCheckIn(end: now, activity: "Preparing classes", categoryID: "work", writer: "phone", now: now)
        try ledger.addCapture(text: "Buy milk", writer: "watch", now: now)
        let rows = ledger.breakdown(on: now, calendar: utc)
        XCTAssertEqual(rows.first { $0.id == "work" }?.minutes, 15)
        XCTAssertEqual(rows.first { $0.id == "work" }!.percent, 15.0 / 1440 * 100, accuracy: 0.0001)
        XCTAssertEqual(rows.first { $0.id == "unlogged" }?.minutes, 1425)
        XCTAssertEqual(rows.reduce(0) { $0 + $1.percent }, 100, accuracy: 0.0001)
    }

    func testEditingSameIntervalDoesNotDoubleCountAndCategoryCanBeChanged() throws {
        var ledger = Ledger(); let now = date("2026-10-14T10:00:00Z")
        try ledger.saveCheckIn(end: now, activity: "Planning", categoryID: nil, writer: "phone", now: now)
        try ledger.saveCheckIn(end: now, activity: "Class planning", categoryID: "work", writer: "phone", now: now)
        XCTAssertEqual(ledger.entries.count, 1)
        XCTAssertEqual(ledger.entries.first?.categoryID, "work")
    }

    func testCategoryRenamePreservesAssignments() throws {
        var ledger = Ledger(); let now = date("2026-10-14T10:00:00Z")
        try ledger.saveCheckIn(end: now, activity: "Prep", categoryID: "work", writer: "phone", now: now)
        try ledger.saveCategory(id: "work", name: "Teaching", writer: "phone")
        XCTAssertEqual(ledger.breakdown(on: now, calendar: utc).first { $0.id == "work" }?.name, "Teaching")
        XCTAssertEqual(ledger.entries.first?.categoryID, "work")
        XCTAssertThrowsError(try ledger.saveCategory(id: nil, name: " teaching ", writer: "phone"))
    }

    func testMidnightIntervalBelongsToPreviousDay() throws {
        var ledger = Ledger(); let end = date("2026-10-15T00:00:00Z")
        try ledger.saveCheckIn(end: end, activity: "Rest", categoryID: "rest", writer: "phone", now: end)
        XCTAssertEqual(ledger.entries(on: date("2026-10-14T12:00:00Z"), calendar: utc).count, 1)
        XCTAssertTrue(ledger.entries(on: end, calendar: utc).isEmpty)
    }

    func testFutureUnalignedAndEmptyEntriesRejected() {
        var ledger = Ledger(); let now = date("2026-10-14T10:00:00Z")
        XCTAssertThrowsError(try ledger.saveCheckIn(end: now.addingTimeInterval(900), activity: "Future", categoryID: nil, writer: "phone", now: now))
        XCTAssertThrowsError(try ledger.saveCheckIn(end: now.addingTimeInterval(-1), activity: "Wrong", categoryID: nil, writer: "phone", now: now))
        XCTAssertThrowsError(try ledger.saveCheckIn(end: now, activity: " ", categoryID: nil, writer: "phone", now: now))
    }

    func testMergePreservesOfflineCapturesAndNewerEdits() throws {
        var phone = Ledger(), watch = Ledger(); let now = date("2026-10-14T10:00:00Z")
        try phone.saveCheckIn(end: now, activity: "Original", categoryID: nil, writer: "phone", now: now)
        watch.merge(phone)
        try watch.saveCheckIn(end: now, activity: "Edited on Watch", categoryID: "work", writer: "watch", now: now)
        try phone.addCapture(text: "Phone thought", writer: "phone")
        try watch.addCapture(text: "Watch thought", writer: "watch")
        phone.merge(watch); watch.merge(phone)
        XCTAssertEqual(phone, watch)
        XCTAssertEqual(phone.entries.count, 1)
        XCTAssertEqual(phone.entries.first?.activity, "Edited on Watch")
        XCTAssertEqual(phone.captures.count, 2)
    }

    func testMergeIsIdempotentAndResolvesConcurrentChangesConsistently() throws {
        var a = Ledger(), b = Ledger(); let now = date("2026-10-14T10:00:00Z")
        try a.saveCheckIn(end: now, activity: "A", categoryID: nil, writer: "a", now: now)
        try b.saveCheckIn(end: now, activity: "B", categoryID: nil, writer: "b", now: now)
        let originalA = a; a.merge(b); b.merge(originalA)
        XCTAssertEqual(a, b)
        let once = a; a.merge(b); XCTAssertEqual(a, once)
    }

    func testDaylightSavingSlotsRespectRealDayButPercentageDenominatorStays1440() throws {
        var calendar = utc; calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let spring = date("2026-03-29T12:00:00Z"), autumn = date("2026-10-25T12:00:00Z")
        XCTAssertEqual(Ledger.completedSlots(on: spring, now: date("2026-03-30T12:00:00Z"), calendar: calendar).count, 92)
        XCTAssertEqual(Ledger.completedSlots(on: autumn, now: date("2026-10-26T12:00:00Z"), calendar: calendar).count, 100)
        XCTAssertEqual(Ledger().breakdown(on: spring, calendar: calendar).last?.percent, 100)
    }

    func testCodingRoundTripKeepsUncategorizedDataAndCompletion() throws {
        var ledger = Ledger()
        try ledger.addCapture(text: "Thought", writer: "phone")
        ledger.setCaptureDone(id: ledger.captures[0].id, done: true, writer: "phone")
        let data = try JSONEncoder().encode(ledger)
        XCTAssertEqual(try JSONDecoder().decode(Ledger.self, from: data), ledger)
    }
}
