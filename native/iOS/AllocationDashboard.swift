import SwiftUI
import LedgerCore

// Keep older navigation routes pointing at the current allocation editor.
struct TargetsView: View {
    var body: some View { CommitmentsView() }
}

enum AllocationDisplayUnit: String, CaseIterable, Hashable {
    case percent, time
    var label: String { self == .percent ? "%" : "Time" }
}

struct AllocationOutlineValue: View {
    @EnvironmentObject private var store: LedgerStore
    let title: String
    let period: AllocationPeriod
    let minutes: Double
    let target: Double?
    var unit: AllocationDisplayUnit = .percent
    var reference = AllocationReference()
    var dailyAverage = false
    var compact = true

    private var shownMinutes: Double { dailyAverage ? minutes / Double(max(1, period.representedDays)) : minutes }
    private var feedback: AllocationGoalFeedback? {
        guard let target, period.sufficient else { return nil }
        if unit == .time {
            guard let day = reference.averageDayMinutes else { return nil }
            return AllocationGoalFeedback(actual: shownMinutes / day * 100, goal: target)
        }
        return AllocationGoalFeedback(actual: period.percent(minutes), goal: target)
    }
    private var feedbackColor: Color {
        switch feedback {
        case .below: return .red
        case .aligned: return .green
        case .above: return .orange
        case nil: return .primary
        }
    }
    private var value: String {
        guard period.sufficient else { return "—" }
        if unit == .percent { return "\(period.percent(minutes).formatted(.number.precision(.fractionLength(1))))%" }
        return store.duration(shownMinutes).replacingOccurrences(of: " 0m", with: "")
    }
    private var feedbackLabel: String {
        switch feedback {
        case .below: return ", below goal"
        case .aligned: return ", at goal"
        case .above: return ", above goal"
        case nil: return ""
        }
    }
    var body: some View {
        Text(value).font(.subheadline.weight(.semibold)).monospacedDigit()
            .lineLimit(1).minimumScaleFactor(0.8).foregroundStyle(feedbackColor)
            .frame(width: compact ? 60 : nil, alignment: .trailing)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(period.sufficient
                ? "\(title): \(value)\(unit == .time && dailyAverage ? " per day" : "")\(feedbackLabel)"
                : "\(title): insufficient data")
    }
}
