import Foundation

/// The timer remains one shared task. Alert delivery is a separate, confirmed
/// device choice; availability alone never proves that an alarm was scheduled.
public enum PhoneTimerAlarmPolicy {
    public static let minimumHandoffRemaining: TimeInterval = 15
    public static let offerLifetime: TimeInterval = 10
    public static func offerCanCommit(expiresAt: Date, now: Date = Date()) -> Bool {
        let remaining = expiresAt.timeIntervalSince(now)
        return remaining >= 1 && remaining <= offerLifetime + 1
    }
    public static func keepsScheduledAlarm(savedToken: String, savedDueAt: Date, savedTitle: String,
                                           token: String, dueAt: Date, title: String,
                                           now: Date = Date()) -> Bool {
        savedToken == token && savedDueAt == dueAt && (savedTitle == title || dueAt <= now)
    }
    public static func absentAlarmHasFinished(dueAt: Date, schedulingConfirmed: Bool,
                                              now: Date = Date()) -> Bool {
        schedulingConfirmed && dueAt <= now
    }

    public static func watchCanFinishTransfer(currentToken: String, scheduledToken: String?,
                                              hasSession: Bool, isActive: Bool) -> Bool {
        guard isActive else { return false }
        return scheduledToken == nil || (scheduledToken == currentToken && hasSession)
    }
    public static func canOfferPhone(_ ledger: Ledger, writer: String, isActive: Bool,
                                     watchOverrideTaskID: String? = nil,
                                     now: Date = Date()) -> Bool {
        guard ledger.settings.timerSystemAlarms, isActive, ledger.currentTimer != nil,
              let control = ledger.timerControl, control.owner == writer, control.onWatch,
              ledger.currentTimer?.id != watchOverrideTaskID,
              let due = control.dueAt, due.timeIntervalSince(now) >= minimumHandoffRemaining else { return false }
        return true
    }

    public static func acceptsHandoff(_ current: Ledger, expectedToken: String,
                                      candidate: Ledger, phoneWriter: String,
                                      now: Date = Date()) -> Bool {
        guard current.currentTimer != nil, let old = current.timerControl,
              old.token == expectedToken, old.onWatch, let due = old.dueAt, due > now,
              let next = candidate.timerControl else { return false }
        return current.currentTimer == candidate.currentTimer && next.taskID == old.taskID && next.dueAt == due && next.pausedRemaining == nil
            && next.owner == phoneWriter && !next.onWatch && next.revision > old.revision
    }

    public static func schedulesSystemAlarm(_ ledger: Ledger, writer: String) -> Bool {
        guard ledger.settings.timerSystemAlarms, ledger.currentTimer != nil,
              let control = ledger.timerControl, control.owner == writer, !control.onWatch,
              control.dueAt != nil else { return false }
        return true
    }
}
