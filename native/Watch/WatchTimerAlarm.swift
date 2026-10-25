import Foundation
import Combine
import WatchKit
import LedgerCore

/// The Watch schedules its own alarm; the system owns repeating haptics.
@MainActor
final class WatchTimerAlarm: NSObject, ObservableObject, WKExtendedRuntimeSessionDelegate {
    static let shared = WatchTimerAlarm()
    @Published private(set) var status = ""
    private var session: WKExtendedRuntimeSession?
    private var token: String?
    private let scheduledKey = "timers.watch-alarm.scheduled"
    private let silencedKey = "timers.watch-alarm.silenced"
    func isArmed(for token: String) -> Bool {
        UserDefaults.standard.string(forKey: scheduledKey) == token && UserDefaults.standard.string(forKey: silencedKey) != token
    }
    func update(ledger: Ledger, writer: String) {
        guard ledger.currentTimer != nil, let control = ledger.timerControl else { stop(); status = ""; return }
        guard control.owner == writer, control.onWatch else { stop(); status = "Timer alerts on iPhone"; return }
        guard let due = control.dueAt else { stop(); status = "Paused"; return }
        #if targetEnvironment(simulator)
        status = "Repeating alarm requires a physical Watch"; return
        #else
        if UserDefaults.standard.string(forKey: silencedKey) == control.token { status = "Alarm silenced · choose Done & Next or Restart"; return }
        if Date().timeIntervalSince(due) >= 1800 { status = "Finished · alarm session ended"; return }
        if isArmed(for: control.token) { status = due > Date() ? "Repeating alarm scheduled on Watch" : "Timer finished · waiting for you"; return }
        guard WKApplication.shared().applicationState == .active else { status = "Open Dash on Watch to arm the repeating alarm"; return }
        stop()
        // Arm before returning from the user's action. A delayed task can lose
        // active state as soon as the person lowers their wrist after Done.
        let value = WKExtendedRuntimeSession()
        session = value; token = control.token; value.delegate = self
        UserDefaults.standard.set(control.token, forKey: scheduledKey)
        status = "Repeating alarm scheduled on Watch"
        value.start(at: max(due, Date().addingTimeInterval(1)))
        #endif
    }
    private func stop() {
        guard session == nil || WKApplication.shared().applicationState == .active else {
            status = "Open Dash on Watch to update the alarm"; return
        }
        let old = session; session = nil; token = nil
        UserDefaults.standard.removeObject(forKey: scheduledKey)
        old?.invalidate()
    }
    func adopt(_ value: WKExtendedRuntimeSession) {
        // Must assign the delegate before the launch handler returns.
        session = value; token = UserDefaults.standard.string(forKey: scheduledKey)
        value.delegate = self
        if value.state == .running { ring(value) }
    }
    private func ring(_ value: WKExtendedRuntimeSession) {
        guard value === session, let token, LedgerStore.shared.ledger.timerControl?.token == token,
              LedgerStore.shared.ledger.currentTimer != nil else { return }
        status = "Timer finished · repeating alarm"
        LedgerStore.shared.openTimers()
        let preferences = UserDefaults.standard
        let pattern = preferences.string(forKey: "timers.haptic-pattern") ?? "standard"
        let type: WKHapticType = pattern == "attention" ? .retry : pattern == "light" ? .click : .notification
        let saved = preferences.double(forKey: "timers.haptic-repeat")
        let interval = saved > 0 ? min(60, max(1, saved)) : 3
        value.notifyUser(hapticType: type) { _ in interval }
    }
    func refreshHaptics() { if let session, session.state == .running { ring(session) } }
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
            if let token = self.token { UserDefaults.standard.set(token, forKey: self.silencedKey) }
            UserDefaults.standard.removeObject(forKey: self.scheduledKey)
            self.session = nil
            self.status = error == nil ? "Alarm silenced · choose Done & Next or Restart" : "Repeating alarm unavailable · open timer and tap Restart to retry"
            if error != nil {
                let store = LedgerStore.shared
                await NotificationScheduler.shared.applyTimer(store.ledger, writer: store.writer)
            }
        }
    }
}
