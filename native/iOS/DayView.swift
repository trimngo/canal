import SwiftUI
import Combine
import LedgerCore

struct DayView: View {
    var body: some View { AllocationHistoryView() }
}

struct AllocationHistoryView: View {
    @EnvironmentObject var store: LedgerStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var now = Date()
    @State private var selectedGroup: CategoryDetailRequest?
    @State private var managingGroups = false
    @State private var reviewing: LogReviewRequest?
    @State private var range: HistoryRange = .today
    @State private var start = Calendar.current.date(byAdding: .day, value: -6, to: Date()) ?? Date()
    @State private var end = Date()
    @State private var selectedDay: Date?
    @AppStorage("dashboard.hide-zero-time") private var hideZeroTime = true

    var body: some View {
        let report = store.ledger.history(range: range, start: start, end: end, now: now, anchor: selectedDay)
        let unreviewed = report.samples.filter { store.ledger.needsCategoryReview($0) || store.ledger.effectiveCategoryIDs(for: $0).isEmpty || store.ledger.allocationCategoryIDs(for: $0).contains("uncategorized") }
        let pending = (store.ledger.calendarEvents ?? []).filter { $0.decision == .pending }.map(\.id)
        let reviewCount = unreviewed.count + pending.count
        return content(report: report)
            .onAppear { now = Date() }
            .onReceive(store.$ledger.dropFirst()) { _ in now = Date() }
            .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { now = $0; Task { await CalendarImport.shared.refresh() } }
            .onChange(of: scenePhase) { _, phase in if phase == .active { now = Date() } }
            .navigationTitle(range == .today ? periodLabel : "Your time").navigationBarTitleDisplayMode(.inline)
            .onChange(of: range) { _, _ in selectedDay = nil }
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    NavigationLink(value: LedgerScreen.calendar) {
                        Label("Calendar", systemImage: "calendar")
                    }.accessibilityIdentifier("dashboard.calendar")
                    if reviewCount > 0 {
                        Button {
                            reviewing = LogReviewRequest(entryIDs: unreviewed.map(\.id), calendarIDs: pending)
                        } label: { Label("Review logs (\(reviewCount))", systemImage: "tray") }
                            .accessibilityIdentifier("dashboard.review.uncategorized")
                    }
                    Menu {
                        Toggle("Hide zero-time categories", isOn: $hideZeroTime)
                            .accessibilityIdentifier("dashboard.hide-zero-time")
                        Button("Manage categories") { managingGroups = true }
                            .accessibilityIdentifier("dashboard.manage-categories")
                    } label: {
                        Label("Filter categories", systemImage: hideZeroTime ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    }.accessibilityIdentifier("dashboard.filter")
                        .accessibilityValue(hideZeroTime ? "Zero-time categories hidden" : "All categories shown")
                }
            }
            .sheet(isPresented: $managingGroups, onDismiss: { now = Date() }) { GroupManagerView() }
            .sheet(item: $selectedGroup, onDismiss: { now = Date() }) { group in
                CategoryDetailView(request: group)
            }
            .sheet(item: $reviewing, onDismiss: { now = Date() }) { request in LogReviewView(entryIDs: request.entryIDs, calendarIDs: request.calendarIDs) }

    }

    private func content(report: HistoryReport) -> some View {
        ScrollView {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 4) {
                    if range == .today || range == .week {
                        Button { shiftPeriod(-1) } label: { Image(systemName: "chevron.left").frame(width: 32, height: 36) }
                            .buttonStyle(.plain).accessibilityLabel(range == .today ? "Previous day" : "Previous seven days")
                            .accessibilityIdentifier("report.previous")
                    }
                    Menu {
                        ForEach(HistoryRange.allCases) { option in
                            Button(option.name) { range = option; selectedDay = nil }
                        }
                    } label: {
                        HStack(spacing: 4) { Text(periodLabel); Image(systemName: "chevron.down").font(.caption2) }
                            .font(.subheadline).lineLimit(1).minimumScaleFactor(0.8)
                    }.accessibilityIdentifier("report.range").accessibilityValue(periodLabel)
                    if range == .today || range == .week {
                        Button { shiftPeriod(1) } label: { Image(systemName: "chevron.right").frame(width: 32, height: 36) }
                            .buttonStyle(.plain).disabled(selectedDay == nil)
                            .accessibilityLabel(range == .today ? "Next day" : "Next seven days")
                            .accessibilityIdentifier("report.next")
                    }
                    Spacer(minLength: 4)
                    Text("\(store.duration(report.trackedMinutes)) tracked · \(report.samples.count) logs")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        .accessibilityIdentifier("report.tracked")
                }
                if range == .custom {
                    DatePicker("From", selection: $start, in: ...now, displayedComponents: [.date]).accessibilityIdentifier("report.from")
                    DatePicker("Through", selection: $end, in: ...now, displayedComponents: [.date]).accessibilityIdentifier("report.through")
                }
                DaylightDashboardView()
            }.padding(.horizontal, 20).padding(.vertical, 8)
            Divider()
            HistoryPanel(report: report, hideZeroTime: hideZeroTime, selectDirect: { row in
                selectedGroup = CategoryDetailRequest(id: row.id, name: row.name, start: report.start, end: report.end, directOnly: true, allTime: false)
            }) { row in
                selectedGroup = CategoryDetailRequest(id: row.id, name: row.name, start: report.start, end: report.end, allTime: false)
            }.padding(.top, 12)
            Divider().padding(.vertical, 20)
            TodayUrgentTasksView(now: now).padding(.horizontal, 20).padding(.bottom, 24)
        }.frame(maxWidth: .infinity)
        }.accessibilityIdentifier("today.content")
    }
    private var periodLabel: String {
        let cal = store.ledger.reportingCalendar()
        let today = cal.startOfDay(for: now)
        guard let selectedDay, range == .today || range == .week else { return range.name }
        let day = cal.startOfDay(for: selectedDay)
        if range == .today {
            if day == today { return "Today" }
            if day == cal.date(byAdding: .day, value: -1, to: today) { return "Yesterday" }
        }
        let format = DateFormatter(); format.calendar = cal; format.timeZone = cal.timeZone
        format.setLocalizedDateFormatFromTemplate("MMM d")
        if range == .today { return format.string(from: day) }
        let first = cal.date(byAdding: .day, value: -6, to: day) ?? day
        return "\(format.string(from: first))–\(format.string(from: day))"
    }
    private func shiftPeriod(_ direction: Int) {
        let cal = store.ledger.reportingCalendar(), today = store.ledger.reportingDay(containing: now)
        guard let shifted = cal.date(byAdding: .day, value: direction * (range == .week ? 7 : 1), to: selectedDay ?? today) else { return }
        selectedDay = shifted >= today ? nil : shifted
    }
}

struct CalendarHistoryView: View {
    @EnvironmentObject var store: LedgerStore
    @State private var day = Date()
    var body: some View {
        TimelineView(.periodic(from: Date(), by: 60)) { _ in
            let now = Date()
            VStack(spacing: 12) {
                DatePicker("Date", selection: $day, in: ...now, displayedComponents: [.date]).environment(\.timeZone, store.ledger.reportingCalendar().timeZone).padding(.horizontal)
                DayCalendarView(day: day, now: now)
            }
        }.navigationTitle("Calendar").navigationBarTitleDisplayMode(.inline)
            .onAppear { day = store.ledger.reportingDay(containing: Date()) }
    }
}
