#if os(iOS)
import AppIntents

/// LiveActivityIntent executes in the containing iPhone app, including actions
/// forwarded by a mirrored Live Activity on Mac. The widget never writes data.
struct RestartTimerIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Restart timer"
    static var description = IntentDescription("Restart the current task for its full duration.")
    static var openAppWhenRun = false
    static var isDiscoverable = false

    @Parameter(title: "Timer") var token: String
    init() {}
    init(token: String) { self.token = token }

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !LEDGER_WIDGETS_EXTENSION
        let store = LedgerStore.shared
        store.start()
        // Ignore an old displayed button after another control or task change.
        try store.changeTimer("restart", expectedToken: token)
        await NotificationScheduler.shared.applyTimer(store.ledger, writer: store.writer)
        await TimerLiveActivity.shared.refresh(store.ledger)
        #endif
        return .result()
    }
}
#endif
