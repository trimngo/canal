import SwiftUI
import WidgetKit
import LedgerCore

private struct TimerEntry: TimelineEntry {
    var date: Date
    var current: TimerWidgetSnapshot?
}
private struct TimerProvider: TimelineProvider {
    func placeholder(in context: Context) -> TimerEntry {
        TimerEntry(date: Date(), current: TimerWidgetSnapshot(title: "Practice guitar", duration: 1200, dueAt: Date().addingTimeInterval(600), pausedRemaining: nil))
    }
    func getSnapshot(in context: Context, completion: @escaping (TimerEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : TimerEntry(date: Date(), current: TimerWidgetStore.read()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<TimerEntry>) -> Void) {
        let now = Date(), current = TimerWidgetStore.read()
        var entries = [TimerEntry(date: now, current: current)]
        if let due = current?.dueAt, due > now { entries.append(TimerEntry(date: due.addingTimeInterval(1), current: current)) }
        completion(Timeline(entries: entries, policy: .never))
    }
}
private struct TimerComplication: View {
    @Environment(\.widgetFamily) private var family
    let entry: TimerEntry
    let adding: Bool
    var body: some View {
        content.widgetURL(TimerQueueShortcut.current)
            .containerBackground(.fill.tertiary, for: .widget)
            .accessibilityLabel(adding ? "Open timers" : "Current timer: \(entry.current?.title ?? "No timer")")
    }
    @ViewBuilder private var countdown: some View {
        if let current = entry.current {
            if let paused = current.pausedRemaining { Text("Paused · \(Int(ceil(paused / 60)))m") }
            else if let due = current.dueAt, due > entry.date {
                Text(timerInterval: due.addingTimeInterval(-current.duration)...due, countsDown: true).monospacedDigit()
            } else { Text("Finished") }
        } else { Text("No timer") }
    }
    @ViewBuilder private var content: some View {
        if adding {
            switch family {
            case .accessoryRectangular:
                VStack(alignment: .leading) { Label("Timers", systemImage: "timer"); Text("Tap to open").font(.caption) }
            case .accessoryInline: Label("Timers", systemImage: "timer")
            case .accessoryCorner: Image(systemName: "timer").widgetLabel { Text("Timers") }
            default: ZStack { AccessoryWidgetBackground(); Image(systemName: "timer").font(.title2).widgetAccentable() }
            }
        } else {
            switch family {
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.current?.title ?? "Timer queue").font(.headline).lineLimit(2)
                    countdown.font(.caption)
                }
            case .accessoryInline:
                HStack(spacing: 4) { Text(entry.current?.title ?? "Timer").lineLimit(1); countdown }
            case .accessoryCorner:
                Image(systemName: "timer").widgetLabel { countdown }
            default:
                VStack(spacing: 2) { Image(systemName: "timer").widgetAccentable(); countdown.font(.caption2).minimumScaleFactor(0.6) }
            }
        }
    }
}
struct DashAddTimerWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "DashAddTimer", provider: TimerProvider()) { TimerComplication(entry: $0, adding: true) }
            .configurationDisplayName("Timers").description("Open your current timer. Tap + to dictate another task; swipe up to see the queue.")
            .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryRectangular, .accessoryInline])
    }
}
struct DashCurrentTimerWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "DashCurrentTimer", provider: TimerProvider()) { TimerComplication(entry: $0, adding: false) }
            .configurationDisplayName("Current task").description("See your task and countdown. Tap for Done & Next or Restart.")
            .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryRectangular, .accessoryInline])
    }
}
