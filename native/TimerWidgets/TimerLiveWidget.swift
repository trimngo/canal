import SwiftUI
import WidgetKit
import ActivityKit
import AppIntents

private struct Countdown: View {
    let state: TimerLiveAttributes.ContentState
    var body: some View {
        if let remaining = state.pausedRemaining {
            Text("Paused · \(Int(remaining / 60))m \(Int(remaining) % 60)s")
        } else if let due = state.dueAt {
            Text(timerInterval: due.addingTimeInterval(-state.duration)...due, countsDown: true)
                .monospacedDigit()
        }
    }
}

@main
struct DashTimerLiveWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TimerLiveAttributes.self) { context in
            HStack {
                Image(systemName: "timer").font(.title2)
                VStack(alignment: .leading, spacing: 4) {
                    Text(context.state.title).font(.headline).lineLimit(2)
                    Countdown(state: context.state).font(.title2)
                    TimerStatistics(state: context.state)
                    WatchRearmHint(state: context.state)
                }
                Spacer()
                RestartTimerButton(state: context.state)
            }.padding().activityBackgroundTint(.black).activitySystemActionForegroundColor(.mint)
                .widgetURL(URL(string: "canal-dash://timers"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Image(systemName: "timer") }
                DynamicIslandExpandedRegion(.center) { Text(context.state.title).lineLimit(2) }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Countdown(state: context.state).font(.title2)
                        Spacer()
                        RestartTimerButton(state: context.state)
                    }
                    TimerStatistics(state: context.state)
                    WatchRearmHint(state: context.state)
                    }
                }
            } compactLeading: {
                Text(context.state.title).font(.caption2.weight(.semibold))
                    .lineLimit(1).truncationMode(.tail).frame(maxWidth: 76, alignment: .leading)
                    .accessibilityLabel("Task: \(context.state.title)")
            }
              compactTrailing: { Countdown(state: context.state).frame(maxWidth: 64) }
              minimal: { Image(systemName: "timer") }
              .widgetURL(URL(string: "canal-dash://timers"))
        }
    }
}

private struct TimerStatistics: View {
    let state: TimerLiveAttributes.ContentState
    var body: some View {
        if let count = state.restartCount {
            HStack(spacing: 8) {
                Text("\(count) \(count == 1 ? "restart" : "restarts")")
                HStack(spacing: 3) {
                    if let start = state.elapsedStartedAt, let end = state.dueAt, end >= start {
                        Text(timerInterval: start.addingTimeInterval(-(state.elapsedSeconds ?? 0))...end,
                             countsDown: false, showsHours: true)
                    } else {
                        Text(Duration.seconds(state.elapsedSeconds ?? 0).formatted(.time(pattern: .hourMinuteSecond)))
                    }
                    Text("total")
                }.monospacedDigit()
            }.font(.caption2).foregroundStyle(.secondary)
        }
    }
}

private struct WatchRearmHint: View {
    let state: TimerLiveAttributes.ContentState
    var body: some View {
        if state.watchRearmHint == true {
            Text("Open Dash on Watch to rearm repeating alerts")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }
}

private struct RestartTimerButton: View {
    let state: TimerLiveAttributes.ContentState
    var body: some View {
        if let token = state.token {
            Button(intent: RestartTimerIntent(token: token)) {
                Label("Restart", systemImage: "arrow.clockwise").font(.caption.weight(.semibold))
            }.buttonStyle(.bordered).tint(.mint).accessibilityIdentifier("timers.live-restart")
        }
    }
}
