import SwiftUI
import LedgerCore

/// Shared with the unified screen. Category demand is counted once; a dated
/// goal's work is already part of its category, not additional budget time.
struct DailyGoalCapacityView: View {
    @EnvironmentObject private var store: LedgerStore
    let report: DailyGoalsReport
    let editWindow: () -> Void
    @State private var showingExplanation = false
    private let colors: [Color] = [.teal, .indigo, .orange, .pink, .blue, .purple, .mint]
    var body: some View { timeLeft(report).buttonStyle(.borderless) }
    private func color(_ goal: DailyGoalProgress, in report: DailyGoalsReport) -> Color {
        guard !goal.isRollup, goal.targetMinutes > 0 else { return .secondary }
        let colored = report.commitments.filter { $0.targetMinutes > 0 }
        return colors[(colored.firstIndex(where: { $0.id == goal.id }) ?? 0) % colors.count]
    }

    private func timeLeft(_ report: DailyGoalsReport) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(store.duration(report.window.remainingMinutes)) left today")
                        .font(.title2.bold()).monospacedDigit()
                        .accessibilityIdentifier("goals.time-left")
                    Button { editWindow() } label: {
                        Text("\(store.time(report.window.interval.start))–\(store.time(report.window.interval.end))")
                            .font(.subheadline)
                    }.accessibilityLabel("Day window \(store.time(report.window.interval.start)) to \(store.time(report.window.interval.end)). Change")
                        .accessibilityIdentifier("goals.day-window")
                }
                Spacer(minLength: 4)
                Button { showingExplanation = true } label: { Image(systemName: "info.circle").frame(width: 32, height: 32) }
                    .accessibilityLabel("About time left and goal estimates")
                    .popover(isPresented: $showingExplanation) {
                        ScrollView { VStack(alignment: .leading, spacing: 12) {
                            Text("Time left today").font(.headline)
                            Text("The upper bar is the entire configured day. Dark gray is elapsed clock time. The Now marker separates elapsed from remaining time. Colored sections after Now are time still needed for goals; light gray is left for other activities. These amounts are not an activity schedule or calendar availability.")
                            Text("Favorite goals appear here. Select rows in Edit goals to favorite or unfavorite them; selecting a parent applies to its current children. Remaining goal time covers these favorites. Focus tasks below them use the same category time and are not added a second time. Other goals and logged time stay saved.")
                            Text("Goal bar lengths share one scale: a two-hour goal is twice as long as a one-hour goal. Filled color is logged progress inside that goal. Tap a category for its inbox items and logs. If goals do not fit, their colored time stops at the day’s end and the shortfall shows the extra time needed.")
                            Text("Daily goal hours are your fixed percentages of this window. All of today’s logs count, including outside it. Unrecorded or uncategorized activity can make progress look lower.")
                            Text("Changing the shared window also changes check-in hours when All day notifications are off. It never blocks logging.")
                        }.font(.subheadline).padding() }.frame(width: 300, height: 390)
                            .presentationCompactAdaptation(.popover)
                    }
            }
            wholeDayBar(report)
            dayLegend
            VStack(alignment: .leading, spacing: 4) {
                Text("\(store.duration(report.neededMinutes)) left across your goals").font(.subheadline.weight(.medium))
                    .accessibilityIdentifier("goals.needed")
                if report.shortfallMinutes >= 1 {
                    Text("\(store.duration(report.shortfallMinutes)) more than the time left")
                        .foregroundStyle(.orange).accessibilityIdentifier("goals.shortfall")
                } else {
                    Text("\(store.duration(report.otherMinutes)) for other activities")
                        .foregroundStyle(.secondary).accessibilityIdentifier("goals.other-time")
                }
            }.font(.subheadline)
        }
    }

    private var elapsedColor: Color { Color.secondary.opacity(0.48) }
    private var otherColor: Color { Color.secondary.opacity(0.18) }

    private var dayLegend: some View {
        HStack(spacing: 16) {
            legend("Elapsed", color: elapsedColor)
            legend("Goals", color: .teal)
            legend("Other", color: otherColor)
        }.font(.caption).foregroundStyle(.secondary)
    }
    private func legend(_ name: String, color: Color) -> some View {
        HStack(spacing: 4) { RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10); Text(name) }
    }

    private func wholeDayBar(_ report: DailyGoalsReport) -> some View {
        GeometryReader { proxy in
            let nowX = proxy.size.width * report.window.elapsedMinutes / report.window.minutes
            HStack(spacing: 0) {
                ForEach(report.dayBarSegments) { segment in
                    Rectangle().fill(segmentColor(segment, report: report))
                        .frame(width: proxy.size.width * segment.minutes / report.window.minutes)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(segmentLabel(segment, report: report))
                        .accessibilityValue(store.duration(segment.minutes))
                        .accessibilityIdentifier("goals.day-segment.\(segment.id)")
                }
            }.frame(height: 24).clipShape(RoundedRectangle(cornerRadius: 8))
            Rectangle().fill(Color.primary).frame(width: 2, height: 30)
                .offset(x: min(nowX, max(0, proxy.size.width - 2)), y: -3)
                .accessibilityHidden(true)
            Text("Now").font(.caption2.weight(.medium))
                .frame(width: 32).offset(x: min(max(0, nowX - 16), max(0, proxy.size.width - 32)), y: 29)
            if report.shortfallMinutes > 0 {
                Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
                    .background(.background, in: Circle()).offset(x: max(0, proxy.size.width - 14), y: -10)
                    .accessibilityHidden(true)
            }
        }.frame(height: 44)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Whole day: elapsed, remaining goals, and other time")
            .accessibilityValue("\(store.duration(report.window.elapsedMinutes)) elapsed, \(store.duration(report.window.remainingMinutes)) left, \(store.duration(report.neededMinutes)) needed, \(store.duration(report.shortfallMinutes)) shortfall")
            .accessibilityIdentifier("goals.capacity-bar")
    }

    private func segmentColor(_ segment: GoalDayBarSegment, report: DailyGoalsReport) -> Color {
        switch segment.kind {
        case .elapsed: return elapsedColor
        case .other: return otherColor
        case .goal(let id): return report.commitments.first { $0.id == id }.map { color($0, in: report) } ?? .teal
        }
    }

    private func segmentLabel(_ segment: GoalDayBarSegment, report: DailyGoalsReport) -> String {
        switch segment.kind {
        case .elapsed: return "Elapsed clock time"
        case .other: return "Other remaining time"
        case .goal(let id):
            return "\(report.commitments.first { $0.id == id }?.category.name ?? "Goal") time still needed"
        }
    }


}

struct DailyCategoryGoalRow: View {
    @EnvironmentObject private var store: LedgerStore
    let goal: DailyGoalProgress
    let report: DailyGoalsReport
    var showsName = true
    var unreviewedMinutes = 0.0
    let onSelect: () -> Void
    private let colors: [Color] = [.teal, .indigo, .orange, .pink, .blue, .purple, .mint]
    private func color(_ goal: DailyGoalProgress, in report: DailyGoalsReport) -> Color {
        guard !goal.isRollup, goal.targetMinutes > 0 else { return .secondary }
        let colored = report.commitments.filter { $0.targetMinutes > 0 }
        return colors[(colored.firstIndex(where: { $0.id == goal.id }) ?? 0) % colors.count]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 8) {
                    Circle().fill(color(goal, in: report)).frame(width: 8, height: 8).accessibilityHidden(true)
                    Text(showsName ? goal.category.name : "Daily target").font(.body.weight(.medium))
                }
                Spacer(minLength: 12)
                Text(goal.isMet ? "Met" : "\(store.duration(goal.remainingMinutes)) left")
                    .font(.subheadline.weight(.medium)).monospacedDigit()
            }.contentShape(Rectangle())

                .accessibilityElement(children: .ignore)
                .accessibilityLabel(goal.category.name)
                .accessibilityValue("\(store.duration(goal.actualMinutes)) of \(store.duration(goal.targetMinutes)) today. \(goal.isMet ? "Goal met" : "\(store.duration(goal.remainingMinutes)) remaining")")
                .accessibilityHint("Open inbox items and logs for this category")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { onSelect() }
                .accessibilityIdentifier("goals.progress.\(goal.id)")
            GeometryReader { proxy in
                let width = proxy.size.width * report.goalWidthFraction(goal)
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4).fill(color(goal, in: report).opacity(0.2))
                    RoundedRectangle(cornerRadius: 4).fill(color(goal, in: report)).frame(width: width * goal.fraction)
                    Rectangle().fill(Color.primary).frame(width: 2, height: 16)
                        .offset(x: max(0, min(width - 2, width * report.window.elapsedMinutes / report.window.minutes)))
                }.frame(width: width, height: 10)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(goal.category.name) daily goal")
                    .accessibilityValue("\(store.duration(goal.actualMinutes)) of \(store.duration(goal.targetMinutes)). Pace line: \(Int(report.window.elapsedMinutes / report.window.minutes * 100)) percent expected by now")
                    .accessibilityIdentifier("goals.target-bar.\(goal.id)")
            }.frame(height: 10)
            Text("\(store.duration(goal.actualMinutes)) of \(store.duration(goal.targetMinutes)) today").font(.caption).foregroundStyle(.secondary)
            if unreviewedMinutes > 0 { Text("Includes \(store.duration(unreviewedMinutes)) awaiting category review").font(.caption2).foregroundStyle(.secondary) }

        }.contentShape(Rectangle()).onTapGesture(perform: onSelect)
    }

}
