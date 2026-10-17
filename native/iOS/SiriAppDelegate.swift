import UIKit
import Intents

final class SiriAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        NotificationScheduler.shared.configureActions()
        ReminderInbox.shared.registerBackgroundRefresh()
        return true
    }
    func application(_ application: UIApplication, handlerFor intent: INIntent) -> Any? {
        intent is INCreateNoteIntent ? SiriCaptureHandler() : nil
    }
}
