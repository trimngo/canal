import SwiftUI
import LedgerCore

// Keep older navigation routes pointing at the current allocation editor.
struct TargetsView: View {
    var body: some View { CommitmentsView() }
}

struct AllocationCategoryRow: View {
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

struct AllocationValues: View {
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
