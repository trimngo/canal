import WatchKit

final class SiriWatchDelegate: NSObject, WKApplicationDelegate {
    func applicationDidFinishLaunching() {
        LedgerStore.shared.start()
        NotificationScheduler.shared.configureActions()
        Task { @MainActor in try? await NotificationScheduler.shared.apply(LedgerStore.shared.ledger.settings, force: true) }
    }

    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        let store = LedgerStore.shared; store.start()
        for task in backgroundTasks {
            if let connectivity = task as? WKWatchConnectivityRefreshBackgroundTask, let companion = store.companion {
                companion.holdBackgroundTask(connectivity)
            } else if let refresh = task as? WKApplicationRefreshBackgroundTask {
                Task { @MainActor in
                    try? await NotificationScheduler.shared.apply(store.ledger.settings, force: true)
                    refresh.setTaskCompletedWithSnapshot(false)
                }
            } else {
                if task is WKIntentDidRunRefreshBackgroundTask { store.refresh() }
                task.setTaskCompletedWithSnapshot(false)
            }
        }
    }
}
