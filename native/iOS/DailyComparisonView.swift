import SwiftUI
import LedgerCore

struct DailyComparisonView: View {
    @EnvironmentObject private var store: LedgerStore
    @State private var day = Date()
    @State private var report: DailyComparison?
    @State private var revision = UUID()
    @AppStorage("comparison.unit") private var unit = AllocationDisplayUnit.percent
    private var rows: [DailyComparisonRow] {
        (report?.rows ?? []).sorted {
            let a = unit == .time ? $0.minuteChange : $0.percentagePointChange
            let b = unit == .time ? $1.minuteChange : $1.percentagePointChange
            return abs(a) == abs(b) ? $0.name < $1.name : abs(a) > abs(b)
        }
    }
    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Button { move(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }.accessibilityLabel("Previous day").accessibilityIdentifier("comparison.previous")
                Spacer()
                DatePicker("Date", selection: $day, in: ...Date(), displayedComponents: .date).labelsHidden()
                    .environment(\.timeZone, store.ledger.reportingCalendar().timeZone).accessibilityIdentifier("comparison.date")
                Spacer()
                Button { move(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                    .disabled(store.ledger.reportingDay(containing: day) >= store.ledger.reportingDay(containing: Date())).accessibilityLabel("Next day").accessibilityIdentifier("comparison.next")
            }
            Picker("Unit", selection: $unit) { Text("%").tag(AllocationDisplayUnit.percent); Text("Time").tag(AllocationDisplayUnit.time) }
                .pickerStyle(.segmented).accessibilityIdentifier("comparison.unit")
            if let report {
                VStack(alignment: .leading, spacing: 3) {
                    Text(report.isToday ? "Today so far" : report.day.formatted(date: .abbreviated, time: .omitted)).font(.headline)
                    Text("Compared with average of \(report.baselineStart.formatted(.dateTime.month(.abbreviated).day()))–\(report.baselineEnd.formatted(.dateTime.month(.abbreviated).day())) · \(report.representedDays) of 7 days")
                        .font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("comparison.baseline")
                    if report.isToday { Text("Today is incomplete and is not part of the baseline.").font(.caption2).foregroundStyle(.secondary) }
                    if !report.hasData { Text("No log data for this day.").font(.subheadline).foregroundStyle(.secondary) }
                }.frame(maxWidth: .infinity, alignment: .leading)
                HStack {
                    Text("Category"); Spacer(); Text(report.isToday ? "So far" : "Day").frame(width: 65, alignment: .trailing)
                    Text("7d avg").frame(width: 65, alignment: .trailing); Text("Change").frame(width: 65, alignment: .trailing)
                }.font(.caption2).foregroundStyle(.secondary)
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(rows) { row in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(alignment: .firstTextBaseline, spacing: 6) {
                                    Text(row.name).font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
                                    Text(report.hasData ? actual(row) : "—").frame(width: 65, alignment: .trailing)
                                    Text(report.representedDays > 0 ? average(row) : "—").foregroundStyle(.secondary).frame(width: 65, alignment: .trailing)
                                    Text(report.hasData && report.representedDays > 0 ? change(row) : "—").frame(width: 65, alignment: .trailing)
                                }.font(.caption.monospacedDigit())
                                if row.averageUnreviewedMinutes > 0 { Text("Average includes \(store.duration(row.averageUnreviewedMinutes))/day awaiting category review").font(.caption2).foregroundStyle(.secondary) }
                                if row.unreviewedMinutes > 0 { Text("Includes \(store.duration(row.unreviewedMinutes)) awaiting category review").font(.caption2).foregroundStyle(.secondary) }
                            }.padding(.vertical, 12).accessibilityElement(children: .combine).accessibilityIdentifier("comparison.row.\(row.id)")
                            Divider()
                        }
                    }
                }
            } else { ProgressView().frame(maxHeight: .infinity) }
        }.accessibilityElement(children: .contain)
        .task(id: revision) {
            let ledger = store.ledger, day = day
            let job = Task.detached(priority: .userInitiated) { ledger.dailyComparison(on: day) }
            let result = await withTaskCancellationHandler(operation: { await job.value }, onCancel: { job.cancel() })
            if !Task.isCancelled { report = result }
        }
        .onChange(of: day) { _, _ in revision = UUID() }
        .onChange(of: store.ledger) { _, _ in revision = UUID() }
        .onAppear { revision = UUID() }
    }
    private func move(_ amount: Int) { day = store.ledger.reportingCalendar().date(byAdding: .day, value: amount, to: day) ?? day }
    private func actual(_ row: DailyComparisonRow) -> String { unit == .time ? store.duration(row.minutes) : String(format: "%.1f%%", row.percent) }
    private func average(_ row: DailyComparisonRow) -> String { unit == .time ? store.duration(row.averageMinutes) : String(format: "%.1f%%", row.averagePercent) }
    private func change(_ row: DailyComparisonRow) -> String {
        let delta = unit == .time ? row.minuteChange : row.percentagePointChange
        if abs(delta) < (unit == .time ? 0.5 : 0.05) { return unit == .time ? "0m" : "0 pp" }
        let sign = delta > 0 ? "+" : "−"
        return sign + (unit == .time ? store.duration(abs(delta)) : String(format: "%.1f pp", abs(delta)))
    }
}
