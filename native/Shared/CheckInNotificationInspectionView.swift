#if DEBUG && os(iOS)
import SwiftUI
import UserNotifications

/// UI checks inspect real pending requests instead of a mock scheduler.
struct CheckInNotificationInspectionView: View {
    @State private var requests: [UNNotificationRequest] = []
    @State private var replyAction = ""
    @State private var refreshing = false
    @State private var error: String?
    var body: some View {
        List {
            Button("Refresh scheduled check-ins") { refreshing = true; Task { await refresh() } }
                .accessibilityIdentifier("checkins.inspect.refresh").disabled(refreshing)
            Text("\(requests.count) check-ins").accessibilityIdentifier("checkins.inspect.count")
            Text(replyAction).accessibilityIdentifier("checkins.inspect.action")
            ForEach(Array(requests.prefix(3).enumerated()), id: \.offset) { index, request in
                Section {
                    Text(request.content.body).accessibilityIdentifier("checkins.inspect.body.\(index)")
                    Text(request.content.userInfo["urgentTaskText"] as? String ?? "No task")
                        .accessibilityIdentifier("checkins.inspect.task.\(index)")
                    Text(request.content.categoryIdentifier + (request.trigger?.repeats == true ? " · repeating" : " · queued"))
                        .accessibilityIdentifier("checkins.inspect.kind.\(index)")
                    Text("\(date(for: request).timeIntervalSince1970)")
                        .accessibilityIdentifier("checkins.inspect.date.\(index)")
                }
            }
            if let error { Text(error) }
        }.navigationTitle("Scheduled check-ins").task { await refresh() }
    }
    private func date(for request: UNNotificationRequest) -> Date {
        if let stamp = request.content.userInfo["scheduledAt"] as? Double { return Date(timeIntervalSince1970: stamp) }
        return (request.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate() ?? .distantFuture
    }
    private func refresh() async {
        refreshing = true; defer { refreshing = false }
        do {
            guard try await NotificationScheduler.shared.permission() else { throw NotificationError.denied }
            try await NotificationScheduler.shared.apply(LedgerStore.shared.ledger.settings, force: true)
            requests = await UNUserNotificationCenter.current().pendingNotificationRequests()
                .filter { $0.identifier.hasPrefix("checkin-") }.sorted { date(for: $0) < date(for: $1) }
            let categories = await UNUserNotificationCenter.current().notificationCategories()
            replyAction = categories.first { $0.identifier == "CHECKIN" }?.actions.first?.identifier ?? "Missing reply action"
        } catch { self.error = error.localizedDescription }
    }
}
#endif
