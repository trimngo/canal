import SwiftUI
import LedgerCore

private struct SelectedGroup: Identifiable {
    var id: String
    var name: String
}

struct DayView: View {
    @EnvironmentObject var store: LedgerStore
    @State private var day = Date()
    @State private var mode = 0
    @State private var editing: CheckIn?
    @State private var selectedGroup: SelectedGroup?
    @State private var managingGroups = false
    private var entries: [CheckIn] { store.ledger.entries(on: day).filter { $0.end <= Date() } }
    private var uncategorizedCount: Int {
        entries.filter { entry in !store.ledger.categories.contains { $0.id == entry.categoryID } }.count
    }

    var body: some View {
        TimelineView(.periodic(from: Date(), by: 60)) { _ in
            let now = Date()
            VStack(spacing: 0) {
                VStack(spacing: 10) {
                    DatePicker("Day", selection: $day, in: ...now, displayedComponents: [.date])
                    Picker("View", selection: $mode) {
                        Text("Summary").tag(0)
                        Text("Calendar").tag(1)
                    }.pickerStyle(.segmented).accessibilityIdentifier("day.mode")
                }.padding(.horizontal).padding(.vertical, 12)
                if mode == 1 {
                    DayCalendarView(day: day, now: now)
                } else {
                    summary(now: now)
                }
            }
        }.navigationTitle(Calendar.current.isDateInToday(day) ? "Today" : "My day")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Groups") { managingGroups = true }.accessibilityIdentifier("dashboard.groups")
                }
            }
            .sheet(isPresented: $managingGroups) { GroupManagerView() }
            .sheet(item: $selectedGroup) { group in
                GroupEntriesView(day: day, groupID: group.id, initialName: group.name)
            }
            .sheet(item: $editing) { entry in
                NavigationStack {
                    ScrollView { CheckInEditor(entry: entry) { editing = nil }.padding(24) }
                        .navigationTitle("Edit sample").navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { editing = nil } } }
                }
            }
    }

    private func summary(now: Date) -> some View {
        let segments = store.ledger.inferredSegments(on: day, now: now)
        let rows = store.ledger.breakdown(on: day, now: now)
            .filter { $0.minutes > 0 || ($0.id == "uncategorized" && uncategorizedCount > 0) }
            .sorted { $0.minutes == $1.minutes ? $0.name < $1.name : $0.minutes > $1.minutes }
        return List {
            Section {
                Button { store.beginSample() } label: {
                    Label("Log what I’m doing", systemImage: "plus.circle.fill").font(.headline)
                }.accessibilityIdentifier("dashboard.log")
                if let first = entries.last {
                    if Calendar.current.isDateInToday(day) {
                        Text("Since your first log at \(store.time(first.end))").font(.subheadline).foregroundStyle(.secondary)
                    } else {
                        Text("From \(store.time(first.end)) to \(store.time(entries.first?.end ?? first.end))")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    Text("\(store.duration(segments.reduce(0) { $0 + $1.minutes })) tracked · \(entries.count) samples")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Log your first activity to start today’s breakdown.").foregroundStyle(.secondary)
                }
            }
            Section {
                ForEach(rows) { row in
                    Button { selectedGroup = SelectedGroup(id: row.id, name: row.name) } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(row.name).foregroundStyle(.primary)
                                    if row.id == "uncategorized" {
                                        Text("\(uncategorizedCount) to group").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Text("\(row.percent, specifier: "%.1f")% · \(store.duration(row.minutes))")
                                    .font(.subheadline).foregroundStyle(.secondary)
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                            }
                            ProgressView(value: min(1, row.percent / 100))
                        }.padding(.vertical, 4)
                    }.accessibilityIdentifier("dashboard.group.\(row.id)")
                }
            } header: { Text("Where your time went") } footer: {
                Text("Estimated between logs using \(store.ledger.settings.inferenceMethod.name.lowercased()). Percentages cover tracked time only. Tap a group to review or change its entries.")
            }
            if store.canUndoGrouping {
                Section { Button("Undo last categorization") { store.undoCategorization() } }
            }
            Section {
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
                Text("Grouping works offline. Corrections are remembered for the same activity description. Your original log text is preserved.")
            }
        }
    }
}
