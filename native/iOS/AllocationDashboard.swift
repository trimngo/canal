import SwiftUI
import LedgerCore

struct DayView: View {
    @EnvironmentObject var store: LedgerStore
    @State private var managingCategories = false
    @State private var reviewing = false
    var body: some View {
        TimelineView(.periodic(from: Date(), by: 60)) { context in
            content(now: context.date)
        }.navigationTitle("Today").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("Categories") { managingCategories = true }.accessibilityIdentifier("dashboard.groups")
                    Menu {
                        NavigationLink("Calendar", value: LedgerScreen.calendar)
                        NavigationLink("Charts & history", value: LedgerScreen.history)
                        NavigationLink("Waking schedule") { WakingScheduleView() }
                    } label: { Image(systemName: "ellipsis.circle") }.accessibilityLabel("More views")
                }
            }
            .sheet(isPresented: $managingCategories) { GroupManagerView() }
            .sheet(isPresented: $reviewing) { GroupEntriesView(day: Date(), groupID: "uncategorized", initialName: "Uncategorized", allTime: true) }
    }
    private func content(now: Date) -> some View {
        let day = store.ledger.wakingDay(containing: now)
        let today = store.ledger.allocation(on: day, now: now)
        let week = store.ledger.rollingAllocation(now: now)
        let targets = store.ledger.currentTargets(at: now)
        let allocated = targets.values.reduce(0, +)
        let pending = store.ledger.activeEntries.filter { (store.ledger.confirmedCategoryIDs(for: $0).isEmpty || store.ledger.allocationCategoryIDs(for: $0).contains("uncategorized")) && $0.end <= now }.count
        return List {
            Section {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Today").font(.subheadline.bold())
                        Text(today.sufficient ? "\(store.duration(today.wakingMinutes)) waking" : "Insufficient data").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Rolling 7 days").font(.subheadline.bold())
                        Text("\(week.representedDays) of 7 days · \(store.duration(week.wakingMinutes))").font(.caption).foregroundStyle(.secondary)
                    }
                }.accessibilityIdentifier("allocation.periods")
                if week.representedDays < 7 {
                    Text("Incomplete window: \(week.representedDays) of 7 days represented. Days without waking-period logs are excluded.")
                        .font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("allocation.coverage")
                }
                if !today.sufficient {
                    Text("Log an activity during your waking period to estimate today. No activities are inferred for a day with no logs.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let bounds = store.ledger.wakingBounds(on: day) {
                    Text("Waking day \(store.dayLabel(day)): \(store.time(bounds.start))–\(store.time(bounds.end)) · \(store.ledger.reportingCalendar().timeZone.identifier)")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            } header: { Text("Where your time went").textCase(nil).font(.headline).accessibilityIdentifier("dashboard.breakdown-title") }
            Section {
                ForEach(store.ledger.children(of: nil)) { category in
                    AllocationCategoryRow(category: category, today: today, week: week, target: targets[category.id])
                }
                if today.directMinutes["uncategorized", default: 0] > 0 || week.directMinutes["uncategorized", default: 0] > 0 {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Uncategorized").font(.headline)
                        AllocationValues(today: today, week: week, todayMinutes: today.directMinutes["uncategorized", default: 0], weekMinutes: week.directMinutes["uncategorized", default: 0], target: nil)
                    }
                }
            } footer: {
                Text("Percentages use waking hours, not just the time between logs. Differences are percentage points from your target; more time is not necessarily better. Expand a category for its breakdown.")
            }
            Section {
                HStack { Text("Unallocated target"); Spacer(); Text("\(max(0, 100 - allocated), specifier: "%.1f")%").bold() }
                Text("≈ \(store.duration(store.ledger.typicalWakingMinutes * max(0, 100 - allocated) / 100)) per typical waking day without a target. This is separate from Uncategorized activity.").font(.caption).foregroundStyle(.secondary)
                if store.ledger.currentBudget(at: now) == nil {
                    Button("Set long-term targets") { managingCategories = true }
                }
            }
            if pending > 0 || store.canUndoGrouping {
                Section {
                    if pending > 0 {
                        Button("\(pending) logs to categorize") { reviewing = true }.accessibilityIdentifier("dashboard.review.uncategorized")
                    }
                    if store.canUndoGrouping { Button("Undo last categorization") { store.undoCategorization() }.accessibilityIdentifier("dashboard.undo") }
                }
            }
            Section {
                NavigationLink("Calendar", value: LedgerScreen.calendar).accessibilityIdentifier("dashboard.calendar")
                NavigationLink("Charts & history", value: LedgerScreen.history).accessibilityIdentifier("dashboard.history")
            }
        }.listStyle(.insetGrouped).listSectionSpacing(12)
    }
}

private struct AllocationCategoryRow: View {
    @EnvironmentObject var store: LedgerStore
    let category: LedgerCategory
    let today: AllocationPeriod
    let week: AllocationPeriod
    var target: Double? = nil
    @State private var expanded = false
    @State private var viewingLogs = false
    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 8) {
                Button("View logs") { viewingLogs = true }.font(.caption)
                let children = store.ledger.children(of: category.id)
                if !children.isEmpty {
                    Text("Directly assigned to \(category.name)").font(.caption.bold())
                    AllocationValues(today: today, week: week, todayMinutes: today.directMinutes[category.id, default: 0], weekMinutes: week.directMinutes[category.id, default: 0], target: nil)
                    ForEach(children) { child in childRow(child) }
                }
            }.padding(.vertical, 6)
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text(category.name).font(.headline)
                    Spacer(minLength: 2)
                    Text(target.map { "Target \($0.formatted(.number.precision(.fractionLength(0...1))))%" } ?? "No target").font(.caption).foregroundStyle(.secondary)
                }
                AllocationValues(today: today, week: week, todayMinutes: today.total(for: category.id, ledger: store.ledger), weekMinutes: week.total(for: category.id, ledger: store.ledger), target: target)
            }.padding(.vertical, 3)
        }.accessibilityIdentifier("dashboard.group.\(category.id)")
            .sheet(isPresented: $viewingLogs) { GroupEntriesView(day: Date(), groupID: category.id, initialName: category.name, allTime: true) }
    }
    private func childRow(_ category: LedgerCategory) -> AnyView {
        AnyView(AllocationCategoryRow(category: category, today: today, week: week))
    }
}

private struct AllocationValues: View {
    @EnvironmentObject var store: LedgerStore
    let today: AllocationPeriod
    let week: AllocationPeriod
    let todayMinutes: Double
    let weekMinutes: Double
    let target: Double?
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            value("Today", period: today, minutes: todayMinutes)
            value("7 days", period: week, minutes: weekMinutes)
        }.foregroundStyle(.primary)
    }
    private func value(_ title: String, period: AllocationPeriod, minutes: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(period.sufficient ? "\(period.percent(minutes).formatted(.number.precision(.fractionLength(1))))%" : "—").font(.title3.bold()).monospacedDigit()
                Text(title).font(.caption2).foregroundStyle(.secondary)
            }
            Text(period.sufficient ? store.duration(minutes) : "Insufficient data").font(.caption).foregroundStyle(.secondary)
            if let target, period.sufficient {
                let delta = period.percent(minutes) - target
                Text("\(delta >= 0 ? "+" : "")\(delta.formatted(.number.precision(.fractionLength(1)))) pp").font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
