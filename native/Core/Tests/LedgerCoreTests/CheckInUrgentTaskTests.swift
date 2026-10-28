import XCTest
@testable import LedgerCore

final class CheckInUrgentTaskTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func task(_ id: String, due: TimeInterval? = nil, available: TimeInterval? = nil) -> CheckInUrgentTask {
        CheckInUrgentTask(id: id, text: id, dueAt: due.map { now.addingTimeInterval($0) },
                          availableAt: available.map { now.addingTimeInterval($0) }, createdAt: now)
    }

    func testUnrankedUncategorizedTasksAreEligibleWithoutMutatingLedger() throws {
        var ledger = Ledger()
        try ledger.addCapture(text: "Reschedule the class", id: "class", writer: "p")
        try ledger.setCaptureTiming("class", timing: .asap, writer: "p")
        let before = ledger
        XCTAssertEqual(CheckInUrgentTask.candidates(in: ledger).map(\.id), ["class"])
        XCTAssertEqual(ledger, before)
    }

    func testCompletedDeletedReferenceAndExplicitNoDateTasksAreExcluded() throws {
        var ledger = Ledger()
        for id in ["active", "done", "deleted", "reference", "no-date"] {
            try ledger.addCapture(text: "Reply to " + id, id: id, writer: "p")
        }
        ledger.captures[1].isDone = true; ledger.captures[2].deletedAt = now
        ledger.captures[3].isReference = true; ledger.captures[4].timing = .noDate
        XCTAssertEqual(CheckInUrgentTask.candidates(in: ledger).map(\.id), ["active"])
    }

    func testUnseenTasksStartWithEarliestDeadlineThenASAP() {
        let tasks = [task("asap"), task("later", due: 7200), task("overdue", due: -60), task("soon", due: 3600)]
        var shown: [String: Date] = [:], ids: [String] = []
        for i in 0..<tasks.count {
            let date = now.addingTimeInterval(Double(i * 900))
            let next = CheckInUrgentTask.next(from: tasks, lastShown: shown, at: date)!
            ids.append(next.id); shown[next.id] = date
        }
        XCTAssertEqual(ids, ["overdue", "soon", "later", "asap"])
    }

    func testSnoozedTaskReturnsOnlyAtItsScheduledReturn() {
        let value = task("later", available: 3600)
        XCTAssertNil(CheckInUrgentTask.next(from: [value], lastShown: [:], at: now))
        XCTAssertEqual(CheckInUrgentTask.next(from: [value], lastShown: [:], at: now.addingTimeInterval(3600)), value)
    }

    func testOldUnshownTasksAndDeadlineWeightsCannotStarveOthers() {
        let tasks = [task("overdue", due: -3600), task("today", due: 3600), task("asap"), task("future", due: 864000)]
        var shown: [String: Date] = [:], ids: [String] = []
        for i in 0..<80 {
            let date = now.addingTimeInterval(Double(i * 900))
            let next = CheckInUrgentTask.next(from: tasks, lastShown: shown, at: date)!
            XCTAssertNotEqual(ids.last, next.id)
            ids.append(next.id); shown[next.id] = date
        }
        for id in tasks.map(\.id) { XCTAssertGreaterThan(ids.filter { $0 == id }.count, 5) }
        XCTAssertGreaterThan(ids.filter { $0 == "overdue" }.count, ids.filter { $0 == "future" }.count)
    }

    func testOlderAppearanceCanOutweighNearerDeadline() {
        let tasks = [task("overdue", due: -1), task("old"), task("recent")]
        let shown = ["overdue": now.addingTimeInterval(-900), "old": now.addingTimeInterval(-7200), "recent": now]
        XCTAssertEqual(CheckInUrgentTask.next(from: tasks, lastShown: shown, at: now)?.id, "old")
    }

    func testSingleUrgentItemAndEmptyInbox() {
        XCTAssertNil(CheckInUrgentTask.next(from: [], lastShown: [:], at: now))
        XCTAssertEqual(CheckInUrgentTask.next(from: [task("one")], lastShown: ["one": now], at: now)?.id, "one")
    }

    func testFutureQueueDoesNotCountAsAlreadyShownAndReconcileIsIdempotent() {
        var history = CheckInUrgentHistory()
        history.schedule(requestID: "a", taskID: "one", at: now.addingTimeInterval(900), repetition: nil)
        history.schedule(requestID: "b", taskID: "two", at: now.addingTimeInterval(1800), repetition: nil)
        history.reconcile(at: now)
        XCTAssertTrue(history.lastShown.isEmpty)
        history.reconcile(at: now.addingTimeInterval(1000))
        XCTAssertEqual(history.lastShown, ["one": now.addingTimeInterval(900)])
        let saved = history
        history.reconcile(at: now.addingTimeInterval(1000))
        XCTAssertEqual(history, saved)
    }

    func testCanceledFutureAndPlainCheckInAssignmentsDoNotAdvanceRecency() {
        var history = CheckInUrgentHistory()
        history.schedule(requestID: "a", taskID: "one", at: now, repetition: nil)
        history.schedule(requestID: "a", taskID: nil, at: now, repetition: nil)
        history.schedule(requestID: "b", taskID: "two", at: now.addingTimeInterval(900), repetition: nil)
        history.retainRequests([]); history.reconcile(at: now.addingTimeInterval(1800))
        XCTAssertTrue(history.lastShown.isEmpty)
    }

    func testHistoryAndFutureAssignmentsSurviveRelaunch() throws {
        var history = CheckInUrgentHistory()
        history.schedule(requestID: "a", taskID: "one", at: now, repetition: nil)
        history.schedule(requestID: "b", taskID: "two", at: now.addingTimeInterval(900), repetition: nil)
        history.reconcile(at: now)
        let saved = try JSONDecoder().decode(CheckInUrgentHistory.self, from: JSONEncoder().encode(history))
        XCTAssertEqual(saved, history)
        XCTAssertNil(saved.lastShown["two"])
    }

    func testDailyRepeatingHistoryUsesLatestOccurrenceAcrossDST() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let format = ISO8601DateFormatter()
        var history = CheckInUrgentHistory()
        history.schedule(requestID: "daily", taskID: "one", at: format.date(from: "2026-10-24T07:00:00Z")!, repetition: .daily)
        history.reconcile(at: format.date(from: "2026-10-26T08:30:00Z")!, calendar: calendar)
        XCTAssertEqual(history.lastShown["one"], format.date(from: "2026-10-26T08:00:00Z"))
    }

    func testHourlyRepeatingHistoryCountsRecentHourInsteadOfOnlyPreviousDay() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let format = ISO8601DateFormatter()
        var history = CheckInUrgentHistory()
        history.schedule(requestID: "hourly", taskID: "one", at: format.date(from: "2026-10-24T07:15:00Z")!, repetition: .hourly)
        history.reconcile(at: format.date(from: "2026-10-26T08:30:00Z")!, calendar: calendar)
        XCTAssertEqual(history.lastShown["one"], format.date(from: "2026-10-26T08:15:00Z"))
    }

    func testPreviewShowsOneTaskTitleWithoutImportedNotes() {
        let value = CheckInUrgentTask(id: "a", text: "Reschedule class\nFind the booking link", dueAt: nil, availableAt: nil, createdAt: now)
        XCTAssertEqual(value.preview, "Reschedule class")
    }
}
