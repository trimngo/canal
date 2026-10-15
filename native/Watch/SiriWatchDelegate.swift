import WatchKit
import Intents

final class SiriWatchDelegate: NSObject, WKApplicationDelegate {
    func applicationDidFinishLaunching() {
        NotificationScheduler.shared.configureActions()
    }
    func handle(_ intent: INIntent, completionHandler: @escaping (INIntentResponse) -> Void) {
        guard let note = intent as? INCreateNoteIntent else {
            completionHandler(INCreateNoteIntentResponse(code: .failure, userActivity: nil))
            return
        }
        SiriCaptureHandler().handle(intent: note) { completionHandler($0) }
    }
}
