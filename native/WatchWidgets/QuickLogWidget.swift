import SwiftUI
import WidgetKit
import LedgerCore

private struct LogEntry: TimelineEntry { let date: Date }

private struct LogProvider: TimelineProvider {
    func placeholder(in context: Context) -> LogEntry { LogEntry(date: Date()) }
    func getSnapshot(in context: Context, completion: @escaping (LogEntry) -> Void) {
        completion(LogEntry(date: Date()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<LogEntry>) -> Void) {
        // A static launch button needs no background refresh or access to logs.
        completion(Timeline(entries: [LogEntry(date: Date())], policy: .never))
    }
}

private struct LogComplicationView: View {
    @Environment(\.widgetFamily) private var family
    var body: some View {
        content
            .widgetURL(WatchLogShortcut.url)
            .containerBackground(.fill.tertiary, for: .widget)
            .accessibilityLabel("Log current activity")
            .accessibilityHint("Opens dictation. Done saves your log.")
    }
    @ViewBuilder private var content: some View {
        switch family {
        case .accessoryInline:
            Label("Log now", systemImage: "mic.fill")
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 3) {
                Label("Log now", systemImage: "mic.fill").font(.headline)
                Text("Tap to dictate").font(.caption)
            }
        case .accessoryCorner:
            Image(systemName: "mic.fill").font(.title2).widgetAccentable()
                .widgetLabel { Text("Log now") }
        default:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "mic.fill").font(.title2).widgetAccentable()
            }
        }
    }
}

struct DashQuickLogWidget: Widget {
    let kind = "DashQuickLog"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LogProvider()) { _ in LogComplicationView() }
            .configurationDisplayName("Log activity")
            .description("Dictate what you’re doing and save it when you tap Done.")
            .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryRectangular, .accessoryInline])
    }
}

@main
struct DashWidgets: WidgetBundle {
    var body: some Widget {
        DashQuickLogWidget()
        DashAddTimerWidget()
        DashCurrentTimerWidget()
    }
}
