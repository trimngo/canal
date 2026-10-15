import Foundation
import Combine
import UserNotifications
import LedgerCore
#if os(watchOS)
import WatchKit
#endif

@MainActor
final class NotificationScheduler: NSObject, UNUserNotificationCenterDelegate, ObservableObject {
    static let shared = NotificationScheduler()
    @Published var status = "Not enabled"
    private let center = UNUserNotificationCenter.current()
    private var applied: Settings?
    private let promptBody = "Dictate what you’re doing. It saves when you finish."
    private override init() { super.init(); center.delegate = self }

    func configureActions() {
        let reply = UNTextInputNotificationAction(identifier: "QUICK_LOG", title: "Dictate log", options: [],
            textInputButtonTitle: "Save", textInputPlaceholder: "What are you doing now?")
        center.setNotificationCategories([UNNotificationCategory(identifier: "CHECKIN", actions: [reply], intentIdentifiers: [])])
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
                    content.title = "What are you doing right now?"
                    content.body = promptBody
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
        content.body = promptBody
        content.sound = .default
        content.categoryIdentifier = "CHECKIN"
        try await center.add(UNNotificationRequest(identifier: "notification-test", content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: 15, repeats: false)))
        await refreshStatus()
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        guard response.notification.request.content.categoryIdentifier == "CHECKIN",
              response.actionIdentifier != UNNotificationDismissActionIdentifier else {
            completionHandler(); return
        }
        if response.actionIdentifier == "QUICK_LOG", let reply = response as? UNTextInputNotificationResponse {
            let text = reply.userText
            let timestamp = Date()
            let id = Self.replyID(for: response.notification)
            Task { @MainActor in
                do {
                    try LedgerStore.shared.saveQuickSample(text, id: id, at: timestamp)
                    center.removeDeliveredNotifications(withIdentifiers: [response.notification.request.identifier])
                    #if os(watchOS)
                    WKInterfaceDevice.current().play(.success)
                    #endif
                } catch {
                    LedgerStore.shared.quickReplyDraft = text
                    LedgerStore.shared.beginSample()
                    LedgerStore.shared.report(error)
                }
                completionHandler()
            }
        } else {
            // Default taps and the old foreground action still open logging.
            Task { @MainActor in self.presentSample() }
            completionHandler()
        }
    }

    nonisolated static func replyID(for notification: UNNotification) -> String {
        "notification-\(notification.request.identifier)-\(notification.date.timeIntervalSince1970)"
    }

    func presentSample() { LedgerStore.shared.beginSample() }
}

enum NotificationError: LocalizedError {
    case denied
    var errorDescription: String? { "Allow notifications in your device Settings, then try again." }
}
