import SwiftUI
import LedgerCore

private struct SelectedGroup: Identifiable {
    var id: String
    var name: String
    var day = Date()
}

struct DayView: View {
    @EnvironmentObject var store: LedgerStore
    @State private var editing: CheckIn?
    @State private var selectedGroup: SelectedGroup?
    @State private var managingGroups = false
    @State private var saved = false
    @State private var visible = false
    private var entries: [CheckIn] { store.ledger.entries(on: Date()).filter { $0.end <= Date() } }
    private var uncategorizedCount: Int { entries.filter { store.ledger.confirmedCategoryID(for: $0) == nil }.count }
    private var totalUncategorizedCount: Int {
        store.ledger.entries.filter { $0.end <= Date() && store.ledger.confirmedCategoryID(for: $0) == nil }.count
    }

    var body: some View {
        ScrollViewReader { proxy in
            TimelineView(.periodic(from: Date(), by: 60)) { _ in
                content(now: Date())
            }
            .onAppear { visible = true; openRequestedLog(using: proxy) }
            .onDisappear { visible = false }
            .onChange(of: store.sampleRequestID) { _, _ in
                saved = false; editing = nil; selectedGroup = nil; managingGroups = false
                if visible { openRequestedLog(using: proxy) }
            }
        }.navigationTitle("Today").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    NavigationLink(value: LedgerScreen.calendar) { Label("Calendar", systemImage: "calendar") }
                        .accessibilityIdentifier("dashboard.calendar")
                    Button("Groups") { managingGroups = true }.accessibilityIdentifier("dashboard.groups")
                    Menu {
                        NavigationLink("Inbox", value: LedgerScreen.inbox)
                        NavigationLink("Settings", value: LedgerScreen.settings)
                    } label: { Label("More", systemImage: "ellipsis.circle") }
                        .accessibilityIdentifier("dashboard.more")
                }
            }
            .sheet(isPresented: $managingGroups) { GroupManagerView() }
            .sheet(item: $selectedGroup) { group in
                GroupEntriesView(day: group.day, groupID: group.id, initialName: group.name)
            }
            .sheet(item: $editing) { entry in
                NavigationStack {
                    ScrollView { CheckInEditor(entry: entry) { editing = nil }.padding(20) }
                        .navigationTitle("Edit log").navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { editing = nil } } }
                }
            }
    }

    private func openRequestedLog(using proxy: ScrollViewProxy) {
        guard store.pendingLogRequest else { return }
        DispatchQueue.main.async {
            withAnimation { proxy.scrollTo("today.logging", anchor: .top) }
            store.pendingLogRequest = false
        }
    }

    private func content(now: Date) -> some View {
        let rows = store.ledger.breakdown(on: now, now: now)
            .filter { $0.minutes > 0 || ($0.id == "uncategorized" && uncategorizedCount > 0) }
            .sorted { $0.minutes == $1.minutes ? $0.name < $1.name : $0.minutes > $1.minutes }
        let tracked = rows.reduce(0) { $0 + $1.minutes }
        return List {
            Section {
                if rows.isEmpty { Text("Log your first activity to start today’s breakdown.").foregroundStyle(.secondary) }
                ForEach(rows) { row in
                    Button { selectedGroup = SelectedGroup(id: row.id, name: row.name) } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(row.name).foregroundStyle(.primary)
                                Spacer()
                                Text("\(row.percent, specifier: "%.1f")% · \(store.duration(row.minutes))")
                                    .font(.subheadline).foregroundStyle(.secondary)
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                            }
                            ProgressView(value: min(1, row.percent / 100))
                        }.padding(.vertical, 3)
                    }.accessibilityIdentifier("dashboard.group.\(row.id)")
                }
                if totalUncategorizedCount > 0 {
                    Button { selectedGroup = SelectedGroup(id: "uncategorized", name: "Uncategorized") } label: {
                        Label("\(totalUncategorizedCount) logs to group", systemImage: "tray")
                    }.accessibilityIdentifier("dashboard.review.uncategorized")
                }
                if store.canUndoGrouping {
                    Button("Undo last categorization") { store.undoCategorization() }.accessibilityIdentifier("dashboard.undo")
                }
            } header: {
                Text("Where your time went").font(.headline).textCase(nil).accessibilityIdentifier("dashboard.breakdown-title")
            } footer: {
                if let first = entries.last {
                    Text("Since \(store.time(first.end)) · \(store.duration(tracked)) tracked · \(entries.count) logs")
                }
            }
            Section {
                CheckInEditor { saved = true }.id(store.sampleRequestID).id("today.logging")
                if saved {
                    Label("Saved. You can change it anytime.", systemImage: "checkmark.circle.fill").foregroundStyle(.tint)
                }
            } header: { Text("Log what I’m doing").font(.headline).textCase(nil) }
            Section {
                DisclosureGroup("Today’s logs (\(entries.count))") {
                    ForEach(entries) { entry in
                        Button { editing = entry } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(entry.activity).foregroundStyle(.primary)
                                Text("\(store.time(entry.end)) · \(store.categoryName(store.ledger.confirmedCategoryID(for: entry)))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }.accessibilityIdentifier("today.logs")
            }
        }.listStyle(.insetGrouped).listSectionSpacing(16)
            .scrollDismissesKeyboard(.interactively)
    }
}

struct CalendarHistoryView: View {
    @State private var day = Date()
    var body: some View {
        TimelineView(.periodic(from: Date(), by: 60)) { _ in
            let now = Date()
            VStack(spacing: 12) {
                DatePicker("Day", selection: $day, in: ...now, displayedComponents: [.date]).padding(.horizontal)
                DayCalendarView(day: day, now: now)
            }
        }.navigationTitle("Calendar").navigationBarTitleDisplayMode(.inline)
    }
}
