import BackgroundTasks
import Combine
import CryptoKit
import EventKit
import UIKit
import LedgerCore

struct ReminderListOption: Identifiable, Hashable {
    let id: String
    let title: String
    let account: String
    var label: String { account.isEmpty ? title : "\(title) · \(account)" }
}

private struct PendingReminder: Sendable {
    let snapshot: ReminderSnapshot
    let localID: String
    let modifiedAt: Date?
}

/// The selected list is a transfer inbox. Delete only after an atomic ledger
/// save, and keep any source that changed during the handoff.
@MainActor
final class ReminderInbox: ObservableObject {
    static let shared = ReminderInbox()
    static let backgroundIdentifier = "com.trimngo.TimeLedger.reminders-refresh"
    @Published private(set) var enabled: Bool
    @Published private(set) var selectedListID: String
    @Published private(set) var lists: [ReminderListOption] = []
    @Published private(set) var authorized = false
    @Published private(set) var accessDenied = false
    @Published private(set) var isRefreshing = false
    @Published private(set) var status = "Connect a Reminders list to capture ideas with Siri."
    @Published private(set) var lastImportAt: Date?
    @Published private(set) var pendingCount: Int?
    private let eventStore = EKEventStore()
    private let defaults = UserDefaults.standard
    private let deviceID: String
    private var connection = UUID()
    private var observer: NSObjectProtocol?
    private var changeTask: Task<Void, Never>?
    private var anotherRefresh = false
    private var fetchToken: Any?
    private var fetchID: UUID?
    private var continuation: CheckedContinuation<[PendingReminder], Error>?
    private var timeout: Task<Void, Never>?

    private init() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-empty-ledger") {
            UserDefaults.standard.set(false, forKey: "reminders.inbox.enabled")
            UserDefaults.standard.removeObject(forKey: "reminders.inbox.list")
            UserDefaults.standard.removeObject(forKey: "reminders.inbox.last-import")
        }
        #endif
        enabled = defaults.bool(forKey: "reminders.inbox.enabled")
        selectedListID = defaults.string(forKey: "reminders.inbox.list") ?? ""
        lastImportAt = defaults.object(forKey: "reminders.inbox.last-import") as? Date
        deviceID = defaults.string(forKey: "reminders.inbox.device") ?? UUID().uuidString
        defaults.set(deviceID, forKey: "reminders.inbox.device")
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.requestRefresh() }
        }
    }

    var selectedListName: String { lists.first { $0.id == selectedListID }?.title ?? "Selected list" }
    var backgroundStatus: String {
        UIApplication.shared.backgroundRefreshStatus == .available
            ? "Background import is best effort. iOS decides when it runs; opening Dash imports right away."
            : "Background App Refresh is unavailable. Opening Dash still imports your ideas."
    }

    func reloadLists() {
        let permission = EKEventStore.authorizationStatus(for: .reminder)
        authorized = permission == .fullAccess
        accessDenied = permission == .denied || permission == .restricted
        lists = authorized ? eventStore.calendars(for: .reminder).map {
            ReminderListOption(id: $0.calendarIdentifier, title: $0.title, account: $0.source?.title ?? "")
        }.sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending } : []
        if enabled, !authorized { status = "Allow Reminders access to resume importing." }
        else if enabled, !lists.contains(where: { $0.id == selectedListID }) {
            status = "The connected list is unavailable. Choose a list to reconnect."
        }
    }

    func requestAccess() async {
        do { _ = try await eventStore.requestFullAccessToReminders(); reloadLists() }
        catch { status = "Could not access Reminders. Try again in Settings."; reloadLists() }
    }

    func connect(_ id: String) async {
        reloadLists()
        guard authorized, lists.contains(where: { $0.id == id }) else { status = "Choose an available Reminders list."; return }
        connection = UUID(); cancelFetch()
        selectedListID = id; enabled = true
        pendingCount = nil
        defaults.set(id, forKey: "reminders.inbox.list")
        defaults.set(true, forKey: "reminders.inbox.enabled")
        _ = await refresh()
        scheduleBackgroundRefresh()
    }

    func createAndConnect() async {
        reloadLists()
        guard authorized else { return }
        do {
            let source = eventStore.defaultCalendarForNewReminders()?.source
                ?? eventStore.sources.first { $0.sourceType == .local }
            guard let source else { throw ImportError.noSource }
            var title = "Dash Inbox"
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ui-reminders-fixture") { title = "Dash Inbox UI Fixture \(UUID().uuidString.prefix(8))" }
            #endif
            let list: EKCalendar
            if let existing = eventStore.calendars(for: .reminder).first(where: { $0.title == title && $0.source?.sourceIdentifier == source.sourceIdentifier }) {
                list = existing
            } else {
                list = EKCalendar(for: .reminder, eventStore: eventStore)
                list.title = title; list.source = source
                try eventStore.saveCalendar(list, commit: true)
            }
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ui-reminders-fixture") { try seedFixture(in: list, source: source) }
            #endif
            await connect(list.calendarIdentifier)
        } catch { status = error.localizedDescription }
    }

    func disconnect() {
        connection = UUID(); enabled = false
        pendingCount = nil
        defaults.set(false, forKey: "reminders.inbox.enabled")
        changeTask?.cancel(); cancelFetch()
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.backgroundIdentifier)
        status = "Disconnected. Your imported ideas are kept in Dash."
    }

    func requestRefresh() {
        guard enabled, UIApplication.shared.applicationState == .active else { return }
        if isRefreshing { anotherRefresh = true; return }
        changeTask?.cancel()
        changeTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 350_000_000) } catch { return }
            _ = await self?.refresh()
        }
    }

    @discardableResult
    func refresh() async -> Bool {
        guard enabled else { return true }
        reloadLists()
        guard authorized else { return false }
        guard !isRefreshing else { anotherRefresh = true; return false }
        guard let list = eventStore.calendar(withIdentifier: selectedListID), list.allowedEntityTypes.contains(.reminder) else {
            status = "The connected list is unavailable. Choose a list to reconnect."; return false
        }
        let current = connection
        isRefreshing = true; status = "Checking Reminders…"
        defer {
            isRefreshing = false
            if anotherRefresh { anotherRefresh = false; requestRefresh() }
        }
        do {
            try Task.checkCancellation()
            let pending = try await fetchPending(in: list)
            pendingCount = pending.count
            try Task.checkCancellation()
            guard enabled, connection == current else { return false }
            let count = try LedgerStore.shared.importReminders(pending.map(\.snapshot))
            // importReminders returns only after an atomic disk write. An import
            // failure exits through catch before any source can be removed.
            let transfer = await removeSaved(pending, listID: list.calendarIdentifier, connection: current)
            try Task.checkCancellation()
            guard enabled, connection == current else { return false }
            if let remaining = try? await fetchPending(in: list) { pendingCount = remaining.count }
            guard enabled, connection == current else { return false }
            let checkedAt = Date(); lastImportAt = checkedAt
            defaults.set(checkedAt, forKey: "reminders.inbox.last-import")
            if transfer.kept > 0 {
                status = "Saved ideas are kept in Dash. Some originals changed or could not be removed, so they remain in Reminders."
            } else if transfer.removed > 0 {
                status = "Moved \(transfer.removed) \(transfer.removed == 1 ? "reminder" : "reminders") to Dash."
            } else {
                status = count == 0 ? "Up to date. No new ideas." : "Imported \(count) new \(count == 1 ? "idea" : "ideas")."
            }
            return true
        } catch {
            if connection == current, enabled {
                status = error is CancellationError ? "Import paused. Dash will retry when opened." : "Could not import Reminders. Your saved ideas are kept. Try Import now."
            }
            return false
        }
    }

    private func removeSaved(_ pending: [PendingReminder], listID: String, connection current: UUID) async -> (removed: Int, kept: Int) {
        var removed = 0, kept = 0
        for candidate in pending {
            await Task.yield() // Keep a large capture-list transfer responsive and cancellable.
            guard enabled, connection == current, selectedListID == listID, !Task.isCancelled else { break }
            guard let reminder = eventStore.calendarItem(withIdentifier: candidate.localID) as? EKReminder else { continue }
            guard reminder.refresh() else { kept += 1; continue }
            // Never remove a reminder moved to another list or completed by its owner.
            guard reminder.calendar.calendarIdentifier == listID, !reminder.isCompleted else { continue }
            let latest = Self.candidate(reminder, deviceID: deviceID)
            guard latest.snapshot == candidate.snapshot, latest.modifiedAt == candidate.modifiedAt,
                  LedgerStore.shared.ledger.canRemoveImportedReminder(latest.snapshot) else { kept += 1; continue }
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ui-reminders-delete-failure") { kept += 1; continue }
            #endif
            do { try eventStore.remove(reminder, commit: true); removed += 1 }
            catch { kept += 1 } // Keep the saved copy and retry cleanup, without importing twice.
        }
        return (removed, kept)
    }

    nonisolated private static func candidate(_ reminder: EKReminder, deviceID: String) -> PendingReminder {
        var identifiers: [String] = []
        if let external = reminder.calendarItemExternalIdentifier, !external.isEmpty {
            identifiers.append(identity("external:" + external))
        }
        identifiers.append(identity("local:" + deviceID + ":" + reminder.calendarItemIdentifier))
        let snapshot = ReminderSnapshot(identifiers: identifiers, title: reminder.title ?? "", notes: reminder.notes,
                                        createdAt: reminder.creationDate, isCompleted: reminder.isCompleted)
        return PendingReminder(snapshot: snapshot, localID: reminder.calendarItemIdentifier, modifiedAt: reminder.lastModifiedDate)
    }

    private func fetchPending(in list: EKCalendar) async throws -> [PendingReminder] {
        let id = UUID(), calendarID = list.calendarIdentifier, deviceID = deviceID
        let predicate = eventStore.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: [list])
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { pending in
                continuation = pending; fetchID = id
                fetchToken = eventStore.fetchReminders(matching: predicate) { [weak self] reminders in
                    let snapshots = reminders?.filter { $0.calendar.calendarIdentifier == calendarID }.map { Self.candidate($0, deviceID: deviceID) }
                    Task { @MainActor in
                        if let snapshots { self?.finishFetch(id, result: .success(snapshots)) }
                        else { self?.finishFetch(id, result: .failure(ImportError.fetchFailed)) }
                    }
                }
                timeout = Task { [weak self] in
                    do { try await Task.sleep(nanoseconds: 20_000_000_000) } catch { return }
                    guard let self, self.fetchID == id else { return }
                    self.cancelFetch()
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in if self?.fetchID == id { self?.cancelFetch() } }
        }
    }

    nonisolated private static func identity(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func finishFetch(_ id: UUID, result: Result<[PendingReminder], Error>) {
        guard fetchID == id, let pending = continuation else { return }
        continuation = nil; fetchID = nil; fetchToken = nil
        timeout?.cancel(); timeout = nil
        pending.resume(with: result)
    }

    private func cancelFetch() {
        guard let id = fetchID else { return }
        if let fetchToken { eventStore.cancelFetchRequest(fetchToken) }
        finishFetch(id, result: .failure(CancellationError()))
    }

    func registerBackgroundRefresh() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.backgroundIdentifier, using: nil) { task in
            guard let refresh = task as? BGAppRefreshTask else { task.setTaskCompleted(success: false); return }
            let operation = Task { @MainActor in
                self.scheduleBackgroundRefresh()
                let success = await self.refresh()
                refresh.setTaskCompleted(success: success)
            }
            refresh.expirationHandler = { operation.cancel() }
        }
    }

    func scheduleBackgroundRefresh() {
        guard enabled, EKEventStore.authorizationStatus(for: .reminder) == .fullAccess else {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.backgroundIdentifier)
            return
        }
        let request = BGAppRefreshTaskRequest(identifier: Self.backgroundIdentifier)
        request.earliestBeginDate = Date().addingTimeInterval(15 * 60)
        // Scheduling is opportunistic. A disabled Background App Refresh must
        // never prevent the foreground import or show a blocking error.
        try? BGTaskScheduler.shared.submit(request)
    }

    #if DEBUG
    private func seedFixture(in list: EKCalendar, source: EKSource) throws {
        // Only explicit UI-test launches create these isolated simulator items.
        // Fixtures never run in a TestFlight/Release build.
        let fixtureKey = "reminders.ui-fixture-seeded.\(list.calendarIdentifier)"
        guard !defaults.bool(forKey: fixtureKey) else { return }
        let pending = EKReminder(eventStore: eventStore); pending.calendar = list; pending.title = "Reminders bicycle idea UI fixture"
        try eventStore.save(pending, commit: true)
        let done = EKReminder(eventStore: eventStore); done.calendar = list; done.title = "Completed source UI fixture"; done.isCompleted = true
        try eventStore.save(done, commit: true)
        let other = EKCalendar(for: .reminder, eventStore: eventStore); other.title = "Other UI Fixture"; other.source = source
        try eventStore.saveCalendar(other, commit: true)
        let unrelated = EKReminder(eventStore: eventStore); unrelated.calendar = other; unrelated.title = "Other list must stay private UI fixture"
        try eventStore.save(unrelated, commit: true)
        defaults.set(true, forKey: fixtureKey)
    }
    #endif

    private enum ImportError: LocalizedError {
        case noSource, fetchFailed
        var errorDescription: String? {
            switch self {
            case .noSource: return "Create a list in Apple Reminders first, then choose it here. Use an iCloud list to capture from your Watch."
            case .fetchFailed: return "Reminders is not available right now. Try again."
            }
        }
    }
}
