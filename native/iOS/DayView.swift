import SwiftUI
import LedgerCore

struct DayView: View {
    @EnvironmentObject var store: LedgerStore
    @State private var day = Date()
    @State private var onlyUncategorized = false
    @State private var mode = 0
    @State private var editing: CheckIn?
    var entries: [CheckIn] {
        let known = Set(store.ledger.categories.map(\.id))
        return store.ledger.entries(on: day).filter { !onlyUncategorized || !known.contains($0.categoryID ?? "") }
    }
    var body: some View {
        TimelineView(.periodic(from: Date(), by: 60)) { context in
            VStack(spacing: 0) {
                VStack(spacing: 10) {
                    DatePicker("Day", selection: $day, in: ...context.date, displayedComponents: [.date])
                    Picker("View", selection: $mode) {
                        Text("Summary").tag(0)
                        Text("Calendar").tag(1)
                    }.pickerStyle(.segmented).accessibilityIdentifier("day.mode")
                }.padding(.horizontal).padding(.vertical, 12)
                if mode == 1 {
                    DayCalendarView(day: day, now: context.date)
                } else {
            List {
                Section {
                    ForEach(store.ledger.breakdown(on: day, now: context.date)) { row in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(row.name); Spacer()
                                Text("\(store.duration(row.minutes)) · \(row.percent, specifier: "%.1f")%")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                            ProgressView(value: min(1, row.percent / 100))
                        }.padding(.vertical, 4)
                    }
                } header: { Text("Estimated time") } footer: {
                    Text("\(store.ledger.settings.inferenceMethod.name). Time before the first sample is unestimated. Today’s estimates stop at now. Percentages use the whole day, normally 24 hours.")
                }
                Section {
                    Toggle("Only uncategorized", isOn: $onlyUncategorized)
                    if entries.isEmpty { Text("No samples here yet.").foregroundStyle(.secondary) }
                    ForEach(entries) { entry in
                        Button { editing = entry } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.activity).foregroundStyle(.primary)
                                Text("\(store.time(entry.end)) · \(store.categoryName(entry.categoryID))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: { Text("Your samples") } footer: {
                    Text("These are observations at specific moments. Change a sample or its category anytime; inferred totals update automatically.")
                }
            }
                }
            }
        }.navigationTitle("My day")
            .sheet(item: $editing) { entry in
                NavigationStack {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            CheckInEditor(entry: entry) { editing = nil }
                        }.padding(24)
                    }.navigationTitle("Edit sample").navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { editing = nil } } }
                }
            }
    }
}
