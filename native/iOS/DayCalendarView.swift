import SwiftUI
import LedgerCore

private struct CalendarActivity: Identifiable {
    var id: String
    var start: Date
    var end: Date
    var activity: String
    var categoryID: String?
    var samples: [CheckIn]
}

struct DayCalendarView: View {
    @EnvironmentObject var store: LedgerStore
    let day: Date
    let now: Date
    @State private var selected: CalendarActivity?
    private let hourHeight: CGFloat = 72
    private var bounds: DateInterval {
        Calendar.current.dateInterval(of: .day, for: day)
            ?? DateInterval(start: Calendar.current.startOfDay(for: day), duration: 86400)
    }
    private var cutoff: Date { max(bounds.start, min(bounds.end, now)) }
    private var height: CGFloat { CGFloat(bounds.duration / 3600) * hourHeight }
    private func y(_ date: Date) -> CGFloat { CGFloat(date.timeIntervalSince(bounds.start) / 3600) * hourHeight }
    private var hours: [Date] {
        stride(from: 0.0, through: bounds.duration, by: 3600).map { bounds.start.addingTimeInterval($0) }
    }
    private var samples: [CheckIn] { store.ledger.entries(on: day).filter { $0.end <= cutoff } }
    private var blocks: [CalendarActivity] {
        let observations = Dictionary(samples.map { ($0.id, $0) }, uniquingKeysWith: { $0.revision < $1.revision ? $1 : $0 })
        var result: [CalendarActivity] = []
        for segment in store.ledger.inferredSegments(on: day, now: now) {
            guard let sample = observations[segment.sampleID] else { continue }
            if let last = result.last, last.end == segment.start,
               last.categoryID == sample.categoryID,
               last.activity.caseInsensitiveCompare(sample.activity) == .orderedSame {
                result[result.count - 1].end = segment.end
                result[result.count - 1].samples.append(sample)
            } else {
                result.append(CalendarActivity(id: sample.id, start: segment.start, end: segment.end,
                                               activity: sample.activity, categoryID: sample.categoryID, samples: [sample]))
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
        if Calendar.current.isDateInToday(day) { return "timeline.now" }
        return blocks.first.map { "timeline.block.\($0.id)" } ?? "timeline.noon"
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Estimated activities · dots mark actual samples")
                .font(.caption).foregroundStyle(.secondary).padding(.horizontal)
            ScrollViewReader { proxy in
                ScrollView {
                    ZStack(alignment: .topLeading) {
                        if let first = blocks.first, y(first.start) > 0 {
                            unestimatedArea(until: first.start)
                        } else if blocks.isEmpty {
                            unestimatedArea(until: cutoff)
                        }
                        ForEach(hours, id: \.self) { hour in
                            hourLine(hour).padding(.top, max(0, y(hour)))
                        }
                        ForEach(blocks) { block in
                            let blockHeight = y(block.end) - y(block.start)
                            Button { selected = block } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    if blockHeight >= 22 { Text(block.activity).font(.caption.bold()).lineLimit(1) }
                                    if blockHeight >= 42 { Text(store.categoryName(block.categoryID)).font(.caption2).lineLimit(1) }
                                }.padding(.horizontal, 6)
                                    .frame(maxWidth: .infinity, minHeight: blockHeight, maxHeight: blockHeight, alignment: .topLeading)
                                    .background(color(block.categoryID).opacity(0.22))
                                    .overlay(alignment: .leading) { Rectangle().fill(color(block.categoryID)).frame(width: 3) }
                                    .clipped()
                            }.buttonStyle(.plain)
                                .accessibilityIdentifier("timeline.block")
                                .accessibilityLabel("\(block.activity), estimated \(store.time(block.start)) to \(store.time(block.end)), \(store.categoryName(block.categoryID))")
                                .id("timeline.block.\(block.id)")
                                .padding(.leading, 64).padding(.trailing, 8)
                                .padding(.top, y(block.start))
                        }
                        ForEach(samples) { sample in
                            Circle().fill(.primary).frame(width: 6, height: 6)
                                .position(x: 61, y: y(sample.end)).allowsHitTesting(false)
                        }
                        if let noon = hours.first(where: { Calendar.current.component(.hour, from: $0) == 12 }) {
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
    private func unestimatedArea(until date: Date) -> some View {
        Text(y(date) >= 30 ? "Unestimated" : "")
            .font(.caption).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: max(0, y(date)), maxHeight: max(0, y(date)))
            .background(.secondary.opacity(0.08)).padding(.leading, 64).padding(.trailing, 8)
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
                Section("Estimated activity") {
                    Text(block.activity).font(.headline)
                    Text("\(store.time(block.start))–\(store.time(block.end)) · \(store.duration(block.end.timeIntervalSince(block.start) / 60))")
                    Text(store.categoryName(block.categoryID)).foregroundStyle(.secondary)
                }
                Section {
                    ForEach(block.samples) { sample in
                        NavigationLink {
                            ScrollView { CheckInEditor(entry: sample) { dismiss() }.padding(24) }
                                .navigationTitle("Edit sample").navigationBarTitleDisplayMode(.inline)
                        } label: {
                            VStack(alignment: .leading) {
                                Text(sample.activity)
                                Text(store.time(sample.end)).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: { Text("Supporting samples") } footer: {
                    Text("Tap a sample to change its activity, category, or time. The calendar is inferred from these observations.")
                }
            }.navigationTitle("Activity").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        }
    }
}
