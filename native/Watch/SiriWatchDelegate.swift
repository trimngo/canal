import WatchKit

final class SiriWatchDelegate: NSObject, WKApplicationDelegate {
    func applicationDidFinishLaunching() {
        LedgerStore.shared.start()
        NotificationScheduler.shared.configureActions()
    }

    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        let store = LedgerStore.shared; store.start()
        for task in backgroundTasks {
            if let connectivity = task as? WKWatchConnectivityRefreshBackgroundTask, let companion = store.companion {
                companion.holdBackgroundTask(connectivity)
            } else {
                if task is WKIntentDidRunRefreshBackgroundTask { store.refresh() }
                task.setTaskCompletedWithSnapshot(false)
            }
        }
    }
}
