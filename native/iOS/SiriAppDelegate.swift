import UIKit
import Intents

final class SiriAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // WatchConnectivity can launch us without creating a visible scene.
        // Install its delegate now, rather than waiting for a SwiftUI task.
        LedgerStore.shared.start()
        NotificationScheduler.shared.configureActions()
        NotificationScheduler.shared.registerBackgroundRefresh()
        ReminderInbox.shared.registerBackgroundRefresh()
        return true
    }
    func application(_ application: UIApplication, handlerFor intent: INIntent) -> Any? {
        intent is INCreateNoteIntent ? SiriCaptureHandler() : nil
    }
}
