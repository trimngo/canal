#if os(iOS)
import AppIntents

/// Stopping a system alarm only silences it. Task completion stays explicit.
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
        await NotificationScheduler.shared.applyTimer(store.ledger, writer: store.writer)
        #endif
        return .result()
    }
}
#endif
