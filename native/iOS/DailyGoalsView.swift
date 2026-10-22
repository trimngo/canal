import SwiftUI
import LedgerCore

/// The everyday view; detailed goal/category editing lives one level deeper.
struct CommitmentsView: View {
    @EnvironmentObject private var store: LedgerStore
    @State private var editingGoals = false
    @State private var editingWindow = false
    @State private var showingExplanation = false
    @State private var showingMet = false
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
                        let outstanding = report.goals.filter { !$0.isMet }
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
                                ForEach(outstanding) { goal in goalRow(goal, report: report) }
                                let met = report.goals.filter(\.isMet)
                                if !met.isEmpty {
                                    DisclosureGroup(isExpanded: $showingMet) {
                                        VStack(spacing: 22) {
                                            ForEach(met) { goal in goalRow(goal, report: report) }
                                        }.padding(.top, 16)
                                    } label: {
                                        Text("Met today (\(met.count))").font(.subheadline).foregroundStyle(.secondary)
                                    }.accessibilityIdentifier("goals.met")
                                }
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
        colors[(report.goals.firstIndex(where: { $0.id == goal.id }) ?? 0) % colors.count]
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
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Time left today").font(.headline)
                            Text("The bar fits your remaining goals into the clock time left in your configured day window. Matching colors connect it to the goals below. Gray is time not needed by those goals; appointments and other activities still use that time.")
                            Text("Daily goal hours are your fixed percentages of this window. All of today’s logs count, including outside the window. Unrecorded or uncategorized activity can make progress look lower. Parent goals are included through their children once.")
                            Text("Changing the shared window also changes check-in hours when All day notifications are off. It never blocks logging.")
                        }.font(.subheadline).padding().frame(width: 300)
                            .presentationCompactAdaptation(.popover)
                    }
            }
            remainingBar(report)
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

    private func remainingBar(_ report: DailyGoalsReport) -> some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                ForEach(report.goals.filter { !$0.isMet }) { goal in
                    Rectangle().fill(color(goal, in: report))
                        .frame(width: report.barMinutes > 0 ? proxy.size.width * goal.remainingMinutes / report.barMinutes : 0)
                }
                Rectangle().fill(Color.secondary.opacity(0.22))
                    .frame(width: report.barMinutes > 0 ? proxy.size.width * report.otherMinutes / report.barMinutes : proxy.size.width)
            }.clipShape(RoundedRectangle(cornerRadius: 8))
            // When goals do not fit, mark the available-time boundary within
            // the bar rather than making an overfull plan look feasible.
            if report.shortfallMinutes > 0, report.barMinutes > 0 {
                Rectangle().fill(Color.primary).frame(width: 2)
                    .offset(x: min(max(0, proxy.size.width * report.window.remainingMinutes / report.barMinutes), max(0, proxy.size.width - 2)))
            }
        }.frame(height: 24)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Remaining goals compared with time left")
            .accessibilityValue("\(store.duration(report.neededMinutes)) needed, \(store.duration(report.window.remainingMinutes)) in the day window, \(store.duration(report.shortfallMinutes)) shortfall")
            .accessibilityIdentifier("goals.capacity-bar")
    }

    private func goalRow(_ goal: DailyGoalProgress, report: DailyGoalsReport) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 8) {
                    Circle().fill(color(goal, in: report)).frame(width: 8, height: 8).accessibilityHidden(true)
                    Text(goal.category.name).font(.headline)
                }
                Spacer(minLength: 12)
                Text(goal.isMet ? "Met" : "\(store.duration(goal.remainingMinutes)) left")
                    .font(.subheadline.weight(.medium)).monospacedDigit()
            }
            ProgressView(value: goal.fraction).tint(color(goal, in: report)).scaleEffect(y: 1.5)
            if expandedGoal == goal.id {
                Text("\(store.duration(goal.actualMinutes)) of \(store.duration(goal.targetMinutes)) today")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.contentShape(Rectangle())
            .onTapGesture { expandedGoal = expandedGoal == goal.id ? nil : goal.id }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(goal.category.name)
            .accessibilityValue("\(store.duration(goal.actualMinutes)) of \(store.duration(goal.targetMinutes)) today. \(goal.isMet ? "Goal met" : "\(store.duration(goal.remainingMinutes)) remaining")")
            .accessibilityHint("Tap to show or hide logged and goal times")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { expandedGoal = expandedGoal == goal.id ? nil : goal.id }
            .accessibilityIdentifier("goals.progress.\(goal.id)")
    }
}
