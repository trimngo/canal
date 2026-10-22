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
    private var feedbackSymbol: String? {
        switch feedback {
        case .below: return "arrow.up"
        case .above: return "arrow.down"
        case .aligned, nil: return nil
        }
    }
    private var feedbackDirection: String {
        switch feedback {
        case .below: return "Up toward goal"
        case .above: return "Down toward goal"
        case .aligned, nil: return ""
        }
    }
    var body: some View {
        HStack(spacing: 2) {
            if let feedbackSymbol {
                Image(systemName: feedbackSymbol).font(.system(size: compact ? 8 : 12, weight: .bold))
                    .frame(width: compact ? 8 : 12).accessibilityHidden(true)
            }
            Text(value).lineLimit(1).minimumScaleFactor(0.7)
        }.font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(feedbackColor)
            .frame(width: compact ? 60 : nil, alignment: .trailing)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(period.sufficient
                ? "\(title): \(value)\(unit == .time && dailyAverage ? " per day" : "")\(feedbackLabel)"
                : "\(title): insufficient data")
            .accessibilityValue(feedbackDirection)
    }
}
