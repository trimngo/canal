import SwiftUI
import LedgerCore

// Keep older navigation routes pointing at the current allocation editor.
struct TargetsView: View {
    var body: some View { CommitmentsView() }
}

struct AllocationOutlineValue: View {
    @EnvironmentObject private var store: LedgerStore
    let title: String
    let period: AllocationPeriod
    let minutes: Double
    let target: Double?
    var compact = true

    private var percentage: String { period.percent(minutes).formatted(.number.precision(.fractionLength(1))) }
    private var delta: Double? { target.map { period.percent(minutes) - $0 } }
    private var difference: String {
        guard let delta else { return "" }
        return "\(delta >= 0 ? "+" : "")\(delta.formatted(.number.precision(.fractionLength(1)))) pp"
    }
    var body: some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(period.sufficient ? "\(percentage)%" : "—").font(.subheadline.weight(.semibold)).monospacedDigit()
            Text(period.sufficient ? store.duration(minutes) : "No data").font(.caption2).foregroundStyle(.secondary)
            if delta != nil, period.sufficient {
                Text(difference).font(.caption2).foregroundStyle(.secondary).monospacedDigit()
            }
        }.frame(width: compact ? 60 : nil, alignment: .trailing)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(period.sufficient
                ? "\(title): \(percentage) percent, \(store.duration(minutes))\(delta == nil ? "" : ", \(difference) from goal")"
                : "\(title): insufficient data")
    }
}
