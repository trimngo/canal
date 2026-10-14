import Foundation
import Combine
import UserNotifications
import LedgerCore

@MainActor
final class NotificationScheduler: NSObject, UNUserNotificationCenterDelegate, ObservableObject {
    static let shared = NotificationScheduler()
    @Published var status = "Not enabled"
    private let center = UNUserNotificationCenter.current()
    private var applied: Settings?
    private override init() { super.init(); center.delegate = self }

    func configureActions() {
        let open = UNNotificationAction(identifier: "OPEN_CHECKIN", title: "Log what I was doing", options: [.foreground])
        center.setNotificationCategories([UNNotificationCategory(identifier: "CHECKIN", actions: [open], intentIdentifiers: [])])
    }

    func permission() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    func refreshStatus() async {
        let value = await center.notificationSettings()
        switch value.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            #if os(iOS)
            status = "Allowed · check-ins scheduled on iPhone"
            #else
            status = "Allowed · check-in alerts come from iPhone"
            #endif
        case .denied: status = "Blocked in system notification settings"
        default: status = "Not enabled"
        }
    }

    func apply(_ settings: Settings) async throws {
        configureActions(); await refreshStatus()
        #if os(iOS)
        guard applied != settings else { return }
        let minutes = try settings.notificationMinutes()
        let pending = await center.pendingNotificationRequests()
        let ids = pending.filter { $0.identifier.hasPrefix("checkin-") }.map(\.identifier)
        center.removePendingNotificationRequests(withIdentifiers: ids)
        if settings.notificationsEnabled {
            let permission = await center.notificationSettings().authorizationStatus
            guard permission == .authorized || permission == .provisional else { applied = nil; return }
            do {
                for minute in minutes {
                    let content = UNMutableNotificationContent()
                    content.title = "What were you doing?"
                    content.body = "Log the last 15 minutes. Categorize now or later."
                    content.sound = .default; content.categoryIdentifier = "CHECKIN"
                    content.userInfo = ["minute": minute]
                    var components = DateComponents(); components.hour = minute / 60; components.minute = minute % 60
                    let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
                    try await center.add(UNNotificationRequest(identifier: "checkin-\(minute)", content: content, trigger: trigger))
                }
            } catch {
                center.removePendingNotificationRequests(withIdentifiers: minutes.map { "checkin-\($0)" })
                applied = nil; throw error
            }
        }
        applied = settings
        #endif
    }

    func sendTest() async throws {
        guard try await permission() else { throw NotificationError.denied }
        let content = UNMutableNotificationContent()
        content.title = "Time Ledger test"
        content.body = "If you see this, native notifications are working."
        content.sound = .default
        try await center.add(UNNotificationRequest(identifier: "notification-test", content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: 15, repeats: false)))
        await refreshStatus()
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard response.notification.request.content.categoryIdentifier == "CHECKIN" else { return }
        let delivered = response.notification.date
        let minute = response.notification.request.content.userInfo["minute"] as? Int
        var calendar = Calendar.current
        calendar.timeZone = .current
        let scheduled = minute.flatMap { calendar.date(bySettingHour: $0 / 60, minute: $0 % 60, second: 0, of: delivered) }
        let end = Ledger.slotEnd(at: scheduled ?? delivered)
        await MainActor.run { LedgerStore.shared.selectedSlot = min(end, Ledger.slotEnd(at: Date())) }
    }
}

enum NotificationError: LocalizedError {
    case denied
    var errorDescription: String? { "Allow notifications in your device Settings, then try again." }
}
