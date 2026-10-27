import XCTest
@testable import LedgerCore

final class PhoneTimerAlarmPolicyTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func watchTimer() throws -> Ledger {
        var ledger = Ledger(); ledger.settings.timerSystemAlarms = true
        try ledger.enqueueTimer(id: "one", title: "Guitar", duration: 300, writer: "watch", onWatch: true, now: now)
        try ledger.enqueueTimer(id: "two", title: "Email", duration: 600, writer: "watch", onWatch: true, now: now)
        return ledger
    }
    func testLegacySettingsDoNotOptIntoSystemAlarms() throws {
        let settings = try JSONDecoder().decode(Settings.self, from: Data("{}".utf8))
        XCTAssertFalse(settings.timerSystemAlarms)
    }
    func testWatchCannotConfirmTransferWhileInactiveOrMissingItsSessionHandle() {
        XCTAssertFalse(PhoneTimerAlarmPolicy.watchCanFinishTransfer(currentToken: "new", scheduledToken: "new", hasSession: true, isActive: false))
        XCTAssertFalse(PhoneTimerAlarmPolicy.watchCanFinishTransfer(currentToken: "new", scheduledToken: "new", hasSession: false, isActive: true))
        XCTAssertFalse(PhoneTimerAlarmPolicy.watchCanFinishTransfer(currentToken: "new", scheduledToken: "old", hasSession: true, isActive: true))
    }
    func testActiveWatchCanConfirmItsOwnCancellableAlarmOrNotificationFallback() {
        XCTAssertTrue(PhoneTimerAlarmPolicy.watchCanFinishTransfer(currentToken: "new", scheduledToken: "new", hasSession: true, isActive: true))
        XCTAssertTrue(PhoneTimerAlarmPolicy.watchCanFinishTransfer(currentToken: "new", scheduledToken: nil, hasSession: false, isActive: true))
    }
    func testTrialPreferenceSurvivesBackupAndSettingsSync() throws {
        var ledger = try watchTimer()
        ledger.settings.revision = ledger.nextRevision(writer: "phone")
        let restored = try LedgerBackup.decode(LedgerBackup(ledger: ledger).encoded()).ledger
        XCTAssertTrue(restored.settings.timerSystemAlarms)
        var receiver = Ledger(); receiver.merge(ledger)
        XCTAssertTrue(receiver.settings.timerSystemAlarms)
    }
    func testWatchOffersOnlyAnActiveLocalFutureTimer() throws {
        var ledger = try watchTimer()
        XCTAssertTrue(PhoneTimerAlarmPolicy.canOfferPhone(ledger, writer: "watch", isActive: true, now: now))
        XCTAssertFalse(PhoneTimerAlarmPolicy.canOfferPhone(ledger, writer: "watch", isActive: false, now: now))
        XCTAssertFalse(PhoneTimerAlarmPolicy.canOfferPhone(ledger, writer: "other", isActive: true, now: now))
        XCTAssertFalse(PhoneTimerAlarmPolicy.canOfferPhone(ledger, writer: "watch", isActive: true, now: now.addingTimeInterval(301)))
        XCTAssertFalse(PhoneTimerAlarmPolicy.canOfferPhone(ledger, writer: "watch", isActive: true, now: now.addingTimeInterval(286)))
        ledger.settings.timerSystemAlarms = false
        XCTAssertFalse(PhoneTimerAlarmPolicy.canOfferPhone(ledger, writer: "watch", isActive: true, now: now))
    }
    func testExplicitWatchChoicePersistsAcrossRestartButNotNextTask() throws {
        var ledger = try watchTimer()
        ledger.restartTimer(writer: "watch", onWatch: true, now: now)
        XCTAssertFalse(PhoneTimerAlarmPolicy.canOfferPhone(ledger, writer: "watch", isActive: true,
            watchOverrideTaskID: "one", now: now))
        ledger.finishTimer(writer: "watch", onWatch: true, now: now)
        XCTAssertTrue(PhoneTimerAlarmPolicy.canOfferPhone(ledger, writer: "watch", isActive: true,
            watchOverrideTaskID: "one", now: now))
    }
    func testPausedAndWaitingTimersDoNotOfferPhone() throws {
        var ledger = try watchTimer()
        ledger.pauseTimer(writer: "watch", onWatch: true, now: now.addingTimeInterval(10))
        XCTAssertFalse(PhoneTimerAlarmPolicy.canOfferPhone(ledger, writer: "watch", isActive: true, now: now))
        ledger.timerControl = nil
        XCTAssertFalse(PhoneTimerAlarmPolicy.canOfferPhone(ledger, writer: "watch", isActive: true, now: now))
    }
    func testPreparingPhoneCandidateDoesNotChangeWatchDeadlineOrQueue() throws {
        let original = try watchTimer(); var candidate = original
        candidate.moveTimerAlerts(writer: "phone", onWatch: false)
        XCTAssertTrue(original.timerControl!.onWatch)
        XCTAssertEqual(candidate.timerControl?.dueAt, original.timerControl?.dueAt)
        XCTAssertEqual(candidate.currentTimer, original.currentTimer)
        XCTAssertEqual(candidate.waitingTimers, original.waitingTimers)
        XCTAssertTrue(PhoneTimerAlarmPolicy.acceptsHandoff(original, expectedToken: original.timerControl!.token,
            candidate: candidate, phoneWriter: "phone", now: now))
    }
    func testRestartedOrCompletedTimerRejectsOldHandoff() throws {
        let original = try watchTimer(); var candidate = original
        candidate.moveTimerAlerts(writer: "phone", onWatch: false)
        var changed = original; changed.restartTimer(writer: "watch", onWatch: true, now: now)
        XCTAssertFalse(PhoneTimerAlarmPolicy.acceptsHandoff(changed, expectedToken: original.timerControl!.token,
            candidate: candidate, phoneWriter: "phone", now: now))
        changed = original; changed.finishTimer(writer: "watch", onWatch: true, now: now)
        XCTAssertFalse(PhoneTimerAlarmPolicy.acceptsHandoff(changed, expectedToken: original.timerControl!.token,
            candidate: candidate, phoneWriter: "phone", now: now))
    }
    func testHandoffCannotMoveDeadlineOrChangeTask() throws {
        let original = try watchTimer(); var candidate = original
        candidate.moveTimerAlerts(writer: "phone", onWatch: false)
        candidate.timerControl?.dueAt = now.addingTimeInterval(900)
        XCTAssertFalse(PhoneTimerAlarmPolicy.acceptsHandoff(original, expectedToken: original.timerControl!.token,
            candidate: candidate, phoneWriter: "phone", now: now))
        candidate = original; candidate.moveTimerAlerts(writer: "phone", onWatch: false)
        try candidate.editQueuedTimer("one", title: "Changed title", duration: 300, writer: "phone", onWatch: false, now: now)
        XCTAssertFalse(PhoneTimerAlarmPolicy.acceptsHandoff(original, expectedToken: original.timerControl!.token,
            candidate: candidate, phoneWriter: "phone", now: now))
    }
    func testHandoffRejectsWrongPhoneStaleRevisionAndExpiredTimer() throws {
        let original = try watchTimer(); var candidate = original
        candidate.moveTimerAlerts(writer: "phone", onWatch: false)
        XCTAssertFalse(PhoneTimerAlarmPolicy.acceptsHandoff(original, expectedToken: original.timerControl!.token,
            candidate: candidate, phoneWriter: "other", now: now))
        XCTAssertFalse(PhoneTimerAlarmPolicy.acceptsHandoff(original, expectedToken: original.timerControl!.token,
            candidate: candidate, phoneWriter: "phone", now: now.addingTimeInterval(301)))
        candidate.timerControl?.revision = original.timerControl!.revision
        XCTAssertFalse(PhoneTimerAlarmPolicy.acceptsHandoff(original, expectedToken: original.timerControl!.token,
            candidate: candidate, phoneWriter: "phone", now: now))
    }
    func testSystemAlarmOnlySchedulesForPhoneOwnerAndEnabledTrial() throws {
        var ledger = try watchTimer()
        XCTAssertFalse(PhoneTimerAlarmPolicy.schedulesSystemAlarm(ledger, writer: "phone"))
        ledger.moveTimerAlerts(writer: "phone", onWatch: false)
        XCTAssertTrue(PhoneTimerAlarmPolicy.schedulesSystemAlarm(ledger, writer: "phone"))
        XCTAssertFalse(PhoneTimerAlarmPolicy.schedulesSystemAlarm(ledger, writer: "other"))
        ledger.settings.timerSystemAlarms = false
        XCTAssertFalse(PhoneTimerAlarmPolicy.schedulesSystemAlarm(ledger, writer: "phone"))
    }
    func testPauseAndWatchTakeoverCancelPhoneEligibilityWithoutCompletingTask() throws {
        var ledger = try watchTimer(); ledger.moveTimerAlerts(writer: "phone", onWatch: false)
        ledger.pauseTimer(writer: "phone", onWatch: false, now: now.addingTimeInterval(30))
        XCTAssertFalse(PhoneTimerAlarmPolicy.schedulesSystemAlarm(ledger, writer: "phone"))
        ledger.resumeTimer(writer: "phone", onWatch: false, now: now.addingTimeInterval(40))
        XCTAssertTrue(PhoneTimerAlarmPolicy.schedulesSystemAlarm(ledger, writer: "phone"))
        let deadline = ledger.timerControl?.dueAt
        ledger.moveTimerAlerts(writer: "watch", onWatch: true)
        XCTAssertFalse(PhoneTimerAlarmPolicy.schedulesSystemAlarm(ledger, writer: "phone"))
        XCTAssertEqual(ledger.currentTimer?.id, "one"); XCTAssertEqual(ledger.timerControl?.dueAt, deadline)
    }
}
