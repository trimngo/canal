#if os(iOS)
import AppIntents

/// Stop silences the alarm. Completion is a separate, explicit preference;
/// the matching expired token protects the next timer from repeated callbacks.
struct SilenceTimerAlarmIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Silence timer alarm"
    static var openAppWhenRun = false
    static var isDiscoverable = false
    @Parameter(title: "Timer") var token: String
    init() {}
    init(token: String) { self.token = token }
    @MainActor
    func perform() async throws -> some IntentResult {
        #if !LEDGER_WIDGETS_EXTENSION
        let store = LedgerStore.shared; store.start()
        await PhoneTimerAlarm.shared.silence(token)
        try store.completeStoppedSystemAlarm(expectedToken: token)
        await TimerLiveActivity.shared.refresh(store.ledger)
        await NotificationScheduler.shared.applyTimer(store.ledger, writer: store.writer)
        #endif
        return .result()
    }
}
#endif
