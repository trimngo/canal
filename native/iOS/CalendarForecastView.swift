import SwiftUI
import LedgerCore

struct CalendarForecastListView: View {
    @EnvironmentObject private var store: LedgerStore
    @Environment(\.dismiss) private var dismiss
    let forecast: CalendarDayForecast
    var categoryID: String?
    var directOnly = false
    private var events: [CategorizedCalendarEvent] {
        guard let categoryID else { return forecast.events }
        let family = Set([categoryID] + (directOnly ? [] : store.ledger.descendants(of: categoryID).map(\.id)))
        return forecast.events.filter { !Set($0.categoryIDs).isDisjoint(with: family) }
    }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(events) { event in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(event.snapshot.title).font(.headline)
                            Text("\(store.time(event.snapshot.start))–\(store.time(event.snapshot.end)) · \(event.snapshot.calendarName)")
                                .font(.subheadline).foregroundStyle(.secondary)
                            Text(Array(Set(event.categoryIDs)).sorted().map { store.ledger.categoryPath($0) }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary)
                            Label("Planned · needs confirmation after it ends", systemImage: "calendar")
                                .font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical, 4).accessibilityElement(children: .combine)
                            .accessibilityIdentifier("forecast.event.\(event.id)")
                    }
                } header: { Text("Remaining timed events") } footer: {
                    Text("This is a preview of selected calendars. Overlapping events share their time. All-day, free and declined events are excluded. Ended events go to Review logs and become recorded time only after you confirm them.")
                }
            }.navigationTitle("Rest of today").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

struct CalendarPlanHatching: View {
    var color: Color = .secondary
    var body: some View {
        Canvas { context, size in
            var lines = Path()
            for offset in stride(from: 0.0, through: size.width + size.height, by: 7) {
                lines.move(to: CGPoint(x: offset, y: 0))
                lines.addLine(to: CGPoint(x: offset - size.height, y: size.height))
            }
            context.stroke(lines, with: .color(color.opacity(0.7)), lineWidth: 1)
        }.clipped().accessibilityHidden(true)
    }
}
