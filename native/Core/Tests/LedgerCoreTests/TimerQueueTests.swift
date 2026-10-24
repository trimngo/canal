import XCTest
@testable import LedgerCore

final class TimerQueueTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func fixture() throws -> Ledger {
        var ledger = Ledger()
        try ledger.enqueueTimer(id: "one", title: "Guitar", duration: 1200, writer: "watch", onWatch: true, now: now)
        try ledger.enqueueTimer(id: "two", title: "Email", duration: 600, writer: "watch", onWatch: true, now: now.addingTimeInterval(1))
        return ledger
    }
    func testFirstStartsAndSubsequentTasksWaitInCreationOrder() throws {
        let ledger = try fixture()
        XCTAssertEqual(ledger.currentTimer?.id, "one")
        XCTAssertEqual(ledger.waitingTimers.map(\.id), ["two"])
        XCTAssertEqual(ledger.timerControl?.dueAt, now.addingTimeInterval(1200))
        XCTAssertTrue(ledger.entries.isEmpty); XCTAssertTrue(ledger.captures.isEmpty)
    }
    func testExpiredTimerWaitsWithoutAdvancingEvenAfterDaysOffline() throws {
        let ledger = try fixture()
        XCTAssertTrue(ledger.timerControl!.isFinished(at: now.addingTimeInterval(86400)))
        XCTAssertEqual(ledger.timerControl!.remaining(at: now.addingTimeInterval(86400)), 0)
        XCTAssertEqual(ledger.currentTimer?.id, "one")
        XCTAssertEqual(ledger.waitingTimers.map(\.id), ["two"])
    }
    func testDoneStartsNextImmediatelyAndDoesNotLogPlannedTime() throws {
        var ledger = try fixture()
        let tap = now.addingTimeInterval(1300)
        ledger.finishTimer(writer: "watch", onWatch: true, now: tap)
        XCTAssertEqual(ledger.currentTimer?.id, "two")
        XCTAssertEqual(ledger.timerControl?.dueAt, tap.addingTimeInterval(600))
        XCTAssertEqual(ledger.queuedTimers?.first { $0.id == "one" }?.completedAt, tap)
        XCTAssertTrue(ledger.entries.isEmpty)
    }
    func testRestartUsesFullOriginalDurationAndPreservesQueue() throws {
        var ledger = try fixture()
        ledger.restartTimer(writer: "watch", onWatch: true, now: now.addingTimeInterval(1300))
        XCTAssertEqual(ledger.currentTimer?.id, "one")
        XCTAssertEqual(ledger.timerControl?.dueAt, now.addingTimeInterval(2500))
        XCTAssertNil(ledger.currentTimer?.completedAt)
        XCTAssertEqual(ledger.waitingTimers.map(\.id), ["two"])
    }
    func testOldOrRepeatedNotificationActionCannotSkipAnotherTask() throws {
        var ledger = try fixture()
        let old = ledger.timerControl!.token
        ledger.finishTimer(expectedToken: old, writer: "watch", onWatch: true, now: now)
        let saved = ledger
        ledger.finishTimer(expectedToken: old, writer: "watch", onWatch: true, now: now)
        ledger.restartTimer(expectedToken: old, writer: "watch", onWatch: true, now: now)
        XCTAssertEqual(ledger, saved)
    }
    func testPauseResumePreservesRemainingTimeWithoutPhone() throws {
        var ledger = try fixture()
        ledger.pauseTimer(writer: "watch", onWatch: true, now: now.addingTimeInterval(300))
        XCTAssertNil(ledger.timerControl?.dueAt)
        XCTAssertEqual(ledger.timerControl?.remaining(at: now.addingTimeInterval(9000)), 900)
        XCTAssertFalse(ledger.timerControl!.isFinished(at: now.addingTimeInterval(9000)))
        ledger.resumeTimer(writer: "watch", onWatch: true, now: now.addingTimeInterval(9000))
        XCTAssertEqual(ledger.timerControl?.dueAt, now.addingTimeInterval(9900))
    }
    func testDeletingQueuedTaskPreservesActiveDeadlineAndSurvivesStaleMerge() throws {
        var ledger = try fixture(); let old = ledger
        let control = ledger.timerControl
        ledger.deleteQueuedTimer("two", writer: "watch", onWatch: true, now: now)
        ledger.merge(old)
        XCTAssertTrue(ledger.waitingTimers.isEmpty)
        XCTAssertEqual(ledger.timerControl, control)
    }
    func testDeletingActiveTaskStartsNextAndCompletingLastStops() throws {
        var ledger = try fixture()
        ledger.deleteQueuedTimer("one", writer: "watch", onWatch: true, now: now)
        XCTAssertEqual(ledger.currentTimer?.id, "two")
        ledger.finishTimer(writer: "watch", onWatch: true, now: now)
        XCTAssertNil(ledger.currentTimer); XCTAssertNil(ledger.timerControl?.taskID)
        XCTAssertTrue(ledger.waitingTimers.isEmpty)
    }
    func testConcurrentAppendsSurviveDeterministicMergeWithOneActiveTimer() throws {
        var watch = try fixture(), phone = watch
        try watch.enqueueTimer(id: "watch-new", title: "Walk", duration: 60, writer: "watch", onWatch: true, now: now.addingTimeInterval(2))
        try phone.enqueueTimer(id: "phone-new", title: "Read", duration: 90, writer: "phone", onWatch: false, now: now.addingTimeInterval(3))
        var a = watch, b = phone; a.merge(phone); b.merge(watch)
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.currentTimer?.id, "one")
        XCTAssertEqual(a.waitingTimers.map(\.id), ["two", "watch-new", "phone-new"])
    }
    func testSimultaneousStartsKeepBothTasksAndResolveOneControl() throws {
        var a = Ledger(), b = Ledger()
        try a.enqueueTimer(id: "a", title: "A", duration: 60, writer: "watch", onWatch: true, now: now)
        try b.enqueueTimer(id: "b", title: "B", duration: 60, writer: "phone", onWatch: false, now: now)
        var x = a, y = b; x.merge(b); y.merge(a)
        XCTAssertEqual(x, y); XCTAssertEqual(x.waitingTimers.count, 1)
        XCTAssertEqual(Set([x.currentTimer!.id] + x.waitingTimers.map(\.id)), ["a", "b"])
    }
    func testPauseAndDeadlineSurviveBackupAndLegacySync() throws {
        var ledger = try fixture()
        ledger.pauseTimer(writer: "watch", onWatch: true, now: now.addingTimeInterval(100))
        var restored = try LedgerBackup.decode(LedgerBackup(ledger: ledger).encoded()).ledger
        XCTAssertEqual(restored, ledger)
        restored.merge(Ledger())
        XCTAssertEqual(restored.timerControl, ledger.timerControl)
        XCTAssertEqual(restored.queuedTimers, ledger.queuedTimers?.sorted { $0.id < $1.id })
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Ledger())) as! [String: Any]
        json.removeValue(forKey: "queuedTimers"); json.removeValue(forKey: "timerControl")
        let legacy = try JSONDecoder().decode(Ledger.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(legacy.timerControl); XCTAssertNil(legacy.queuedTimers)
    }
    func testAlertOwnershipMovesWithoutChangingTheDeadline() throws {
        var ledger = try fixture(); let deadline = ledger.timerControl?.dueAt
        ledger.moveTimerAlerts(writer: "phone", onWatch: false)
        XCTAssertEqual(ledger.timerControl?.owner, "phone")
        XCTAssertEqual(ledger.timerControl?.dueAt, deadline)
        XCTAssertEqual(ledger.timerControl?.onWatch, false)
    }
    func testInvalidInputAndIdempotentCapture() throws {
        var ledger = try fixture(); let saved = ledger
        try ledger.enqueueTimer(id: "one", title: "Duplicate", duration: 12, writer: "watch", onWatch: true)
        XCTAssertEqual(ledger, saved)
        for duration in [0.0, -1, .nan, .infinity, 86401] {
            XCTAssertThrowsError(try ledger.enqueueTimer(title: "Bad", duration: duration, writer: "watch", onWatch: true))
        }
        XCTAssertThrowsError(try ledger.enqueueTimer(title: " ", duration: 60, writer: "watch", onWatch: true))
    }
    func testSpokenDraftParsesTaskAndDurationWithoutChangingItsTitle() throws {
        for (text, title, seconds) in [("Practice guitar for twenty minutes", "Practice guitar", 1200.0),
                                       ("Read, 1 hour and 30 minutes", "Read", 5400.0),
                                       ("Twenty one pilots for twenty-five minutes", "Twenty one pilots", 1500.0),
                                       ("Stretch for half an hour", "Stretch", 1800.0),
                                       ("20 minutes practice guitar", "practice guitar", 1200.0)] {
            let draft = try TimerDraft.parse(text)
            XCTAssertEqual(draft.title, title, text); XCTAssertEqual(draft.duration, seconds, text)
        }
    }
    func testAmbiguousDurationRequiresCorrection() {
        for text in ["Read", "Read for a while", "Read for 20 minutes or 30 minutes", "Read for -2 minutes", "Read for 25 hours"] {
            XCTAssertThrowsError(try TimerDraft.parse(text), text)
        }
    }
    func testOnlyExactTimerComplicationRoutesAreAccepted() {
        XCTAssertTrue(TimerQueueShortcut.matches(TimerQueueShortcut.add))
        XCTAssertTrue(TimerQueueShortcut.matches(TimerQueueShortcut.current))
        for url in ["https://timers", "canal-dash://log-now", "canal-dash://timers?task=bad", "canal-dash://user@timers"] {
            XCTAssertFalse(TimerQueueShortcut.matches(URL(string: url)!))
        }
    }
    func testQuickCompanionPacketCarriesActiveControlAndRecentTimerChanges() throws {
        let ledger = try fixture()
        var delivery = CompanionQuickDelivery()
        let bytes = try XCTUnwrap(delivery.prepare(ledger, id: "timer-packet"))
        let packet = try JSONDecoder().decode(CompanionQuickPacket.self, from: bytes)
        XCTAssertEqual(packet.ledger.timerControl, ledger.timerControl)
        XCTAssertEqual(packet.ledger.currentTimer, ledger.currentTimer)
        var restored = Ledger(); restored.merge(packet.ledger)
        XCTAssertEqual(restored.waitingTimers.map(\.id), ["two"])
        XCTAssertTrue(delivery.finish(id: "timer-packet", saved: true))
        XCTAssertNil(try delivery.prepare(ledger, id: "same"))
    }
}
