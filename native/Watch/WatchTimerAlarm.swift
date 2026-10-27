import Foundation
import Combine
import WatchKit
import LedgerCore

/// The Watch schedules its own alarm; the system owns repeating haptics.
@MainActor
final class WatchTimerAlarm: NSObject, ObservableObject, WKExtendedRuntimeSessionDelegate {
    static let shared = WatchTimerAlarm()
    @Published private(set) var status = ""
    @Published private(set) var needsAlarmUpdate = false
    private var session: WKExtendedRuntimeSession?
    private weak var notifiedSession: WKExtendedRuntimeSession?
    private var token: String?
    private let scheduledKey = "timers.watch-alarm.scheduled"
    private let scheduledDueKey = "timers.watch-alarm.due"
    private let silencedKey = "timers.watch-alarm.silenced"
    private let failedKey = "timers.watch-alarm.failed"
    private var preferences: UserDefaults { .standard }
    private var scheduledToken: String? { preferences.string(forKey: scheduledKey) }
    private var isActive: Bool { WKApplication.shared().applicationState == .active }
    private var supportsRepeatingAlarm: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        return true
        #endif
    }

    func isArmed(for token: String) -> Bool {
        scheduledToken == token && session?.state != .invalid && !isSilenced(for: token)
            && preferences.string(forKey: failedKey) != token
    }
    func isSilenced(for token: String) -> Bool { preferences.string(forKey: silencedKey) == token }
    func canTransferToPhone(_ token: String) -> Bool {
        PhoneTimerAlarmPolicy.watchCanFinishTransfer(currentToken: token, scheduledToken: scheduledToken,
            hasSession: session != nil && session?.state != .invalid, isActive: isActive)
    }

    private func requestedControl(_ ledger: Ledger, writer: String) -> TimerQueueControl? {
        WatchTimerAlarmPolicy.controlToSchedule(in: ledger, writer: writer,
            silencedToken: preferences.string(forKey: silencedKey), failedToken: preferences.string(forKey: failedKey))
    }

    func update(ledger: Ledger, writer: String) {
        guard supportsRepeatingAlarm else { status = "Repeating alarm requires a physical Watch"; return }
        let requested = requestedControl(ledger, writer: writer)
        // Migrate token-only records once. A changed phone control cannot
        // supply the old deadline; use a bounded, conservative horizon.
        if let scheduledToken, preferences.object(forKey: scheduledDueKey) == nil {
            preferences.set(WatchTimerAlarmPolicy.deadlineForLegacyRecord(
                scheduledToken: scheduledToken, control: ledger.timerControl), forKey: scheduledDueKey)
        }
        // After process termination, only discard an unadopted alarm record
        // once the system's entire runtime window has elapsed.
        if session == nil, let due = preferences.object(forKey: scheduledDueKey) as? Date,
           WatchTimerAlarmPolicy.scheduledRecordHasExpired(dueAt: due) { clearScheduled() }

        switch WatchTimerAlarmPolicy.update(scheduledToken: scheduledToken, requestedToken: requested?.token,
                                            isActive: isActive, hasSession: session != nil) {
        case .waitForForeground:
            needsAlarmUpdate = scheduledToken != nil
            status = needsAlarmUpdate ? "Open Dash on Watch to apply timer changes · previous alarm still scheduled"
                                      : "Open Dash on Watch to arm the repeating alarm"
            return
        case .waitForSession:
            needsAlarmUpdate = true
            status = "Previous Watch alarm still scheduled · tap Stop if it rings"
            return
        case .cancel, .replace:
            stop()
        case .unchanged:
            needsAlarmUpdate = false
            if let due = requested?.dueAt {
                status = due > Date() ? "Repeating alarm scheduled on Watch" : "Timer finished · waiting for you"
                if let session, session.state == .running { ring(session) }
                return
            }
        case .schedule: break
        }

        needsAlarmUpdate = false
        guard let requested, let due = requested.dueAt else {
            status = idleStatus(ledger, writer: writer); return
        }
        // No suspension point between checking active state and scheduling.
        let value = WKExtendedRuntimeSession()
        session = value; token = requested.token; value.delegate = self
        preferences.set(requested.token, forKey: scheduledKey)
        let start = max(due, Date().addingTimeInterval(1))
        preferences.set(start, forKey: scheduledDueKey)
        status = "Repeating alarm scheduled on Watch"
        value.start(at: start)
    }

    private func idleStatus(_ ledger: Ledger, writer: String) -> String {
        guard ledger.currentTimer != nil, let control = ledger.timerControl else { return "" }
        if control.owner != writer || !control.onWatch { return "Timer alerts on iPhone" }
        if control.dueAt == nil { return "Paused" }
        if isSilenced(for: control.token) { return "Alarm silenced · choose Done & Next or Restart" }
        if preferences.string(forKey: failedKey) == control.token {
            return "Repeating alarm unavailable · open timer and tap Restart to retry"
        }
        return "Finished · alarm session ended"
    }

    private func clearScheduled() {
        preferences.removeObject(forKey: scheduledKey)
        preferences.removeObject(forKey: scheduledDueKey)
    }
    private func stop() {
        guard isActive, let old = session else { return }
        session = nil; token = nil; clearScheduled()
        old.invalidate()
    }
    func adopt(_ value: WKExtendedRuntimeSession) {
        // Set the delegate synchronously, before the launch handler returns.
        session = value; token = scheduledToken ?? UUID().uuidString
        preferences.set(token, forKey: scheduledKey)
        if let expiration = value.expirationDate {
            preferences.set(expiration.addingTimeInterval(-WatchTimerAlarmPolicy.runtimeLimit), forKey: scheduledDueKey)
        } else if preferences.object(forKey: scheduledDueKey) == nil {
            preferences.set(Date(), forKey: scheduledDueKey)
        }
        value.delegate = self
        if value.state == .running { ring(value) }
    }
    private func ring(_ value: WKExtendedRuntimeSession, updateHaptics: Bool = false) {
        guard value === session, value.state == .running else { return }
        let store = LedgerStore.shared
        let requested = requestedControl(store.ledger, writer: store.writer)
        switch WatchTimerAlarmPolicy.wake(scheduledToken: token, requestedToken: requested?.token, isActive: isActive) {
        case .cancel:
            stop()
            store.refreshTimerSupport(force: true)
            return
        case .ringCurrent:
            needsAlarmUpdate = false
            status = "Timer finished · repeating alarm"
        case .ringPrevious:
            needsAlarmUpdate = true
            status = "Previous Watch timer · open Dash to apply phone changes"
        }
        let firstAlert = notifiedSession !== value
        guard firstAlert || updateHaptics else { return }
        notifiedSession = value
        // Every managed running session alerts, even if a phone edit made it
        // stale while background cancellation was forbidden by WatchKit.
        let pattern = preferences.string(forKey: "timers.haptic-pattern") ?? "standard"
        let type: WKHapticType = pattern == "attention" ? .retry : pattern == "light" ? .click : .notification
        let saved = preferences.double(forKey: "timers.haptic-repeat")
        let interval = saved.isFinite && saved > 0 ? min(60, max(1, saved)) : 3
        value.notifyUser(hapticType: type) { _ in interval }
        // Queue/settings views refresh alarm support when they appear. The
        // system already repeats the haptic; do not navigate away on refresh.
        if firstAlert { store.openTimers() }
    }
    func refreshHaptics() { if let session, session.state == .running { ring(session, updateHaptics: true) } }
    nonisolated func extendedRuntimeSessionDidStart(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        Task { @MainActor in self.ring(extendedRuntimeSession) }
    }
    nonisolated func extendedRuntimeSessionWillExpire(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        Task { @MainActor in if self.session === extendedRuntimeSession { self.status = "Alarm session is ending" } }
    }
    nonisolated func extendedRuntimeSession(_ extendedRuntimeSession: WKExtendedRuntimeSession,
                                          didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason, error: Error?) {
        Task { @MainActor in
            guard self.session === extendedRuntimeSession else { return }
            if let token = self.token {
                self.preferences.set(token, forKey: error == nil ? self.silencedKey : self.failedKey)
            }
            self.clearScheduled(); self.session = nil; self.token = nil; self.needsAlarmUpdate = false
            let store = LedgerStore.shared
            // An old callback cannot silence a newer timer. Only failures use
            // notification fallback; the system Stop button stays silent.
            self.status = self.idleStatus(store.ledger, writer: store.writer)
            await NotificationScheduler.shared.applyTimer(store.ledger, writer: store.writer)
        }
    }
}
