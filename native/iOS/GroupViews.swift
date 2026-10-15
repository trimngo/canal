import SwiftUI
import LedgerCore

struct GroupEntriesView: View {
    @EnvironmentObject var store: LedgerStore
    @Environment(\.dismiss) private var dismiss
    let day: Date
    let groupID: String
    let initialName: String
    @State private var allDays: Bool
    @State private var creatingFor: CheckIn?
    @State private var showingNewGroup = false
    @State private var groupName = ""
    @State private var editing: CheckIn?
    @State private var error: String?
    init(day: Date, groupID: String, initialName: String) {
        self.day = day; self.groupID = groupID; self.initialName = initialName
        _allDays = State(initialValue: groupID == "uncategorized")
    }
    private var entries: [CheckIn] {
        let source = allDays ? store.ledger.entries.sorted { $0.end > $1.end } : store.ledger.entries(on: day)
        return source.filter {
            $0.end <= Date() && (groupID == "uncategorized" ? store.ledger.confirmedCategoryID(for: $0) == nil : store.ledger.confirmedCategoryID(for: $0) == groupID)
        }
    }
    var body: some View {
        NavigationStack {
            List {
                if groupID == "uncategorized" {
                    Picker("Review", selection: $allDays) {
                        Text("Selected day").tag(false)
                        Text("All days").tag(true)
                    }.pickerStyle(.segmented)
                }
                if entries.isEmpty { Text("All sorted. There are no entries in this view.").foregroundStyle(.secondary) }
                ForEach(entries) { entry in
                    VStack(alignment: .leading, spacing: 10) {
                        Button { editing = entry } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(entry.activity).foregroundStyle(.primary)
                                Text(allDays ? "\(entry.end.formatted(date: .abbreviated, time: .omitted)) · \(store.time(entry.end))" : store.time(entry.end))
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
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
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
    @State private var editing: LedgerCategory?
    @State private var showingEditor = false
    @State private var name = ""
    @State private var error: String?
    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(store.ledger.categories) { group in
                        Button { name = group.name; editing = group; showingEditor = true } label: {
                            HStack { Text(group.name); Spacer(); Image(systemName: "pencil").foregroundStyle(.secondary) }
                        }.accessibilityIdentifier("groups.rename.\(group.id)")
                    }
                    Button("Create group", systemImage: "plus") { name = ""; editing = LedgerCategory(id: "", name: ""); showingEditor = true }
                } footer: { Text("Tap a group to rename it everywhere. Log text and confirmed choices stay intact. Offline suggestions keep working after a rename.") }
                if let error { Text(error).foregroundStyle(.red) }
            }.navigationTitle("Groups").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
                .alert(editing?.id == "" ? "New group" : "Rename group", isPresented: $showingEditor, presenting: editing) { group in
                    TextField("Group name", text: $name)
                    Button("Save") {
                        do { try store.saveCategory(id: group.id == "" ? nil : group.id, name: name) } catch { self.error = error.localizedDescription }
                    }
                    Button("Cancel", role: .cancel) {}
                }
        }
    }
}
