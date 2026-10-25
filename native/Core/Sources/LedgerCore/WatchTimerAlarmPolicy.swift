import Foundation

/// Watch alarms outlive the app process and can only be changed while the
/// app is active and holds the system session. Synced timer state is separate.
public enum WatchTimerAlarmPolicy {
    public static let runtimeLimit: TimeInterval = 30 * 60

    /// Token-only records from older builds have no known deadline after a
    /// phone edit. Retain them for WatchKit's maximum 36-hour scheduling
    /// horizon, then allow recovery after the runtime window also expires.
    public static func deadlineForLegacyRecord(scheduledToken: String, control: TimerQueueControl?,
                                               now: Date = Date()) -> Date {
        if control?.token == scheduledToken, let due = control?.dueAt { return due }
        return now.addingTimeInterval(36 * 60 * 60)
    }

    public static func scheduledRecordHasExpired(dueAt: Date, now: Date = Date()) -> Bool {
        now.timeIntervalSince(dueAt) >= runtimeLimit
    }

    public enum Update: Equatable {
        case unchanged, schedule, cancel, replace, waitForForeground, waitForSession
    }
    public enum Wake: Equatable { case ringCurrent, ringPrevious, cancel }

    public static func controlToSchedule(in ledger: Ledger, writer: String, silencedToken: String?,
                                         failedToken: String?, now: Date = Date()) -> TimerQueueControl? {
        guard ledger.currentTimer != nil, let control = ledger.timerControl,
              control.owner == writer, control.onWatch, let due = control.dueAt,
              control.token != silencedToken, control.token != failedToken,
              !scheduledRecordHasExpired(dueAt: due, now: now) else { return nil }
        return control
    }

    public static func update(scheduledToken: String?, requestedToken: String?,
                              isActive: Bool, hasSession: Bool) -> Update {
        if scheduledToken == requestedToken { return .unchanged }
        if scheduledToken != nil {
            guard isActive else { return .waitForForeground }
            // A persisted token isn't a session handle. After relaunch, wait
            // for WatchKit to deliver the old session before cancelling it.
            guard hasSession else { return .waitForSession }
            return requestedToken == nil ? .cancel : .replace
        }
        return isActive ? .schedule : .waitForForeground
    }

    public static func wake(scheduledToken: String?, requestedToken: String?, isActive: Bool) -> Wake {
        if let scheduledToken, scheduledToken == requestedToken { return .ringCurrent }
        // A background session cannot be cancelled. It must alert rather than
        // silently consume its runtime and trigger a system warning.
        return isActive ? .cancel : .ringPrevious
    }
}
