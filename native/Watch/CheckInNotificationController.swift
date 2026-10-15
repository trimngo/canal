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
    @StateObject private var store = LedgerStore.shared
    var body: some View {
        TimelineView(.periodic(from: Date(), by: 60)) { _ in
            let now = Date()
            VStack(alignment: .leading, spacing: 8) {
                Text("What are you doing right now?").font(.headline)
                Text("Today, from your first log").font(.caption2).foregroundStyle(.secondary)
                ForEach(store.ledger.breakdown(on: now, now: now).filter { $0.minutes > 0 }.sorted { $0.minutes > $1.minutes }) { row in
                    Text("\(row.name): \(row.percent, specifier: "%.0f")% · \(store.duration(row.minutes))").font(.caption)
                }
                Text("Based on logs available on this Watch.").font(.caption2).foregroundStyle(.secondary)
            }
        }.task { store.start() }
    }
}
