import SwiftUI
import Combine
import LedgerCore

private struct SelectedGroup: Identifiable {
    var id: String
    var name: String
    var start: Date?
    var end: Date?
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
    @State private var range: HistoryRange = .today
    @State private var start = Calendar.current.date(byAdding: .day, value: -6, to: Date()) ?? Date()
    @State private var end = Date()

    var body: some View {
        content(now: now)
            .onAppear { now = Date() }
            .onReceive(store.$ledger.dropFirst()) { _ in now = Date() }
            .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { now = $0 }
            .onChange(of: scenePhase) { _, phase in if phase == .active { now = Date() } }
            .navigationTitle(range == .today ? "Today" : "Your time").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("Categories") { managingGroups = true }.accessibilityIdentifier("dashboard.groups")
                }
            }
            .sheet(isPresented: $managingGroups, onDismiss: { now = Date() }) { GroupManagerView() }
            .sheet(item: $selectedGroup, onDismiss: { now = Date() }) { group in
                GroupEntriesView(day: group.start ?? Date(), groupID: group.id, initialName: group.name, rangeStart: group.start, rangeEnd: group.end)
            }

    }

    private func content(now: Date) -> some View {
        let report = store.ledger.history(range: range, start: start, end: end, now: now)
        let ungrouped = report.samples.filter {
            $0.end >= report.start && $0.end <= report.end &&
            (store.ledger.confirmedCategoryIDs(for: $0).isEmpty || store.ledger.allocationCategoryIDs(for: $0).contains("uncategorized"))
        }.count
        return List {
            Section {
                Picker("Period", selection: $range) {
                    ForEach(HistoryRange.allCases) { Text($0.name).tag($0) }
                }.pickerStyle(.menu).accessibilityIdentifier("report.range")
                if range == .custom {
                    DatePicker("From", selection: $start, in: ...now, displayedComponents: [.date]).accessibilityIdentifier("report.from")
                    DatePicker("Through", selection: $end, in: ...now, displayedComponents: [.date]).accessibilityIdentifier("report.through")
                }
                HistoryPanel(report: report, expandsBreakdown: true) { row in
                    selectedGroup = SelectedGroup(id: row.id, name: row.name, start: report.start, end: report.end)
                }.listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            } header: {
                Text("Where your time went").font(.headline).textCase(nil).accessibilityIdentifier("dashboard.breakdown-title")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(store.duration(report.trackedMinutes)) tracked · \(report.samples.count) logs")
                    Text("Percentages start at each day’s first log and end at now today, or midnight for completed days. Days without logs are excluded.")
                    Text("Swipe the chart for breakdown, pie, and trend.")
                }
            }
            if ungrouped > 0 || store.canUndoGrouping {
                Section {
                    if ungrouped > 0 {
                        Button { selectedGroup = SelectedGroup(id: "uncategorized", name: "Uncategorized", start: report.start, end: report.end) } label: {
                            Label("\(ungrouped) logs to group", systemImage: "tray")
                        }.accessibilityIdentifier("dashboard.review.uncategorized")
                    }
                    if store.canUndoGrouping {
                        Button("Undo last categorization") { store.undoCategorization() }.accessibilityIdentifier("dashboard.undo")
                    }
                }
            }
            Section {
                NavigationLink("Calendar", value: LedgerScreen.calendar).accessibilityIdentifier("dashboard.calendar")
            }
        }.listStyle(.insetGrouped).listSectionSpacing(12).scrollDismissesKeyboard(.immediately)
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
