import SwiftUI
import WatchKit
import UserNotifications

final class CheckInNotificationController: WKUserNotificationHostingController<WatchPromptView> {
    override var body: WatchPromptView { WatchPromptView() }
    override func didReceive(_ notification: UNNotification) {
        Task { @MainActor in LedgerStore.shared.beginSample() }
    }
}

struct WatchPromptView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What are you doing right now?").font(.headline)
            Text("Record this moment. Categorize now or later.").font(.caption)
        }
    }
}
