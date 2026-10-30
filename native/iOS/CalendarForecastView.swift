import SwiftUI
import LedgerCore

struct CalendarForecastListView: View {
    @EnvironmentObject private var store: LedgerStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var calendars = CalendarImport.shared
    @State private var editing: CategorizedCalendarEvent?
    let forecast: CalendarDayForecast
    var categoryID: String?
    var directOnly = false
    private var currentForecast: CalendarDayForecast {
        var now = Date()
        #if DEBUG
        if CalendarForecastFixture.enabled { now = CalendarForecastFixture.now }
        #endif
        return store.ledger.calendarForecast(calendars.plannedEvents, on: forecast.start, now: now)
    }
    private var events: [CategorizedCalendarEvent] {
        guard let categoryID else { return currentForecast.events }
        let family = Set([categoryID] + (directOnly ? [] : store.ledger.descendants(of: categoryID).map(\.id)))
        return currentForecast.events.filter { !Set($0.categoryIDs).isDisjoint(with: family) }
    }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(events) { event in
                        Button {
                            editing = calendars.plannedEvents.first { $0.id == event.id } ?? event
                        } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(event.snapshot.title).font(.headline)
                            Text("\(store.time(event.snapshot.start))–\(store.time(event.snapshot.end)) · \(event.snapshot.calendarName)")
                                .font(.subheadline).foregroundStyle(.secondary)
                            Text(Array(Set(event.categoryIDs)).sorted().map { store.ledger.categoryPath($0) }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary)
                            Label("Planned · needs confirmation after it ends", systemImage: "calendar")
                                .font(.caption).foregroundStyle(.secondary)
                            Label("Edit categories", systemImage: "tag").font(.caption)
                        }.padding(.vertical, 4).frame(maxWidth: .infinity, alignment: .leading)
                        }.buttonStyle(.plain).accessibilityElement(children: .combine)
                            .accessibilityIdentifier("forecast.event.\(event.id)")
                    }
                    if events.isEmpty { Text("No remaining events in this view.").foregroundStyle(.secondary) }
                } header: { Text("Remaining timed events") } footer: {
                    Text("This is a preview of selected calendars. Overlapping events share their time. All-day, free and declined events are excluded. Ended events go to Review logs and become recorded time only after you confirm them.")
                }
            }.navigationTitle("Rest of today").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                .sheet(item: $editing) { CalendarForecastCategoryView(event: $0) }
        }
    }
}

private struct CalendarForecastCategoryView: View {
    @EnvironmentObject private var store: LedgerStore
    @Environment(\.dismiss) private var dismiss
    let event: CategorizedCalendarEvent
    @State private var selection: [String] = []
    @State private var loaded = false
    @State private var error: String?
    private var hasChoice: Bool {
        store.ledger.calendarEvents?.first { $0.id == event.id }?.plannedCategoryIDs != nil
    }
    var body: some View {
        NavigationStack {
            CategorySelectionList(selection: $selection, activity: event.snapshot.title,
                selectionHelp: "Choose categories for this occurrence. Time is split equally between selected categories. This remains planned time until you confirm the event after it ends.")
                .navigationTitle("Event categories").navigationBarTitleDisplayMode(.inline)
                .safeAreaInset(edge: .bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("For this occurrence · still planned until confirmed").font(.caption).foregroundStyle(.secondary)
                        if hasChoice {
                            Button("Use suggested categories") { save(nil) }
                                .accessibilityIdentifier("forecast-categories.use-suggestion").disabled(!store.storageAvailable)
                        }
                        if let error { Text(error).font(.caption).foregroundStyle(.red) }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding().background(.bar)
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.accessibilityIdentifier("forecast-categories.cancel") }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { save(selection) }.disabled(!store.storageAvailable)
                            .accessibilityIdentifier("forecast-categories.save")
                    }
                }
                .onAppear {
                    guard !loaded else { return }; loaded = true
                    let known = Set(store.ledger.categories.map(\.id))
                    let choice = store.ledger.calendarEvents?.first { $0.id == event.id }?.plannedCategoryIDs
                    selection = (choice ?? event.categoryIDs).filter { $0 != "uncategorized" && known.contains($0) }
                }
        }
    }
    private func save(_ ids: [String]?) {
        do { try store.setPlannedCalendarCategories(event.snapshot, categoryIDs: ids); dismiss() }
        catch { self.error = error.localizedDescription }
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
