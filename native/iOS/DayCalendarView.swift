import SwiftUI
import LedgerCore

private struct CalendarActivity: Identifiable {
    var id: String
    var start: Date
    var end: Date
    var activity: String
    var categoryIDs: [String]
    var confirmed: Bool
    var samples: [CheckIn]
}

struct DayCalendarView: View {
    @EnvironmentObject var store: LedgerStore
    let day: Date
    let now: Date
    @State private var selected: CalendarActivity?
    private let hourHeight: CGFloat = 72
    private var bounds: DateInterval {
        store.ledger.dayBounds(on: day)
            ?? DateInterval(start: Calendar.current.startOfDay(for: day), duration: 86400)
    }
    private var height: CGFloat { CGFloat(bounds.duration / 3600) * hourHeight }
    private func y(_ date: Date) -> CGFloat { CGFloat(date.timeIntervalSince(bounds.start) / 3600) * hourHeight }
    private var hours: [Date] {
        let calendar = store.ledger.reportingCalendar()
        var result: [Date] = [bounds.start]
        var hour = calendar.dateInterval(of: .hour, for: bounds.start)?.start ?? bounds.start
        if hour <= bounds.start { hour = hour.addingTimeInterval(3600) }
        while hour <= bounds.end { result.append(hour); hour = hour.addingTimeInterval(3600) }
        return result
    }
    private var samples: [CheckIn] { store.ledger.daySamples(on: day, now: now) }
    private var blocks: [CalendarActivity] {
        let observations = Dictionary(store.ledger.activeEntries.map { ($0.id, $0) }, uniquingKeysWith: { $0.revision < $1.revision ? $1 : $0 })
        var result: [CalendarActivity] = []
        for segment in store.ledger.inferredSegments(on: day, now: now) {
            guard let sample = observations[segment.sampleID] else { continue }
            let groupIDs = store.ledger.confirmedCategoryIDs(for: sample)
            if let last = result.last, last.end == segment.start,
               last.categoryIDs == groupIDs, last.confirmed == (sample.intervalStart != nil),
               last.activity.caseInsensitiveCompare(sample.activity) == .orderedSame {
                result[result.count - 1].end = segment.end
                result[result.count - 1].samples.append(sample)
            } else {
                result.append(CalendarActivity(id: sample.id + ":" + String(segment.start.timeIntervalSince1970), start: segment.start, end: segment.end,
                                               activity: sample.activity, categoryIDs: groupIDs, confirmed: sample.intervalStart != nil, samples: [sample]))
            }
        }
        return result
    }
    private func color(_ categoryID: String?) -> Color {
        guard let categoryID else { return .secondary }
        let palette: [Color] = [.teal, .blue, .purple, .orange, .pink, .indigo]
        let index = categoryID.utf8.reduce(0) { ($0 * 31 + Int($1)) % palette.count }
        return palette[index]
    }
    private var scrollTarget: String {
        if store.ledger.reportingCalendar().isDate(day, inSameDayAs: now) { return "timeline.now" }
        return blocks.first.map { "timeline.block.\($0.id)" } ?? "timeline.noon"
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Activities · dots mark instantaneous samples")
                .font(.caption).foregroundStyle(.secondary).padding(.horizontal)
            ScrollViewReader { proxy in
                ScrollView {
                    ZStack(alignment: .topLeading) {
                        ForEach(hours, id: \.self) { hour in
                            hourLine(hour).padding(.top, max(0, y(hour)))
                        }
                        ForEach(blocks) { block in
                            let blockHeight = y(block.end) - y(block.start)
                            Button { selected = block } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    if blockHeight >= 22 { Text(block.activity).font(.caption.bold()).lineLimit(1) }
                                    if blockHeight >= 42 { Text(block.categoryIDs.isEmpty ? "Uncategorized" : block.categoryIDs.map { store.ledger.categoryPath($0) }.joined(separator: " + ")).font(.caption2).lineLimit(1) }
                                }.padding(.horizontal, 6)
                                    .frame(maxWidth: .infinity, minHeight: blockHeight, maxHeight: blockHeight, alignment: .topLeading)
                                    .background(color(block.categoryIDs.first).opacity(0.22))
                                    .overlay(alignment: .leading) { Rectangle().fill(color(block.categoryIDs.first)).frame(width: 3) }
                                    .clipped()
                            }.buttonStyle(.plain)
                                .accessibilityIdentifier("timeline.block")
                                .accessibilityLabel("\(block.activity), \(block.confirmed ? "confirmed" : "estimated") \(store.time(block.start)) to \(store.time(block.end)), \(block.categoryIDs.isEmpty ? "Uncategorized" : block.categoryIDs.map { store.ledger.categoryPath($0) }.joined(separator: " + "))")
                                .id("timeline.block.\(block.id)")
                                .padding(.leading, 64).padding(.trailing, 8)
                                .padding(.top, y(block.start))
                        }
                        ForEach(samples) { sample in
                            Circle().fill(.primary).frame(width: 6, height: 6)
                                .position(x: 61, y: y(sample.end)).allowsHitTesting(false)
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel("Logged sample: \(sample.activity)")
                                .accessibilityValue(store.time(sample.end))
                                .accessibilityIdentifier("timeline.sample.\(sample.id)")
                        }
                        if let noon = hours.first(where: { store.ledger.reportingCalendar().component(.hour, from: $0) == 12 }) {
                            hourLine(noon, emphasize: true).id("timeline.noon").padding(.top, y(noon)).allowsHitTesting(false)
                        }
                        if now >= bounds.start, now < bounds.end {
                            HStack(spacing: 4) {
                                Text("Now").font(.caption2.bold()).frame(width: 56, alignment: .trailing)
                                Rectangle().frame(height: 1)
                            }.foregroundStyle(.red).frame(height: 1).id("timeline.now")
                                .padding(.top, y(now)).allowsHitTesting(false)
                        }
                    }.frame(height: height + 24, alignment: .topLeading)
                }.accessibilityIdentifier("timeline.grid")
                    .onAppear { proxy.scrollTo(scrollTarget, anchor: .center) }
                    .onChange(of: day) { _, _ in proxy.scrollTo(scrollTarget, anchor: .center) }
            }
        }.sheet(item: $selected) { block in CalendarActivityDetail(block: block) }
    }
    private func hourLine(_ date: Date, emphasize: Bool = false) -> some View {
        HStack(spacing: 8) {
            Text(emphasize ? "Noon" : store.time(date)).font(.caption2)
                .fontWeight(emphasize ? .bold : .regular).frame(width: 56, alignment: .trailing)
            Rectangle().fill(emphasize ? Color.primary.opacity(0.35) : Color.secondary.opacity(0.16)).frame(height: 1)
        }.foregroundStyle(.secondary).frame(height: 1)
    }
}

private struct CalendarActivityDetail: View {
    @EnvironmentObject var store: LedgerStore
    @Environment(\.dismiss) var dismiss
    let block: CalendarActivity
    var body: some View {
        NavigationStack {
            List {
                Section(block.confirmed ? "Confirmed calendar period" : "Estimated activity") {
                    Text(block.activity).font(.headline)
                    Text("\(store.time(block.start))–\(store.time(block.end)) · \(store.duration(block.end.timeIntervalSince(block.start) / 60))")
                    Text(block.categoryIDs.isEmpty ? "Uncategorized" : block.categoryIDs.map { store.ledger.categoryPath($0) }.joined(separator: " + ")).foregroundStyle(.secondary)
                }
                Section {
                    ForEach(block.samples.filter { !store.ledger.isLogDeleted($0.id) }) { sample in
                        NavigationLink {
                            ScrollView { CheckInEditor(entry: sample) { dismiss() }.padding(24) }
                                .navigationTitle("Edit log").navigationBarTitleDisplayMode(.inline)
                        } label: {
                            VStack(alignment: .leading) {
                                Text(sample.activity)
                                Text(store.time(sample.end)).font(.caption).foregroundStyle(.secondary)
                            }
                        }.swipeActions {
                            Button("Delete", role: .destructive) {
                                do { try store.deleteLog(sample) } catch { store.report(error) }
                            }
                        }
                    }
                } header: { Text(block.confirmed ? "Calendar log" : "Supporting samples") } footer: {
                    Text(block.confirmed ? "This period was confirmed from your calendar. Deleting it restores estimates from the original samples." : "Tap a sample to change its activity, category, or time. The calendar is inferred from these observations.")
                }
            }.safeAreaInset(edge: .bottom, spacing: 0) { LogDeletionUndoBar() }
                .navigationTitle("Activity").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
                .onChange(of: store.ledger.logDeletions) { _, _ in
                    if block.samples.contains(where: { store.ledger.isLogDeleted($0.id) }) { dismiss() }
                }
        }
    }
}
