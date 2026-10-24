import SwiftUI
import WidgetKit
import ActivityKit

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
                }
                Spacer()
            }.padding().activityBackgroundTint(.black).activitySystemActionForegroundColor(.mint)
                .widgetURL(URL(string: "canal-dash://timers"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Image(systemName: "timer") }
                DynamicIslandExpandedRegion(.center) { Text(context.state.title).lineLimit(2) }
                DynamicIslandExpandedRegion(.bottom) { Countdown(state: context.state).font(.title2) }
            } compactLeading: { Image(systemName: "timer") }
              compactTrailing: { Countdown(state: context.state).frame(maxWidth: 64) }
              minimal: { Image(systemName: "timer") }
              .widgetURL(URL(string: "canal-dash://timers"))
        }
    }
}
