import SwiftUI
import LedgerCore

struct GroupEntriesView: View {
    @EnvironmentObject var store: LedgerStore
    @Environment(\.dismiss) private var dismiss
    let day: Date
    let groupID: String
    let initialName: String
    let rangeStart: Date?
    let rangeEnd: Date?
    let management: Bool
    @State private var allDays: Bool
    @State private var creatingFor: CheckIn?
    @State private var showingNewGroup = false
    @State private var groupName = ""
    @State private var editing: CheckIn?
    @State private var error: String?
    @State private var renaming = false
    @State private var confirmingDeletion = false
    init(day: Date, groupID: String, initialName: String, rangeStart: Date? = nil, rangeEnd: Date? = nil, allTime: Bool = false, management: Bool = false) {
        self.day = day; self.groupID = groupID; self.initialName = initialName
        self.rangeStart = rangeStart; self.rangeEnd = rangeEnd
        self.management = management
        _allDays = State(initialValue: allTime || groupID == "uncategorized")
    }
    private var entries: [CheckIn] {
        let source: [CheckIn]
        if allDays { source = store.ledger.entries.sorted { $0.end > $1.end } }
        else if let rangeStart, let rangeEnd { source = store.ledger.entries.filter { $0.end >= rangeStart && $0.end <= rangeEnd }.sorted { $0.end > $1.end } }
        else { source = store.ledger.entries(on: day) }
        return source.filter {
            $0.end <= Date() && (groupID == "uncategorized" ? store.ledger.confirmedCategoryID(for: $0) == nil : store.ledger.confirmedCategoryID(for: $0) == groupID)
        }
    }
    var body: some View {
        NavigationStack {
            List {
                if management {
                    Section {
                        HStack { Text("All-time logs"); Spacer(); Text("\(entries.count)").foregroundStyle(.secondary) }
                            .accessibilityIdentifier("group.all-time-count")
                        Button("Rename group") {
                            groupName = store.categoryName(groupID); renaming = true
                        }.accessibilityIdentifier("group.rename")
                        Button("Delete group", role: .destructive) { confirmingDeletion = true }
                            .accessibilityIdentifier("group.delete")
                    } footer: { Text("Deleting this group moves its logs to Uncategorized. Your activity text and timestamps are kept.") }
                }
                if groupID == "uncategorized", !management {
                    Picker("Review", selection: $allDays) {
                        Text(rangeStart == nil ? "Selected day" : "Selected range").tag(false)
                        Text("All days").tag(true)
                    }.pickerStyle(.segmented)
                }
                if entries.isEmpty { Text("There are no logs in this group for this view.").foregroundStyle(.secondary) }
                ForEach(entries) { entry in
                    VStack(alignment: .leading, spacing: 10) {
                        Button { editing = entry } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(entry.activity).foregroundStyle(.primary)
                                Text(allDays || rangeStart != nil ? "\(entry.end.formatted(date: .abbreviated, time: .omitted)) · \(store.time(entry.end))" : store.time(entry.end))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }.buttonStyle(.plain)
                        Text("Group: \(store.categoryName(store.ledger.confirmedCategoryID(for: entry)))")
                            .font(.caption).foregroundStyle(.secondary)
                        suggestion(for: entry)
                        Menu {
                            ForEach(store.ledger.categories) { group in
                                Button(group.name) {
                                    do { try store.categorize(entry, categoryID: group.id) } catch { self.error = error.localizedDescription }
                                }
                            }
                            Divider()
                            Button("Create new group…", systemImage: "plus") { groupName = ""; creatingFor = entry; showingNewGroup = true }
                            if store.ledger.confirmedCategoryID(for: entry) != nil {
                                Button("Move to Uncategorized") {
                                    do { try store.categorize(entry, categoryID: nil) } catch { self.error = error.localizedDescription }
                                }
                            }
                        } label: {
                            Label(groupID == "uncategorized" ? "Choose group" : "Change group", systemImage: "folder")
                        }.accessibilityIdentifier("group.choose.\(entry.id)")
                    }.padding(.vertical, 5)
                }
                if store.canUndoGrouping {
                    Section { Button("Undo last categorization") { store.undoCategorization() }.accessibilityIdentifier("group.undo") }
                }
                if let error { Text(error).foregroundStyle(.red) }
                Section {
                    Text("Suggestions work offline and learn from confirmed choices. Every log stays Uncategorized until you confirm its group.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }.navigationTitle(store.ledger.categories.first { $0.id == groupID }?.name ?? initialName)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() }.accessibilityIdentifier("group.done") } }
                .alert("Rename group", isPresented: $renaming) {
                    TextField("Group name", text: $groupName)
                    Button("Save") {
                        do { try store.saveCategory(id: groupID, name: groupName); error = nil } catch { self.error = error.localizedDescription }
                    }
                    Button("Cancel", role: .cancel) {}
                }
                .confirmationDialog("Delete \(store.categoryName(groupID))?", isPresented: $confirmingDeletion, titleVisibility: .visible) {
                    Button("Delete group", role: .destructive) {
                        do { try store.deleteCategory(id: groupID); dismiss() } catch { self.error = error.localizedDescription }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: { Text("All \(entries.count) logs will be kept and moved to Uncategorized.") }
                .alert("New group", isPresented: $showingNewGroup, presenting: creatingFor) { entry in
                    TextField("Group name", text: $groupName)
                    Button("Create & categorize") {
                        do { try store.categorize(entry, categoryID: nil, newGroupName: groupName) } catch { self.error = error.localizedDescription }
                    }
                    Button("Cancel", role: .cancel) {}
                }
                .sheet(item: $editing) { entry in
                    NavigationStack {
                        ScrollView { CheckInEditor(entry: entry) { editing = nil }.padding(24) }
                            .navigationTitle("Edit sample")
                            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { editing = nil } } }
                    }
                }
        }
    }

    @ViewBuilder
    private func suggestion(for entry: CheckIn) -> some View {
        if let id = store.ledger.suggestedCategory(for: entry.activity) {
            let name = store.categoryName(id)
            let matches = store.ledger.unconfirmedMatches(for: entry.activity).count
            if store.ledger.confirmedCategoryID(for: entry) == id {
                Label("\(name) confirmed", systemImage: "checkmark.circle").font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Suggested: \(name)").font(.subheadline)
                Button("Use \(name)") {
                    do { try store.categorize(entry, categoryID: id); error = nil } catch { self.error = error.localizedDescription }
                }.buttonStyle(.bordered).accessibilityIdentifier("group.confirm.\(entry.id)")
                if matches > 1 && store.ledger.confirmedCategoryID(for: entry) == nil {
                    Button("Confirm \(name) for \(matches) matching logs") {
                        do { try store.categorize(entry, categoryID: id, includeMatching: true); error = nil } catch { self.error = error.localizedDescription }
                    }.font(.caption).buttonStyle(.borderless).accessibilityIdentifier("group.confirm-matching.\(entry.id)")
                }
            }
        } else {
            Text("No suggestion yet").font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct GroupManagerView: View {
    @EnvironmentObject var store: LedgerStore
    @Environment(\.dismiss) private var dismiss
    @State private var selected: LedgerCategory?
    @State private var showingEditor = false
    @State private var name = ""
    @State private var error: String?
    var body: some View {
        NavigationStack {
            List {
                Section {
                    let counts = store.ledger.groupEntryCounts()
                    ForEach(store.ledger.categories) { group in
                        Button { selected = group } label: {
                            HStack {
                                Text(group.name).foregroundStyle(.primary)
                                Text("\(counts[group.id, default: 0])").foregroundStyle(.secondary)
                                Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                            }
                        }.accessibilityIdentifier("groups.open.\(group.id)")
                    }
                    Button { selected = LedgerCategory(id: "uncategorized", name: "Uncategorized") } label: {
                        HStack { Text("Uncategorized"); Text("\(counts["uncategorized", default: 0])").foregroundStyle(.secondary); Spacer(); Image(systemName: "chevron.right").font(.caption) }
                    }.accessibilityIdentifier("groups.open.uncategorized")
                    Button("Create group", systemImage: "plus") { name = ""; showingEditor = true }
                } footer: { Text("Counts include all-time logs. Tap a group to see its logs, rename it, or delete it.") }
                if let error { Text(error).foregroundStyle(.red) }
            }.navigationTitle("Groups").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() }.accessibilityIdentifier("groups.done") } }
                .sheet(item: $selected) { group in
                    GroupEntriesView(day: Date(), groupID: group.id, initialName: group.name, allTime: true, management: group.id != "uncategorized")
                }
                .alert("New group", isPresented: $showingEditor) {
                    TextField("Group name", text: $name)
                    Button("Save") {
                        do { try store.saveCategory(id: nil, name: name); error = nil } catch { self.error = error.localizedDescription }
                    }
                    Button("Cancel", role: .cancel) {}
                }
        }
    }
}
