import SwiftUI
import LedgerCore

/// The everyday view; detailed goal/category editing lives one level deeper.
struct CommitmentsView: View {
    @EnvironmentObject private var store: LedgerStore
    @State private var editingGoals = false
    @State private var editingWindow = false
    @State private var showingExplanation = false
    @State private var expandedGoal: String?
    @State private var reviewing: LogReviewRequest?
    private let colors: [Color] = [.teal, .indigo, .orange, .pink, .blue, .purple, .mint]

    var body: some View {
        TimelineView(.periodic(from: Date(), by: 60)) { context in
            let now = reportDate(context.date)
            if let report = store.ledger.dailyGoals(now: now) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        timeLeft(report)
                        if report.goals.isEmpty {
                            ContentUnavailableView {
                                Label("What do you want time for?", systemImage: "clock")
                            } description: {
                                Text("Set goals for the categories you want to focus on.")
                            } actions: {
                                Button("Set goals") { editingGoals = true }.buttonStyle(.borderedProminent)
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 22) {
                                ForEach(report.goals) { goal in goalRow(goal, report: report) }
                            }
                        }
                        if report.uncategorizedMinutes > 0 {
                            Button {
                                let ids = store.ledger.daySamples(on: now, now: now).filter {
                                    store.ledger.confirmedCategoryIDs(for: $0).isEmpty || store.ledger.allocationCategoryIDs(for: $0).contains("uncategorized")
                                }.map(\.id)
                                reviewing = LogReviewRequest(entryIDs: ids)
                            } label: {
                                Label("Review uncategorized logs", systemImage: "tag")
                                    .font(.subheadline)
                            }.accessibilityIdentifier("goals.review-logs")
                        }
                    }.padding(20)
                }.accessibilityIdentifier("goals.today")
            } else {
                ContentUnavailableView {
                    Label("Set your day window", systemImage: "clock")
                } description: {
                    Text("Choose start and end times to estimate daily goals and time remaining.")
                } actions: {
                    Button("Set day window") { editingWindow = true }.buttonStyle(.borderedProminent)
                }
            }
        }
        .navigationTitle("Commitments").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit goals") { editingGoals = true }.accessibilityIdentifier("goals.edit")
            }
        }
        .sheet(isPresented: $editingGoals) {
            NavigationStack {
                GoalEditorView()
                    .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Close") { editingGoals = false } } }
            }
        }
        .sheet(isPresented: $editingWindow) { NavigationStack { DayWindowSettingsView() } }
        .sheet(item: $reviewing) { request in LogReviewView(entryIDs: request.entryIDs) }
    }

    private func reportDate(_ date: Date) -> Date {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("--ui-daily-goals") }) {
            return ISO8601DateFormatter().date(from: "2026-10-22T17:30:00Z")!
        }
        #endif
        return date
    }

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
                    Button { editingWindow = true } label: {
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
                            Text("Every category with a goal stays listed, including goals already met and 0% goals. Parent totals include their children and Direct time. Parent totals are not added again to the day bar.")
                            Text("Goal bar lengths share one scale: a two-hour goal is twice as long as a one-hour goal. Filled color is logged progress inside that goal. Tap a row for its logged and target times. If goals do not fit, their colored time stops at the day’s end and the shortfall shows the extra time needed.")
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
                        .accessibilityLabel(segment.id)
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

    private func goalRow(_ goal: DailyGoalProgress, report: DailyGoalsReport) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 8) {
                    Circle().fill(color(goal, in: report)).frame(width: 8, height: 8).accessibilityHidden(true)
                    Text(goal.category.name).font(goal.isRollup ? .headline : .body.weight(.medium))
                    if goal.isRollup { Text("Total").font(.caption2).foregroundStyle(.secondary) }
                }.padding(.leading, CGFloat(goal.depth) * 14)
                Spacer(minLength: 12)
                Text(goal.isMet ? "Met" : "\(store.duration(goal.remainingMinutes)) left")
                    .font(.subheadline.weight(.medium)).monospacedDigit()
            }.contentShape(Rectangle())
                .onTapGesture { toggleDetail(goal.id) }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(goal.category.name)
                .accessibilityValue("\(store.duration(goal.actualMinutes)) of \(store.duration(goal.targetMinutes)) today. \(goal.isMet ? "Goal met" : "\(store.duration(goal.remainingMinutes)) remaining")\(goal.isRollup ? "; parent total" : "")")
                .accessibilityHint("Tap to show or hide logged and goal times")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { toggleDetail(goal.id) }
                .accessibilityIdentifier("goals.progress.\(goal.id)")
            GeometryReader { proxy in
                let width = proxy.size.width * report.goalWidthFraction(goal)
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4).fill(color(goal, in: report).opacity(0.2))
                    RoundedRectangle(cornerRadius: 4).fill(color(goal, in: report)).frame(width: width * goal.fraction)
                }.frame(width: width, height: 10)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(goal.category.name) daily goal")
                    .accessibilityValue("\(store.duration(goal.actualMinutes)) of \(store.duration(goal.targetMinutes))")
                    .accessibilityIdentifier("goals.target-bar.\(goal.id)")
            }.frame(height: 10)
            if expandedGoal == goal.id {
                Text("\(store.duration(goal.actualMinutes)) of \(store.duration(goal.targetMinutes)) today")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func toggleDetail(_ id: String) { expandedGoal = expandedGoal == id ? nil : id }
}
