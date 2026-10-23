import SwiftUI
import Combine
import LedgerCore

private struct SelectedGroup: Identifiable {
    var id: String
    var name: String
    var start: Date?
    var end: Date?
    var directOnly = false
}

struct DayView: View {
    var body: some View { AllocationHistoryView() }
}

struct AllocationHistoryView: View {
    @EnvironmentObject var store: LedgerStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var now = Date()
    @State private var selectedGroup: SelectedGroup?
    @State private var managingGroups = false
    @State private var reviewing: LogReviewRequest?
    @State private var range: HistoryRange = .today
    @State private var start = Calendar.current.date(byAdding: .day, value: -6, to: Date()) ?? Date()
    @State private var end = Date()
    @AppStorage("dashboard.hide-zero-time") private var hideZeroTime = true

    var body: some View {
        content(now: now)
            .onAppear { now = Date() }
            .onReceive(store.$ledger.dropFirst()) { _ in now = Date() }
            .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { now = $0 }
            .onChange(of: scenePhase) { _, phase in if phase == .active { now = Date() } }
            .navigationTitle(range == .today ? "Today" : "Your time").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    NavigationLink(value: LedgerScreen.calendar) {
                        Label("Calendar", systemImage: "calendar")
                    }.accessibilityIdentifier("dashboard.calendar")
                    Button("Categories") { managingGroups = true }.accessibilityIdentifier("dashboard.groups")
                    Menu {
                        Toggle("Hide zero-time categories", isOn: $hideZeroTime)
                            .accessibilityIdentifier("dashboard.hide-zero-time")
                    } label: {
                        Label("Filter categories", systemImage: hideZeroTime ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    }.accessibilityIdentifier("dashboard.filter")
                        .accessibilityValue(hideZeroTime ? "Zero-time categories hidden" : "All categories shown")
                }
            }
            .sheet(isPresented: $managingGroups, onDismiss: { now = Date() }) { GroupManagerView() }
            .sheet(item: $selectedGroup, onDismiss: { now = Date() }) { group in
                GroupEntriesView(day: group.start ?? Date(), groupID: group.id, initialName: group.name, rangeStart: group.start, rangeEnd: group.end, directOnly: group.directOnly)
            }
            .sheet(item: $reviewing, onDismiss: { now = Date() }) { request in LogReviewView(entryIDs: request.entryIDs) }

    }

    private func content(now: Date) -> some View {
        let report = store.ledger.history(range: range, start: start, end: end, now: now)
        let ungrouped = report.samples.filter {
            $0.end >= report.start && $0.end <= report.end &&
            (store.ledger.confirmedCategoryIDs(for: $0).isEmpty || store.ledger.allocationCategoryIDs(for: $0).contains("uncategorized"))
        }.count
        return VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Picker("Period", selection: $range) {
                        ForEach(HistoryRange.allCases) { Text($0.name).tag($0) }
                    }.pickerStyle(.menu).labelsHidden().accessibilityIdentifier("report.range")
                    Spacer(minLength: 8)
                    Text("\(store.duration(report.trackedMinutes)) tracked · \(report.samples.count) logs")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if range == .custom {
                    DatePicker("From", selection: $start, in: ...now, displayedComponents: [.date]).accessibilityIdentifier("report.from")
                    DatePicker("Through", selection: $end, in: ...now, displayedComponents: [.date]).accessibilityIdentifier("report.through")
                }
                if ungrouped > 0 {
                    Button {
                        reviewing = LogReviewRequest(entryIDs: report.samples.filter {
                            store.ledger.confirmedCategoryIDs(for: $0).isEmpty || store.ledger.allocationCategoryIDs(for: $0).contains("uncategorized")
                        }.sorted { $0.end == $1.end ? $0.id < $1.id : $0.end > $1.end }.map(\.id))
                    } label: {
                        Label("Review logs (\(ungrouped))", systemImage: "tray")
                            .font(.subheadline).frame(minHeight: 32)
                    }.accessibilityIdentifier("dashboard.review.uncategorized")
                }
            }.padding(.horizontal, 20).padding(.vertical, 8)
            Divider()
            HistoryPanel(report: report, hideZeroTime: hideZeroTime, selectDirect: { row in
                selectedGroup = SelectedGroup(id: row.id, name: row.name, start: report.start, end: report.end, directOnly: true)
            }) { row in
                selectedGroup = SelectedGroup(id: row.id, name: row.name, start: report.start, end: report.end)
            }.padding(.top, 12)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
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
