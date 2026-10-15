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
        let known = Set(store.ledger.categories.map(\.id))
        let source = allDays ? store.ledger.entries.sorted { $0.end > $1.end } : store.ledger.entries(on: day)
        return source.filter {
            $0.end <= Date() && (groupID == "uncategorized" ? !known.contains($0.categoryID ?? "") : $0.categoryID == groupID)
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
                        Menu {
                            ForEach(store.ledger.categories) { group in
                                Button(group.name) {
                                    do { try store.categorize(entry, categoryID: group.id) } catch { self.error = error.localizedDescription }
                                }
                            }
                            Divider()
                            Button("Create new group…", systemImage: "plus") { groupName = ""; creatingFor = entry; showingNewGroup = true }
                            if entry.categoryID != nil {
                                Button("Use automatic grouping") {
                                    do { try store.categorize(entry, categoryID: nil) } catch { self.error = error.localizedDescription }
                                }
                            }
                        } label: {
                            Label(groupID == "uncategorized" ? "Choose group" : "Change group", systemImage: "folder")
                        }.accessibilityIdentifier("group.choose.\(entry.id)")
                    }.padding(.vertical, 5)
                }
                if store.canUndoGrouping {
                    Section { Button("Undo last categorization") { store.undoCategorization() } }
                }
                if let error { Text(error).foregroundStyle(.red) }
                Section {
                    Text("Choosing a group teaches the app to recognize this description next time. Matching automatic entries update too; entries you’ve grouped manually keep your choices.")
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
                } footer: { Text("Tap a group to rename it everywhere. Log text and assignments stay intact. Offline grouping keeps working after a rename.") }
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
