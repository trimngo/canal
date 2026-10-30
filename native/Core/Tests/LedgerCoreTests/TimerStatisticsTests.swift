import XCTest
@testable import LedgerCore

final class TimerStatisticsTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func fixture() throws -> Ledger {
        var ledger = Ledger()
        try ledger.enqueueTimer(id: "one", title: "Practice", duration: 60, writer: "watch", onWatch: true, now: now)
        return ledger
    }
    private func total(_ ledger: Ledger, _ seconds: Double) throws -> Double {
        ledger.timerElapsedSeconds(for: try XCTUnwrap(ledger.currentTimer), at: now.addingTimeInterval(seconds))
    }
    func testRestartCountsEarlyAndExpiredAttemptsOnceAndExcludesOverrun() throws {
        var ledger = try fixture()
        XCTAssertEqual(try total(ledger, 10), 10)
        let token = try XCTUnwrap(ledger.timerControl?.token)
        ledger.restartTimer(expectedToken: token, writer: "phone", onWatch: false, now: now.addingTimeInterval(20))
        XCTAssertEqual(ledger.currentTimer?.restarts, 1)
        XCTAssertEqual(try total(ledger, 30), 30)
        ledger.restartTimer(expectedToken: token, writer: "phone", onWatch: false, now: now.addingTimeInterval(40))
        XCTAssertEqual(ledger.currentTimer?.restarts, 1)
        XCTAssertEqual(try total(ledger, 1000), 80)
        ledger.restartTimer(writer: "watch", onWatch: true, now: now.addingTimeInterval(1000))
        XCTAssertEqual(ledger.currentTimer?.restarts, 2)
        XCTAssertEqual(try total(ledger, 1005), 85)
        XCTAssertTrue(ledger.entries.isEmpty)
    }
    func testPauseResumeAndPausedRestartExcludeEveryPausedSecond() throws {
        var ledger = try fixture()
        ledger.pauseTimer(writer: "watch", onWatch: true, now: now.addingTimeInterval(15))
        XCTAssertEqual(try total(ledger, 500), 15)
        ledger.resumeTimer(writer: "phone", onWatch: false, now: now.addingTimeInterval(500))
        XCTAssertEqual(try total(ledger, 510), 25)
        ledger.pauseTimer(writer: "phone", onWatch: false, now: now.addingTimeInterval(510))
        ledger.restartTimer(writer: "watch", onWatch: true, now: now.addingTimeInterval(1000))
        XCTAssertEqual(ledger.currentTimer?.restarts, 1)
        XCTAssertEqual(try total(ledger, 1010), 35)
        XCTAssertEqual(try total(ledger, 5000), 85)
    }
    func testEditingDurationPreservesSpentTimeWhenShorteningAndExtending() throws {
        var ledger = try fixture()
        try ledger.editQueuedTimer("one", title: "Practice", duration: 10, writer: "phone", onWatch: false, now: now.addingTimeInterval(30))
        XCTAssertEqual(try total(ledger, 100), 30)
        try ledger.editQueuedTimer("one", title: "Practice more", duration: 40, writer: "phone", onWatch: false, now: now.addingTimeInterval(100))
        XCTAssertEqual(try total(ledger, 105), 35)
        ledger.restartTimer(writer: "watch", onWatch: true, now: now.addingTimeInterval(105))
        XCTAssertEqual(try total(ledger, 110), 40)
        XCTAssertEqual(ledger.currentTimer?.restarts, 1)
    }
    func testBackupQuickSyncAndOldContextsPreserveCountAndRunningAnchor() throws {
        var watch = try fixture(); let old = watch
        watch.restartTimer(writer: "watch", onWatch: true, now: now.addingTimeInterval(90))
        var restored = try LedgerBackup.decode(LedgerBackup(ledger: watch).encoded()).ledger
        var delivery = CompanionQuickDelivery()
        let packet = try JSONDecoder().decode(CompanionQuickPacket.self, from: XCTUnwrap(delivery.prepare(watch, id: "restart")))
        var phone = Ledger(); phone.merge(packet.ledger); phone.merge(old); restored.merge(old)
        XCTAssertEqual(phone.currentTimer?.restarts, 1)
        XCTAssertEqual(try total(phone, 100), 70)
        XCTAssertEqual(try total(restored, 100), 70)
        phone.moveTimerAlerts(writer: "phone", onWatch: false)
        XCTAssertEqual(try total(phone, 110), 80)
    }
    func testDoneAndDeleteSettleTotalsAndTheNextTaskStartsWithItsOwnStatistics() throws {
        for delete in [false, true] {
            var ledger = try fixture()
            try ledger.enqueueTimer(id: "two", title: "Email", duration: 30, writer: "watch", onWatch: true, now: now)
            ledger.restartTimer(writer: "phone", onWatch: false, now: now.addingTimeInterval(60))
            if delete {
                ledger.deleteQueuedTimer("one", writer: "watch", onWatch: true, now: now.addingTimeInterval(70))
                ledger.startNextTimer(writer: "watch", onWatch: true, now: now.addingTimeInterval(70))
            } else { ledger.finishTimer(writer: "watch", onWatch: true, now: now.addingTimeInterval(70)) }
            XCTAssertEqual(ledger.queuedTimers?.first { $0.id == "one" }?.accumulatedSeconds, 70)
            XCTAssertEqual(ledger.currentTimer?.id, "two")
            XCTAssertEqual(ledger.currentTimer?.restarts, 0)
            XCTAssertEqual(try total(ledger, 75), 5)
        }
    }
    func testLegacyRunningAndPausedTimersRecoverOnlyTheirCurrentAttempt() throws {
        for paused in [false, true] {
            var ledger = try fixture()
            ledger.queuedTimers?[0].accumulatedSeconds = nil; ledger.queuedTimers?[0].restartCount = nil
            ledger.timerControl?.startedAt = nil
            if paused { ledger.timerControl?.dueAt = nil; ledger.timerControl?.pausedRemaining = 40 }
            XCTAssertEqual(try total(ledger, 20), 20)
            ledger.restartTimer(writer: "phone", onWatch: false, now: now.addingTimeInterval(20))
            XCTAssertEqual(ledger.currentTimer?.restarts, 1)
            XCTAssertEqual(try total(ledger, 25), 25)
        }
    }
    func testMalformedStatisticsCannotOverflowTheUIOrRestartCounter() throws {
        var ledger = try fixture()
        ledger.queuedTimers?[0].restartCount = Int.max
        ledger.queuedTimers?[0].accumulatedSeconds = .greatestFiniteMagnitude
        XCTAssertLessThan(try total(ledger, 20), Double(Int.max))
        ledger.restartTimer(writer: "phone", onWatch: false, now: now.addingTimeInterval(20))
        XCTAssertEqual(ledger.currentTimer?.restarts, Int.max)
        XCTAssertTrue(try total(ledger, 25).isFinite)
    }
}
