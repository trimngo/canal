import SwiftUI
import EventKit
import Combine
import CryptoKit
import BackgroundTasks
import LedgerCore

struct CalendarSourceOption: Identifiable {
    let id: String
    let name: String
    let account: String
}

/// Read-only access. Only an explicit confirmation adds a time period to logs.
@MainActor
final class CalendarImport: ObservableObject {
    static let shared = CalendarImport()
    static let backgroundIdentifier = "com.trimngo.TimeLedger.calendar-refresh"
    @Published private(set) var sources: [CalendarSourceOption] = []
    @Published private(set) var authorized = false
    @Published private(set) var selected: Set<String>
    @Published private(set) var status = "Choose calendars to preview today and review events after they end."
    @Published private(set) var refreshing = false
    @Published private(set) var plannedEvents: [CategorizedCalendarEvent] = []
    private var upcoming: [CalendarEventSnapshot] = []
    private var forecastTask: Task<Void, Never>?
    private var forecastGeneration = 0
    private let events = EKEventStore()
    private let defaults = UserDefaults.standard
    private var observer: NSObjectProtocol?
    private init() {
        selected = Set(UserDefaults.standard.stringArray(forKey: "calendar.sources") ?? [])
        #if DEBUG
        if CalendarForecastFixture.enabled {
            selected = Set(UserDefaults.standard.stringArray(forKey: CalendarForecastFixture.selectionKey) ?? [CalendarForecastFixture.sourceID])
        }
        #endif
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
    }
    func reload() {
        #if DEBUG
        if CalendarForecastFixture.enabled {
            authorized = true
            sources = [CalendarSourceOption(id: CalendarForecastFixture.sourceID, name: "Today plan", account: "Test calendar")]
            if selected.isEmpty { clearForecast() }
            return
        }
        #endif
        authorized = EKEventStore.authorizationStatus(for: .event) == .fullAccess
        sources = authorized ? events.calendars(for: .event).map {
            CalendarSourceOption(id: $0.calendarIdentifier, name: $0.title, account: $0.source?.title ?? "")
        }.sorted { ($0.name + $0.account).localizedStandardCompare($1.name + $1.account) == .orderedAscending } : []
        if !authorized, !selected.isEmpty { status = "Calendar access is unavailable. Allow full calendar access in iPhone Settings." }
        if !authorized || selected.isEmpty { clearForecast() }
    }
    func requestAccess() async {
        do { _ = try await events.requestFullAccessToEvents(); reload() }
        catch { status = "Could not access calendars. Try again in iPhone Settings." }
    }
    func setSelected(_ id: String, enabled: Bool) async {
        if enabled { selected.insert(id) } else { selected.remove(id) }
        #if DEBUG
        if CalendarForecastFixture.enabled {
            defaults.set(Array(selected).sorted(), forKey: CalendarForecastFixture.selectionKey)
            await refresh(); return
        }
        #endif
        defaults.set(Array(selected).sorted(), forKey: "calendar.sources")
        // Adding a source starts with today's events, never imports years of history.
        let today = Calendar.current.startOfDay(for: Date())
        let previous = defaults.object(forKey: "calendar.scan-start") as? Date
        defaults.set(min(previous ?? today, today), forKey: "calendar.scan-start")
        await refresh()
    }
    func refresh() async {
        guard !refreshing else { return }
        refreshing = true; defer { refreshing = false }
        reload()
        guard authorized, !selected.isEmpty else { return }
        #if DEBUG
        if CalendarForecastFixture.enabled {
            let snapshots = CalendarForecastFixture.snapshots.filter { selected.contains($0.calendarID) }
            do { try LedgerStore.shared.collectCalendarEvents(snapshots) }
            catch { clearForecast(); status = "Calendar review could not be saved."; return }
            upcoming = snapshots.filter { $0.end > CalendarForecastFixture.now }
            refreshForecastCategories()
            status = "Planned time is tentative. Ended events need confirmation."
            return
        }
        #endif
        let calendars = events.calendars(for: .event).filter { selected.contains($0.calendarIdentifier) }
        guard !calendars.isEmpty else { clearForecast(); status = "Selected calendars are unavailable. Choose another calendar."; return }
        let now = Date()
        let start = defaults.object(forKey: "calendar.scan-start") as? Date ?? Calendar.current.startOfDay(for: now)
        let dayEnd = LedgerStore.shared.ledger.dayBounds(on: now)?.end ?? now
        let predicate = events.predicateForEvents(withStart: min(start, now), end: dayEnd, calendars: calendars)
        let occurrences = events.events(matching: predicate).filter { $0.status != .canceled }
        func snapshot(_ event: EKEvent) -> CalendarEventSnapshot {
            // Occurrence date distinguishes repeating events even when titles match.
            let recurring = !(event.recurrenceRules ?? []).isEmpty || event.isDetached
            let key = CalendarEventSnapshot.identityKey(calendarID: event.calendar.calendarIdentifier,
                itemID: event.calendarItemIdentifier, externalID: event.calendarItemExternalIdentifier,
                occurrence: recurring ? (event.occurrenceDate ?? event.startDate) : nil)
            let id = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
            let title = event.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return CalendarEventSnapshot(id: id, calendarID: event.calendar.calendarIdentifier, calendarName: event.calendar.title,
                title: title.isEmpty ? "Calendar event" : String(title.prefix(500)), start: event.startDate, end: event.endDate)
        }
        let snapshots = occurrences.map(snapshot)
        upcoming = occurrences.filter { event in
            event.endDate > now && !event.isAllDay && event.availability != .free &&
                !(event.attendees ?? []).contains { $0.isCurrentUser && $0.participantStatus == .declined }
        }.map(snapshot)
        do {
            LedgerStore.shared.start()
            try LedgerStore.shared.collectCalendarEvents(snapshots)
            refreshForecastCategories()
            // Keep a lookback for late sync and recently edited events. Durable
            // receipts deduplicate repeated scans and never reopen decisions.
            defaults.set(now.addingTimeInterval(-86400), forKey: "calendar.scan-start")
            status = "Up to date. Planned time is tentative. Events count as recorded time only after you confirm them."
            scheduleBackgroundRefresh()
        } catch { clearForecast(); status = "Calendar review could not be saved. Opening Dash retries it." }
    }
    func refreshForecastCategories() {
        forecastGeneration += 1
        let generation = forecastGeneration, snapshots = upcoming
        forecastTask?.cancel()
        guard authorized, !selected.isEmpty, !snapshots.isEmpty else { plannedEvents = []; return }
        let previous = Dictionary(plannedEvents.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        plannedEvents = snapshots.map { snapshot in
            CategorizedCalendarEvent(snapshot: snapshot,
                categoryIDs: previous[snapshot.id]?.snapshot.title == snapshot.title ? previous[snapshot.id]?.categoryIDs ?? [] : [])
        }
        let ledger = LedgerStore.shared.ledger
        forecastTask = Task {
            let suggestions = await AutomaticCategories.shared.suggestions(for: snapshots.map(\.title), in: ledger)
            guard !Task.isCancelled, forecastGeneration == generation, authorized, !selected.isEmpty else { return }
            plannedEvents = snapshots.map { CategorizedCalendarEvent(snapshot: $0, categoryIDs: suggestions[$0.title]?.categoryIDs ?? []) }
        }
    }
    private func clearForecast() {
        forecastGeneration += 1; forecastTask?.cancel(); forecastTask = nil
        upcoming = []; plannedEvents = []
    }
    func registerBackgroundRefresh() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.backgroundIdentifier, using: nil) { task in
            guard let refresh = task as? BGAppRefreshTask else { task.setTaskCompleted(success: false); return }
            let operation = Task { @MainActor in await self.refresh(); refresh.setTaskCompleted(success: !Task.isCancelled) }
            refresh.expirationHandler = { operation.cancel() }
        }
    }
    func scheduleBackgroundRefresh() {
        guard !selected.isEmpty else { BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.backgroundIdentifier); return }
        let request = BGAppRefreshTaskRequest(identifier: Self.backgroundIdentifier)
        request.earliestBeginDate = Date().addingTimeInterval(30 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}

struct CalendarConnectionView: View {
    @StateObject private var connection = CalendarImport.shared
    @EnvironmentObject private var store: LedgerStore
    var body: some View {
        Form {
            if !connection.authorized {
                Section {
                    Button("Allow calendar access") { Task { await connection.requestAccess() } }
                        .accessibilityIdentifier("calendar.allow")
                } footer: { Text("Dash reads events from calendars you select. It does not change your calendars. Full access is required by Apple to read events.") }
            } else {
                Section("Calendars") {
                    ForEach(connection.sources) { source in
                        Toggle(isOn: Binding(get: { connection.selected.contains(source.id) }, set: { value in Task { await connection.setSelected(source.id, enabled: value) } })) {
                            VStack(alignment: .leading) { Text(source.name); Text(source.account).font(.caption).foregroundStyle(.secondary) }
                        }.accessibilityIdentifier("calendar.source.\(source.id)")
                    }
                }
            }
            Section {
                Text(connection.status).font(.footnote).foregroundStyle(.secondary)
                Button("Refresh calendars") { Task { await connection.refresh() } }.disabled(connection.refreshing)
                NavigationLink("Review calendar events") { CalendarEventReviewView() }
                    .accessibilityIdentifier("calendar.review")
            } footer: { Text("Today's remaining timed events preview planned categories in the dashboard. Plans are tentative and do not count toward goals or history. All-day, free and declined events are excluded from the preview. Opening Dash checks for updates; background refresh is best effort. Confirmed events count until their scheduled end or the first overlapping log. Original records are kept.") }
        }.navigationTitle("Calendars").task { connection.reload(); await connection.refresh() }
    }
}

struct CalendarEventReviewView: View {
    @EnvironmentObject private var store: LedgerStore
    @State private var review: LogReviewRequest?
    @State private var error: String?
    private var pending: [CalendarEventRecord] {
        store.ledger.calendarEventsToReview()
    }
    var body: some View {
        List {
            if pending.isEmpty { ContentUnavailableView("No events to confirm", systemImage: "calendar.badge.checkmark") }
            ForEach(pending) { record in
                Button { review = LogReviewRequest(entryIDs: [], calendarIDs: [record.id]) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(record.snapshot.title).foregroundStyle(.primary)
                        Text(record.snapshot.start.formatted(date: .abbreviated, time: .shortened) + " – " + store.ledger.calendarEventEnd(record.snapshot).formatted(date: .abbreviated, time: .shortened))
                            .font(.caption).foregroundStyle(.secondary)
                        Text(record.snapshot.calendarName).font(.caption).foregroundStyle(.secondary)
                    }
                }.accessibilityIdentifier("calendar.event.\(record.id)")
                    .swipeActions { Button("Skip", role: .destructive) { decide(record, confirm: false) } }
            }
            if let error { Text(error).foregroundStyle(.red) }
        }.navigationTitle("Confirm events").navigationBarTitleDisplayMode(.inline)
            .sheet(item: $review) { LogReviewView(entryIDs: $0.entryIDs, calendarIDs: $0.calendarIDs) }
            .task { await CalendarImport.shared.refresh() }
    }
    private func decide(_ record: CalendarEventRecord, confirm: Bool) {
        do { try store.decideCalendarEvent(record.id, confirm: confirm) } catch { self.error = error.localizedDescription }
    }
}
