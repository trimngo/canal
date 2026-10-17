import SwiftUI
import LedgerCore

private struct SelectedGroup: Identifiable {
    var id: String
    var name: String
    var start: Date?
    var end: Date?
}

struct DayView: View {
    var body: some View { AllocationHistoryView(isHome: true) }
}

struct AllocationHistoryView: View {
    @EnvironmentObject var store: LedgerStore
    var isHome = false
    @State private var selectedGroup: SelectedGroup?
    @State private var managingGroups = false
    @State private var range: HistoryRange = .today
    @State private var start = Calendar.current.date(byAdding: .day, value: -6, to: Date()) ?? Date()
    @State private var end = Date()
    private var ungrouped: Int {
        store.ledger.activeEntries.filter {
            $0.end <= Date() && (store.ledger.confirmedCategoryIDs(for: $0).isEmpty || store.ledger.allocationCategoryIDs(for: $0).contains("uncategorized"))
        }.count
    }

    var body: some View {
        TimelineView(.periodic(from: Date(), by: 60)) { _ in content(now: Date()) }
            .navigationTitle(range == .today ? "Today" : "Your time").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if !isHome {
                        NavigationLink(value: LedgerScreen.calendar) { Label("Calendar", systemImage: "calendar") }
                            .accessibilityIdentifier("dashboard.calendar")
                    }
                    Button("Categories") { managingGroups = true }.accessibilityIdentifier("dashboard.groups")
                }
            }
            .sheet(isPresented: $managingGroups) { GroupManagerView() }
            .sheet(item: $selectedGroup) { group in
                GroupEntriesView(day: group.start ?? Date(), groupID: group.id, initialName: group.name, rangeStart: group.start, rangeEnd: group.end)
            }

    }

    private func content(now: Date) -> some View {
        let report = store.ledger.history(range: range, start: start, end: end, now: now)
        return List {
            Section {
                if !isHome {
                    Picker("Period", selection: $range) {
                        ForEach(HistoryRange.allCases) { Text($0.name).tag($0) }
                    }.pickerStyle(.menu).accessibilityIdentifier("report.range")
                }
                if range == .custom {
                    DatePicker("From", selection: $start, in: ...now, displayedComponents: [.date]).accessibilityIdentifier("report.from")
                    DatePicker("Through", selection: $end, in: ...now, displayedComponents: [.date]).accessibilityIdentifier("report.through")
                }
                HistoryPanel(report: report, expandsBreakdown: isHome) { row in
                    guard row.id != "remaining" else { return }
                    selectedGroup = SelectedGroup(id: row.id, name: row.name, start: report.start, end: report.end)
                }.listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            } header: {
                Text("Where your time went").font(.headline).textCase(nil).accessibilityIdentifier("dashboard.breakdown-title")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(store.duration(report.trackedMinutes)) tracked · \(report.samples.count) logs")
                    if !isHome {
                        if report.remainingMinutes > 0 { Text("Percentages include time remaining until bedtime.") }
                        else { Text("Percentages start at each day’s first log and end at now or bedtime. Days without logs are excluded.") }
                    }
                    Text("Swipe the chart for breakdown, pie, and trend.")
                }
            }
            if ungrouped > 0 || store.canUndoGrouping {
                Section {
                    if ungrouped > 0 {
                        Button { selectedGroup = SelectedGroup(id: "uncategorized", name: "Uncategorized") } label: {
                            Label("\(ungrouped) logs to group", systemImage: "tray")
                        }.accessibilityIdentifier("dashboard.review.uncategorized")
                    }
                    if store.canUndoGrouping {
                        Button("Undo last categorization") { store.undoCategorization() }.accessibilityIdentifier("dashboard.undo")
                    }
                }
            }
            if isHome {
                Section {
                    NavigationLink("Calendar", value: LedgerScreen.calendar).accessibilityIdentifier("dashboard.calendar")
                    NavigationLink("Charts & history", value: LedgerScreen.history).accessibilityIdentifier("dashboard.history")
                }
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
                DatePicker("Waking date", selection: $day, in: ...now, displayedComponents: [.date]).environment(\.timeZone, store.ledger.reportingCalendar().timeZone).padding(.horizontal)
                DayCalendarView(day: day, now: now)
            }
        }.navigationTitle("Calendar").navigationBarTitleDisplayMode(.inline)
            .onAppear { day = store.ledger.wakingDay(containing: Date()) }
    }
}
