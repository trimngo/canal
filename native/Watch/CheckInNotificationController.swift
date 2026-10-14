import SwiftUI
import WatchKit
import UserNotifications
import LedgerCore

final class CheckInNotificationController: WKUserNotificationHostingController<WatchPromptView> {
    private var end = Ledger.slotEnd(at: Date())
    override var body: WatchPromptView { WatchPromptView(end: end) }
    override func didReceive(_ notification: UNNotification) {
        let minute = notification.request.content.userInfo["minute"] as? Int
        let scheduled = minute.flatMap { Calendar.current.date(bySettingHour: $0 / 60, minute: $0 % 60, second: 0, of: notification.date) }
        end = Ledger.slotEnd(at: scheduled ?? notification.date)
        // Preserve the prompted interval if the user opens the Watch app later.
        LedgerStore.shared.selectedSlot = min(end, Ledger.slotEnd(at: Date()))
    }
}

struct WatchPromptView: View {
    let end: Date
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What were you doing?").font(.headline)
            Text(LedgerStore.shared.interval(end)).font(.caption)
            Text("Log the last 15 minutes. Categorize now or later.").font(.caption)
        }
    }
}
