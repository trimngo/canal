import Foundation
import Combine
import UserNotifications
import LedgerCore
#if os(watchOS)
import WatchKit
#endif
#if os(iOS)
import BackgroundTasks
#endif

@MainActor
final class NotificationScheduler: NSObject, UNUserNotificationCenterDelegate, ObservableObject {
    static let shared = NotificationScheduler()
    @Published var status = "Not enabled"
    @Published private(set) var permissionGranted = false
    @Published private(set) var pendingCheckIns = 0
    @Published private(set) var nextCheckIn: Date?
    private let center = UNUserNotificationCenter.current()
    @Published private(set) var scheduleStatus = ""
    private var applyTask: Task<Void, Error>?
    private var timerTask: Task<Void, Never>?
    @Published private(set) var timerStatus = ""
    private let configurationKey = "notifications.schedule-configuration.v2"
    #if os(iOS)
    static let backgroundIdentifier = "com.trimngo.TimeLedger.checkins-refresh"
    #endif
    private var lastConfiguration: Data?
    private var lastChecked = Date.distantPast
    private var lastUsedQueue = false
    private static var isWatch: Bool {
        #if os(watchOS)
        return true
        #else
        return false
        #endif
    }
    private let promptBody = "Tap to type or dictate what you’re doing now."
    private override init() { super.init(); center.delegate = self }

    func configureActions() {
        let reply = UNTextInputNotificationAction(identifier: "QUICK_LOG", title: "Dictate log", options: [],
            textInputButtonTitle: "Save", textInputPlaceholder: "What are you doing now?")
        let done = UNNotificationAction(identifier: "TIMER_DONE", title: "Done", options: [.foreground])
        let restart = UNNotificationAction(identifier: "TIMER_RESTART", title: "Restart", options: [.foreground])
        center.setNotificationCategories([UNNotificationCategory(identifier: "CHECKIN", actions: [reply], intentIdentifiers: []),
            UNNotificationCategory(identifier: "TASK_TIMER", actions: [done, restart], intentIdentifiers: [])])
    }

    func permission() async throws -> Bool {
        let allowed = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        await refreshStatus()
        return allowed
    }

    func refreshStatus() async {
        let value = await center.notificationSettings()
        permissionGranted = false
        switch value.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            permissionGranted = true
            #if os(iOS)
            status = "Notifications allowed on iPhone"
            #else
            status = "Notifications allowed on Apple Watch"
            #endif
        case .denied: status = "Blocked in system notification settings"
        default: status = "Not enabled"
        }
        if value.authorizationStatus == .provisional {
            status = "Quiet delivery is enabled. Allow alerting notifications in system settings."
        } else if permissionGranted, value.alertSetting == .disabled {
            status = "Notification alerts are disabled in system settings."
        }
        let requests = await center.pendingNotificationRequests().filter { $0.identifier.hasPrefix("checkin-") }
        pendingCheckIns = requests.count
        nextCheckIn = requests.compactMap { request -> Date? in
            if let stamp = request.content.userInfo["scheduledAt"] as? Double {
                let date = Date(timeIntervalSince1970: stamp)
                return date > Date() ? date : nil
            }
            if let trigger = request.trigger as? UNCalendarNotificationTrigger { return trigger.nextTriggerDate() }
            if let trigger = request.trigger as? UNTimeIntervalNotificationTrigger { return trigger.nextTriggerDate() }
            return nil
        }.min()
    }

    func apply(_ settings: Settings, force: Bool = false) async throws {
        // Save, foreground, and Watch sync can all request a refill at once.
        // Serialize changes so they cannot delete or duplicate each other's queue.
        let previous = applyTask
        let task = Task { @MainActor in
            _ = try? await previous?.value
            try await self.applySerially(settings, force: force)
        }
        applyTask = task
        try await task.value
    }

    private func applySerially(_ settings: Settings, force: Bool) async throws {
        try settings.validateNotificationSettings()
        let calendar = Calendar.current
        let configuration = Configuration(settings: settings, timeZone: calendar.timeZone.identifier)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let encoded = try encoder.encode(configuration)
        // Ranking and log edits invoke save observers too. Most saves need no
        // notification I/O; queued schedules need at most one refill per minute.
        if !force, lastConfiguration == encoded,
           !lastUsedQueue || Date().timeIntervalSince(lastChecked) < 60 { return }
        configureActions(); await refreshStatus()
        let pending = await center.pendingNotificationRequests()
        let checkIns = pending.filter { $0.identifier.hasPrefix("checkin-") }
        let changed = UserDefaults.standard.data(forKey: configurationKey) != encoded
        let permission = await center.notificationSettings().authorizationStatus
        let runsHere = settings.notificationDelivery.schedulesLocally(onWatch: Self.isWatch)
        guard settings.notificationsEnabled, runsHere, permission == .authorized || permission == .provisional else {
            center.removePendingNotificationRequests(withIdentifiers: checkIns.map(\.identifier))
            UserDefaults.standard.removeObject(forKey: configurationKey)
            cancelBackgroundRefresh()
            if !settings.notificationsEnabled { scheduleStatus = "Check-ins are off." }
            else if !runsHere {
                scheduleStatus = Self.isWatch ? "Automatic: iPhone schedules check-ins. Apple routes each alert to your phone or Watch."
                    : "Check-ins are assigned to Apple Watch. Open Dash on your Watch to check notification permission."
            } else { scheduleStatus = "No check-ins scheduled. Allow notifications on this device to start." }
            lastConfiguration = encoded; lastChecked = Date(); lastUsedQueue = false
            await refreshStatus()
            return
        }
        // Reserve a slot for the existing delivery-test notification, and respect
        // other pending requests rather than assuming all 64 belong to check-ins.
        let capacity = max(0, 62 - (pending.count - checkIns.count))
        let repeating = try settings.notificationSchedule()
        let queued = settings.usesQueuedNotifications || repeating.count > capacity
        let reusable = !changed && checkIns.allSatisfy { ($0.trigger?.repeats ?? false) != queued }
        if !reusable { center.removePendingNotificationRequests(withIdentifiers: checkIns.map(\.identifier)) }
        do {
            if queued {
                let now = Date()
                // Store the absolute date explicitly: a relative trigger's
                // nextTriggerDate must not slide forward on every refill.
                let kept = reusable ? checkIns.compactMap { request -> Date? in
                    guard let stamp = request.content.userInfo["scheduledAt"] as? Double else { return nil }
                    return Date(timeIntervalSince1970: stamp)
                }.filter { $0 > now }.sorted() : []
                let dates = try settings.notificationQueue(existing: kept, now: now, capacity: min(60, capacity), calendar: calendar)
                let existing = Set(kept)
                for date in dates where !existing.contains(date) {
                    // Absolute intervals keep the chosen random gaps intact over
                    // DST. On a time-zone change we rebuild for the new window.
                    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, date.timeIntervalSinceNow), repeats: false)
                    let message = content(); message.userInfo["scheduledAt"] = date.timeIntervalSince1970
                    try await center.add(UNNotificationRequest(identifier: "checkin-once-\(UUID().uuidString)", content: message, trigger: trigger))
                }
                if let through = dates.last {
                    let formatter = DateFormatter(); formatter.dateStyle = .medium; formatter.timeStyle = .short
                    scheduleStatus = "Scheduled through \(formatter.string(from: through)). Opening Dash or saving a log refills the queue. Background refresh is best effort."
                } else { scheduleStatus = "No check-ins scheduled. Open Dash to try again." }
                scheduleBackgroundRefresh()
            } else {
                let existing = reusable ? Set(checkIns.map(\.identifier)) : []
                for time in repeating where !existing.contains(time.id) {
                    var components = DateComponents(); components.hour = time.hour; components.minute = time.minute; components.second = 0
                    let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
                    try await center.add(UNNotificationRequest(identifier: time.id, content: content(), trigger: trigger))
                }
                scheduleStatus = "Repeats automatically until turned off."
                cancelBackgroundRefresh()
            }
            UserDefaults.standard.set(encoded, forKey: configurationKey)
            lastConfiguration = encoded; lastChecked = Date(); lastUsedQueue = queued
            await refreshStatus()
        } catch {
            // Keep successfully queued alerts. A later refill reconciles them;
            // losing network/background time must never erase saved log entries.
            scheduleStatus = "Could not finish scheduling. Open Dash to retry."
            throw error
        }
    }

    private func content() -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = "What are you doing right now?"; content.body = promptBody
        content.sound = .default; content.categoryIdentifier = "CHECKIN"
        content.interruptionLevel = .active
        return content
    }

    private struct Configuration: Codable {
        let settings: Settings
        let timeZone: String
        init(settings: Settings, timeZone: String) {
            // Display/inference changes and revision bumps do not move alerts.
            var value = Settings()
            value.notificationsEnabled = settings.notificationsEnabled
            value.notificationsAllDay = settings.notificationsAllDay
            value.startMinute = settings.startMinute; value.endMinute = settings.endMinute
            value.notificationTiming = settings.notificationTiming
            value.notificationDelivery = settings.notificationDelivery
            value.regularNotificationInterval = settings.regularNotificationInterval
            value.randomizedNotificationInterval = settings.randomizedNotificationInterval
            self.settings = value; self.timeZone = timeZone
        }
    }

    #if os(iOS)
    func registerBackgroundRefresh() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.backgroundIdentifier, using: nil) { task in
            guard let refresh = task as? BGAppRefreshTask else { task.setTaskCompleted(success: false); return }
            let operation = Task { @MainActor in
                do {
                    try await self.apply(LedgerStore.shared.ledger.settings, force: true)
                    refresh.setTaskCompleted(success: !Task.isCancelled)
                } catch { refresh.setTaskCompleted(success: false) }
            }
            refresh.expirationHandler = { operation.cancel() }
        }
    }

    #endif

    private func scheduleBackgroundRefresh() {
        #if os(iOS)
        let request = BGAppRefreshTaskRequest(identifier: Self.backgroundIdentifier)
        request.earliestBeginDate = Date().addingTimeInterval(30 * 60)
        try? BGTaskScheduler.shared.submit(request)
        #else
        WKApplication.shared().scheduleBackgroundRefresh(withPreferredDate: Date().addingTimeInterval(30 * 60), userInfo: nil) { _ in }
        #endif
    }

    private func cancelBackgroundRefresh() {
        #if os(iOS)
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.backgroundIdentifier)
        #endif
        // A pending Watch refresh may still run once; it sees delivery disabled
        // and completes without scheduling another refresh or any alerts.
    }

    func applyTimer(_ ledger: Ledger, writer: String) async {
        let previous = timerTask
        let task = Task { @MainActor in
            _ = await previous?.value
            await self.applyTimerSerially(ledger, writer: writer)
        }
        timerTask = task; await task.value
    }
    private func applyTimerSerially(_ ledger: Ledger, writer: String) async {
        configureActions()
        #if os(iOS)
        // A delayed snapshot must not cancel a newer system alarm. Confirm the
        // authoritative state again after the asynchronous AlarmKit operation.
        guard ledger.timerControl == LedgerStore.shared.ledger.timerControl,
              ledger.currentTimer == LedgerStore.shared.ledger.currentTimer,
              ledger.settings.timerSystemAlarms == LedgerStore.shared.ledger.settings.timerSystemAlarms,
              ledger.settings.timerSystemAlarmSilent == LedgerStore.shared.ledger.settings.timerSystemAlarmSilent else { return }
        let systemManaged = await PhoneTimerAlarm.shared.refresh(ledger, writer: writer)
        guard ledger.timerControl == LedgerStore.shared.ledger.timerControl,
              ledger.currentTimer == LedgerStore.shared.ledger.currentTimer,
              ledger.settings.timerSystemAlarms == LedgerStore.shared.ledger.settings.timerSystemAlarms,
              ledger.settings.timerSystemAlarmSilent == LedgerStore.shared.ledger.settings.timerSystemAlarmSilent else { return }
        #endif
        let pending = await center.pendingNotificationRequests().filter { $0.identifier.hasPrefix("task-timer-") }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-quiet-timer-alerts") {
            // Fake expired timers are for UI/control tests. Their simulator-only
            // fallback banner must not cover the controls being exercised.
            center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier))
            let delivered = await center.deliveredNotifications().filter { $0.request.identifier.hasPrefix("task-timer-") }
            center.removeDeliveredNotifications(withIdentifiers: delivered.map { $0.request.identifier })
            return
        }
        #endif
        let control = ledger.timerControl
        // A remote Watch restart retains repeating Watch alerts and also gets
        // one phone backup in case the Watch cannot rearm until opened.
        let localAlert = control?.schedulesNotification(writer: writer, onWatchDevice: LedgerStore.isWatch) == true
        let wanted = ledger.currentTimer != nil && localAlert && control?.dueAt != nil ? control?.token : nil
        center.removePendingNotificationRequests(withIdentifiers: pending.filter { $0.identifier != wanted }.map(\.identifier))
        let delivered = await center.deliveredNotifications().filter { $0.request.identifier.hasPrefix("task-timer-") && $0.request.identifier != wanted }
        center.removeDeliveredNotifications(withIdentifiers: delivered.map { $0.request.identifier })
        guard let current = ledger.currentTimer, let control, let due = control.dueAt, localAlert else {
            timerStatus = ledger.currentTimer == nil ? "" : control?.pausedRemaining != nil ? "Paused" : "Timer alerts on \(control?.onWatch == true ? "Apple Watch" : "iPhone")"
            return
        }
        #if os(iOS)
        if systemManaged || PhoneTimerAlarm.shared.isSilenced(control.token) {
            center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier))
            timerStatus = PhoneTimerAlarm.shared.status.isEmpty ? "Alarm silenced · timer awaits Done or Restart" : PhoneTimerAlarm.shared.status
            return
        }
        #endif
        #if os(watchOS)
        if WatchTimerAlarm.shared.isSilenced(for: control.token) {
            center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier))
            timerStatus = WatchTimerAlarm.shared.status; return
        }
        if WatchTimerAlarm.shared.isArmed(for: control.token) {
            center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier))
            timerStatus = WatchTimerAlarm.shared.status; return
        }
        #endif
        let permission = await center.notificationSettings().authorizationStatus
        guard permission == .authorized || permission == .provisional else {
            timerStatus = "Allow notifications for timer alerts."
            #if os(iOS)
            PhoneTimerAlarm.shared.noteNotificationFallback("allow notifications for a backup", token: control.token)
            #endif
            return
        }
        guard !pending.contains(where: { $0.identifier == control.token && $0.content.title == "\(current.title) finished" }) else {
            timerStatus = "Timer alert scheduled"
            #if os(iOS)
            PhoneTimerAlarm.shared.noteNotificationFallback("notification backup scheduled", token: control.token)
            #endif
            return
        }
        let key = "timers.last-notification"
        guard due > Date() || UserDefaults.standard.string(forKey: key) != control.token else { return }
        let content = UNMutableNotificationContent()
        content.title = "\(current.title) finished"
        content.body = control.isRemoteWatchRestart
            ? "Open Dash on Watch to rearm repeating haptics. Done & Next completes the task; Restart repeats its duration."
            : "Done & Next starts the next task. Restart repeats this timer."
        content.sound = .default; content.categoryIdentifier = "TASK_TIMER"
        content.threadIdentifier = "task-timer"; content.interruptionLevel = .timeSensitive
        do {
            try await center.add(UNNotificationRequest(identifier: control.token, content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, due.timeIntervalSinceNow), repeats: false)))
            UserDefaults.standard.set(control.token, forKey: key)
            timerStatus = "Timer alert scheduled"
            #if os(iOS)
            PhoneTimerAlarm.shared.noteNotificationFallback("notification backup scheduled", token: control.token)
            #endif
        } catch {
            timerStatus = "Timer alert could not be scheduled. Open the timer and try again."
            #if os(iOS)
            PhoneTimerAlarm.shared.noteNotificationFallback("notification backup could not be scheduled", token: control.token)
            #endif
        }
    }

    func sendTest() async throws {
        guard try await permission() else { throw NotificationError.denied }
        let content = UNMutableNotificationContent()
        content.title = "Dash test"
        content.body = promptBody
        content.sound = .default
        content.categoryIdentifier = "CHECKIN"
        try await center.add(UNNotificationRequest(identifier: "notification-test", content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: 15, repeats: false)))
        await refreshStatus()
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
        if notification.request.content.categoryIdentifier == "CHECKIN" {
            Task { @MainActor in try? await self.apply(LedgerStore.shared.ledger.settings) }
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        if response.notification.request.content.categoryIdentifier == "TASK_TIMER" {
            guard response.actionIdentifier != UNNotificationDismissActionIdentifier else { completionHandler(); return }
            let action = response.actionIdentifier, token = response.notification.request.identifier
            Task { @MainActor in
                let store = LedgerStore.shared; store.start()
                do {
                    if action == "TIMER_DONE" { try store.changeTimer("done", expectedToken: token) }
                    if action == "TIMER_RESTART" { try store.changeTimer("restart", expectedToken: token) }
                    store.openTimers()
                    await self.applyTimer(store.ledger, writer: store.writer)
                } catch { store.report(error) }
                completionHandler()
            }
            return
        }
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
                    // Scheduling errors must not turn an already saved log into
                    // an unsaved draft or encourage duplicate responses.
                    try? await self.apply(LedgerStore.shared.ledger.settings)
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
