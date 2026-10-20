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
    @State private var categorizing: CheckIn?
    @State private var groupName = ""
    @State private var editing: CheckIn?
    @State private var error: String?
    @State private var renaming = false
    @State private var confirmingDeletion = false
    init(day: Date, groupID: String, initialName: String, rangeStart: Date? = nil, rangeEnd: Date? = nil, allTime: Bool = false, management: Bool = false) {
        self.day = day; self.groupID = groupID; self.initialName = initialName
        self.rangeStart = rangeStart; self.rangeEnd = rangeEnd
        self.management = management
        _allDays = State(initialValue: allTime || (groupID == "uncategorized" && rangeStart == nil))
    }
    private var entries: [CheckIn] {
        let source: [CheckIn]
        if allDays { source = store.ledger.activeEntries.sorted { $0.end > $1.end } }
        else if let rangeStart, let rangeEnd { source = store.ledger.activeEntries.filter { $0.end >= rangeStart && $0.end <= rangeEnd }.sorted { $0.end > $1.end } }
        else { source = store.ledger.entries(on: day) }
        return source.filter {
            $0.end <= Date() && (groupID == "uncategorized" ? (store.ledger.confirmedCategoryID(for: $0) == nil || store.ledger.allocationCategoryIDs(for: $0).contains("uncategorized")) : !Set(store.ledger.confirmedCategoryIDs(for: $0)).isDisjoint(with: Set([groupID] + store.ledger.descendants(of: groupID).map(\.id))))
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
                                Text(allDays || rangeStart != nil ? "\(store.dayLabel(entry.end)) · \(store.time(entry.end))" : store.time(entry.end))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }.buttonStyle(.plain)
                        Text("Group: \(store.categoryNames(for: entry))")
                            .font(.caption).foregroundStyle(.secondary)
                        suggestion(for: entry)
                        Button { categorizing = entry } label: {
                            Label(groupID == "uncategorized" ? "Choose group" : "Change group", systemImage: "folder")
                        }.accessibilityIdentifier("group.choose.\(entry.id)")
                    }.padding(.vertical, 5)
                        .swipeActions {
                            Button("Delete", role: .destructive) {
                                do { try store.deleteLog(entry) } catch { self.error = error.localizedDescription }
                            }
                        }
                }
                if store.canUndoGrouping {
                    Section { Button("Undo last categorization") { store.undoCategorization() }.accessibilityIdentifier("group.undo") }
                }
                if let error { Text(error).foregroundStyle(.red) }
                Section {
                    Text("Suggestions work offline and learn from confirmed choices. Every log stays Uncategorized until you confirm its group.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }.safeAreaInset(edge: .bottom, spacing: 0) { LogDeletionUndoBar() }
                .navigationTitle(store.ledger.categories.first { $0.id == groupID }?.name ?? initialName)
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
                } message: { Text("Logs are kept. This category’s shares become Uncategorized; children are promoted.") }
                .sheet(item: $categorizing) { entry in
                    GroupAssignmentView(entry: entry, selection: store.ledger.confirmedCategoryIDs(for: entry))
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
    var body: some View { NavigationStack { CategoriesView() } }
}


private struct GroupAssignmentView: View {
    @EnvironmentObject private var store: LedgerStore
    @Environment(\.dismiss) private var dismiss
    let entry: CheckIn
    @State var selection: [String]
    @State private var error: String?
    var body: some View {
        NavigationStack {
            CategorySelectionList(selection: $selection, activity: entry.activity, timestamp: entry.end)
                .navigationTitle("Choose groups").navigationBarTitleDisplayMode(.inline)
                .safeAreaInset(edge: .bottom) {
                    if let error { Text(error).font(.footnote).foregroundStyle(.red).padding().background(.regularMaterial) }
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            do { try store.categorize(entry, categoryIDs: selection); dismiss() }
                            catch { self.error = error.localizedDescription }
                        }.accessibilityIdentifier("group-selection.done")
                    }
                }
        }
    }
}
