import XCTest
@testable import LedgerCore

final class TimerWidgetRefreshPolicyTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func snapshot(due: TimeInterval?, paused: TimeInterval? = nil) -> TimerWidgetSnapshot {
        TimerWidgetSnapshot(title: "Current task", duration: 1200,
                            dueAt: due.map { now.addingTimeInterval($0) }, pausedRemaining: paused)
    }

    func testWaitingTaskIsReadyInsteadOfFinished() {
        XCTAssertEqual(snapshot(due: nil).displayState(at: now), .ready)
    }

    func testRestartedExpiredSnapshotBecomesRunningWithANewDeadline() throws {
        var ledger = Ledger()
        try ledger.enqueueTimer(id: "task", title: "Current task", duration: 1200, writer: "watch", onWatch: true, now: now.addingTimeInterval(-1500))
        let old = snapshot(due: -300)
        XCTAssertEqual(old.displayState(at: now), .finished)
        ledger.restartTimer(writer: "watch", onWatch: true, now: now)
        let current = TimerWidgetSnapshot(title: ledger.currentTimer!.title, duration: ledger.currentTimer!.duration,
                                          dueAt: ledger.timerControl?.dueAt, pausedRemaining: ledger.timerControl?.pausedRemaining)
        XCTAssertEqual(current.displayState(at: now), .running)
        XCTAssertEqual(current.dueAt, now.addingTimeInterval(1200))
        XCTAssertNotEqual(current, old)
    }

    func testPausedSnapshotStaysPausedEvenWithAnOldDeadline() {
        XCTAssertEqual(snapshot(due: -300, paused: 90).displayState(at: now), .paused)
    }

    func testLongRunningTimerRequestsRecoveryBeforeItsDistantDeadline() {
        XCTAssertEqual(TimerWidgetRefreshPolicy.nextRefresh(snapshot: snapshot(due: 7200), at: now), now.addingTimeInterval(900))
    }

    func testApproachingExpiryRequestsRefreshAfterTheExistingExpiryEntry() {
        XCTAssertEqual(TimerWidgetRefreshPolicy.nextRefresh(snapshot: snapshot(due: 120), at: now), now.addingTimeInterval(121))
    }

    func testJustExpiredSnapshotAndShortTimerAvoidImmediateRefreshLoops() {
        XCTAssertEqual(TimerWidgetRefreshPolicy.nextRefresh(snapshot: snapshot(due: 10), at: now), now.addingTimeInterval(60))
        XCTAssertEqual(TimerWidgetRefreshPolicy.nextRefresh(snapshot: snapshot(due: 0), at: now), now.addingTimeInterval(1800))
    }

    func testMissingPausedAndWaitingSnapshotsHaveAFiniteRecoveryDate() {
        let snapshots: [TimerWidgetSnapshot?] = [nil, snapshot(due: nil), snapshot(due: nil, paused: 90)]
        for value in snapshots {
            XCTAssertEqual(TimerWidgetRefreshPolicy.nextRefresh(snapshot: value, at: now), now.addingTimeInterval(1800))
        }
    }
}
