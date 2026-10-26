import XCTest
@testable import LedgerCore

final class WatchTimerAlarmPolicyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func fixture() throws -> Ledger {
        var ledger = Ledger()
        try ledger.enqueueTimer(id: "one", title: "Guitar", duration: 60, writer: "watch", onWatch: true, now: now)
        try ledger.enqueueTimer(id: "two", title: "Email", duration: 120, writer: "watch", onWatch: true, now: now)
        return ledger
    }
    private func requested(_ ledger: Ledger, at date: Date? = nil, silenced: String? = nil, failed: String? = nil) -> String? {
        WatchTimerAlarmPolicy.controlToSchedule(in: ledger, writer: "watch", silencedToken: silenced,
                                                failedToken: failed, now: date ?? now)?.token
    }

    func testLegacyAlarmRecoversItsExactDeadlineWhileTheControlStillMatches() throws {
        let control = try XCTUnwrap(fixture().timerControl)
        XCTAssertEqual(WatchTimerAlarmPolicy.deadlineForLegacyRecord(
            scheduledToken: control.token, control: control, now: now), control.dueAt)
    }

    func testLegacyAlarmChangedOnPhoneEventuallyRecoversWithoutSchedulingADuplicateEarly() throws {
        var ledger = try fixture()
        let old = try XCTUnwrap(ledger.timerControl?.token)
        ledger.restartTimer(writer: "phone", onWatch: false, now: now)
        let due = WatchTimerAlarmPolicy.deadlineForLegacyRecord(scheduledToken: old, control: ledger.timerControl, now: now)
        XCTAssertEqual(due, now.addingTimeInterval(36 * 60 * 60))
        XCTAssertEqual(WatchTimerAlarmPolicy.deadlineForLegacyRecord(scheduledToken: old, control: nil, now: now), due)
        XCTAssertEqual(WatchTimerAlarmPolicy.update(scheduledToken: old, requestedToken: "new",
            isActive: true, hasSession: false), .waitForSession)
        XCTAssertFalse(WatchTimerAlarmPolicy.scheduledRecordHasExpired(dueAt: due,
            now: due.addingTimeInterval(1799)))
        XCTAssertTrue(WatchTimerAlarmPolicy.scheduledRecordHasExpired(dueAt: due,
            now: due.addingTimeInterval(1800)))
        // Once that entire system window passes, discarding the record permits
        // a new foreground alarm instead of waiting forever for a lost handle.
        XCTAssertEqual(WatchTimerAlarmPolicy.update(scheduledToken: nil, requestedToken: "new",
            isActive: true, hasSession: false), .schedule)
    }

    func testPhoneEditsRetainAlarmInBackgroundAndCancelWhenWatchBecomesActive() throws {
        for action in ["pause", "restart", "done", "delete", "edit", "takeover"] {
            var ledger = try fixture()
            let scheduled = try XCTUnwrap(requested(ledger))
            switch action {
            case "pause": ledger.pauseTimer(writer: "phone", onWatch: false, now: now)
            case "restart": ledger.restartTimer(writer: "phone", onWatch: false, now: now)
            case "done": ledger.finishTimer(writer: "phone", onWatch: false, now: now)
            case "delete": ledger.deleteQueuedTimer("one", writer: "phone", onWatch: false, now: now)
            case "edit": try ledger.editQueuedTimer("one", title: "Guitar", duration: 180, writer: "phone", onWatch: false, now: now)
            default: ledger.moveTimerAlerts(writer: "phone", onWatch: false)
            }
            let next = requested(ledger)
            XCTAssertNil(next, action)
            XCTAssertEqual(WatchTimerAlarmPolicy.update(scheduledToken: scheduled, requestedToken: next,
                isActive: false, hasSession: true), .waitForForeground, action)
            XCTAssertEqual(WatchTimerAlarmPolicy.wake(scheduledToken: scheduled, requestedToken: next,
                isActive: false), .ringPrevious, action)
            XCTAssertEqual(WatchTimerAlarmPolicy.update(scheduledToken: scheduled, requestedToken: next,
                isActive: true, hasSession: true), .cancel, action)
        }
    }
    func testBackgroundRelaunchPreservesTheOldSessionEvenBeforeWatchKitAdoptsIt() throws {
        let scheduled = try XCTUnwrap(requested(fixture()))
        XCTAssertEqual(WatchTimerAlarmPolicy.update(scheduledToken: scheduled, requestedToken: nil,
            isActive: false, hasSession: false), .waitForForeground)
        XCTAssertEqual(WatchTimerAlarmPolicy.update(scheduledToken: scheduled, requestedToken: "new",
            isActive: true, hasSession: false), .waitForSession)
        XCTAssertEqual(WatchTimerAlarmPolicy.update(scheduledToken: scheduled, requestedToken: "new",
            isActive: true, hasSession: true), .replace)
    }
    func testUnchangedAlarmSurvivesRelaunchWithoutSchedulingADuplicate() throws {
        let token = try XCTUnwrap(requested(fixture()))
        for active in [true, false] {
            XCTAssertEqual(WatchTimerAlarmPolicy.update(scheduledToken: token, requestedToken: token,
                isActive: active, hasSession: false), .unchanged)
            XCTAssertEqual(WatchTimerAlarmPolicy.wake(scheduledToken: token, requestedToken: token,
                isActive: active), .ringCurrent)
        }
    }
    func testStaleSessionAdoptedInForegroundCanBeCancelledWithoutRinging() {
        XCTAssertEqual(WatchTimerAlarmPolicy.wake(scheduledToken: "old", requestedToken: "new", isActive: true), .cancel)
        XCTAssertEqual(WatchTimerAlarmPolicy.wake(scheduledToken: nil, requestedToken: nil, isActive: true), .cancel)
    }
    func testUnknownRunningBackgroundSessionStillAlertsInsteadOfRunningSilently() {
        XCTAssertEqual(WatchTimerAlarmPolicy.wake(scheduledToken: nil, requestedToken: nil, isActive: false), .ringPrevious)
    }
    func testNewAlarmRequiresForegroundAndNoAlarmRequiresNoWork() {
        XCTAssertEqual(WatchTimerAlarmPolicy.update(scheduledToken: nil, requestedToken: "new",
            isActive: false, hasSession: false), .waitForForeground)
        XCTAssertEqual(WatchTimerAlarmPolicy.update(scheduledToken: nil, requestedToken: "new",
            isActive: true, hasSession: false), .schedule)
        XCTAssertEqual(WatchTimerAlarmPolicy.update(scheduledToken: nil, requestedToken: nil,
            isActive: false, hasSession: false), .unchanged)
    }
    func testStoppedFailedAndExpiredAlarmsDoNotAutomaticallyRearm() throws {
        let ledger = try fixture(), token = try XCTUnwrap(requested(ledger))
        XCTAssertNil(requested(ledger, silenced: token))
        XCTAssertNil(requested(ledger, failed: token))
        XCTAssertNotNil(requested(ledger, at: now.addingTimeInterval(1859)))
        XCTAssertNil(requested(ledger, at: now.addingTimeInterval(1860)))
        var restarted = ledger
        restarted.restartTimer(writer: "watch", onWatch: true, now: now)
        XCTAssertNotNil(requested(restarted, silenced: token, failed: token))
    }
    func testTitleAndQueueEditsDoNotReplaceTheScheduledAlarm() throws {
        var ledger = try fixture()
        let token = try XCTUnwrap(requested(ledger))
        try ledger.editQueuedTimer("one", title: "Practice guitar", duration: 60, writer: "phone", onWatch: false, now: now)
        ledger.reorderWaitingTimers(["two"], writer: "phone")
        XCTAssertEqual(requested(ledger), token)
        XCTAssertEqual(WatchTimerAlarmPolicy.wake(scheduledToken: token, requestedToken: requested(ledger), isActive: false), .ringCurrent)
    }
    func testRestartingExpiredWatchTimerOnPhoneDoesNotLeaveASilentSession() throws {
        var ledger = try fixture()
        let scheduled = try XCTUnwrap(requested(ledger))
        let expired = now.addingTimeInterval(90)
        XCTAssertTrue(ledger.timerControl!.isFinished(at: expired))
        ledger.restartTimer(writer: "phone", onWatch: false, now: expired)
        XCTAssertEqual(ledger.timerControl?.dueAt, expired.addingTimeInterval(60))
        XCTAssertNotEqual(ledger.timerControl?.token, scheduled)
        XCTAssertNil(requested(ledger, at: expired))
        XCTAssertEqual(WatchTimerAlarmPolicy.wake(scheduledToken: scheduled,
            requestedToken: requested(ledger, at: expired), isActive: false), .ringPrevious)
        XCTAssertEqual(WatchTimerAlarmPolicy.update(scheduledToken: scheduled,
            requestedToken: requested(ledger, at: expired), isActive: true, hasSession: true), .cancel)
        // Stopping that earlier alarm must not suppress a later Watch takeover.
        ledger.moveTimerAlerts(writer: "watch", onWatch: true)
        XCTAssertNotNil(requested(ledger, at: expired, silenced: scheduled))
    }
}
