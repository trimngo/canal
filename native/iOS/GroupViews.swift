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
    let directOnly: Bool
    @State private var allDays: Bool
    @State private var categorizing: CheckIn?
    @State private var groupName = ""
    @State private var editing: CheckIn?
    @State private var error: String?
    @State private var renaming = false
    @State private var confirmingDeletion = false
    @State private var selecting = false
    @State private var selected = Set<String>()
    @State private var moving: LogMoveRequest?
    init(day: Date, groupID: String, initialName: String, rangeStart: Date? = nil, rangeEnd: Date? = nil, allTime: Bool = false, management: Bool = false, directOnly: Bool = false) {
        self.day = day; self.groupID = groupID; self.initialName = initialName
        self.rangeStart = rangeStart; self.rangeEnd = rangeEnd
        self.management = management
        self.directOnly = directOnly
        _allDays = State(initialValue: allTime || (groupID == "uncategorized" && rangeStart == nil))
    }
    private var entries: [CheckIn] {
        let source: [CheckIn]
        if allDays { source = store.ledger.activeEntries.sorted { $0.end > $1.end } }
        else if let rangeStart, let rangeEnd { source = store.ledger.activeEntries.filter { ($0.intervalStart ?? $0.end) <= rangeEnd && $0.end >= rangeStart }.sorted { $0.end > $1.end } }
        else { source = store.ledger.entries(on: day) }
        let categoryIDs = Set([groupID] + (directOnly ? [] : store.ledger.descendants(of: groupID).map(\.id)))
        return source.filter {
            $0.end <= Date() && (groupID == "uncategorized" ? (store.ledger.effectiveCategoryIDs(for: $0).isEmpty || store.ledger.allocationCategoryIDs(for: $0).contains("uncategorized")) : !Set(store.ledger.effectiveCategoryIDs(for: $0)).isDisjoint(with: categoryIDs))
        }
    }
    var body: some View {
        let entries = self.entries
        let name = store.ledger.categories.first { $0.id == groupID }?.name ?? initialName
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
                    } footer: { Text("Deleting this group keeps its logs and ideas. Its logged time becomes Uncategorized, and its label is removed from ideas.") }
                }
                if groupID == "uncategorized", !management {
                    Picker("Review", selection: $allDays) {
                        Text(rangeStart == nil ? "Selected day" : "Selected range").tag(false)
                        Text("All days").tag(true)
                    }.pickerStyle(.segmented)
                }
                if entries.isEmpty { Text("There are no logs in this group for this view.").foregroundStyle(.secondary) }
                ForEach(entries) { entry in entryRow(entry) }
                if store.canUndoGrouping {
                    Section { Button("Undo last categorization") { store.undoCategorization() }.accessibilityIdentifier("group.undo") }
                }
                if let error { Text(error).foregroundStyle(.red) }
                Section {
                    Text("Suggestions work offline and learn from confirmed choices. Confident suggestions count toward totals and stay marked for review until you confirm or correct them.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }.ledgerInputDismissal().safeAreaInset(edge: .bottom, spacing: 0) {
                if selecting {
                    Button("Move \(selected.count) logs to category") { moving = LogMoveRequest(ids: selected) }
                        .buttonStyle(.borderedProminent).disabled(selected.isEmpty || !store.storageAvailable)
                        .padding().frame(maxWidth: .infinity).background(.bar).accessibilityIdentifier("group.move-logs")
                } else { LogDeletionUndoBar() }
            }
                .navigationTitle(directOnly ? "\(name) (direct)" : name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() }.accessibilityIdentifier("group.done") }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(selecting ? "Cancel selection" : "Select") { selecting.toggle(); selected = [] }
                            .accessibilityIdentifier("group.select")
                    }
                }
                .onChange(of: entries.map(\.id)) { _, ids in selected.formIntersection(ids) }
                .sheet(item: $moving) { request in
                    LogCategoryMoveView(ids: request.ids, source: groupID) { selecting = false; selected = [] }
                }
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
                } message: { Text("Logs and ideas are kept. This category’s shares become Uncategorized, its label is removed from ideas, and children are promoted.") }
                .sheet(item: $categorizing) { entry in
                    GroupAssignmentView(entry: entry, selection: store.ledger.effectiveCategoryIDs(for: entry))
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

    private func entryRow(_ entry: CheckIn) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    InlineEntryText(text: entry.activity, identifier: "group.text.\(entry.id)", maxLength: 500) {
                        try store.updateLogActivity(id: entry.id, activity: $0)
                    }.disabled(selecting)
                    Button { editing = entry } label: {
                        Text(allDays || rangeStart != nil ? "\(store.dayLabel(entry.end)) · \(store.time(entry.end))" : store.time(entry.end))
                            .font(.caption).foregroundStyle(.secondary)
                    }.buttonStyle(.borderless).accessibilityLabel("Edit time and details")
                }.frame(maxWidth: .infinity, alignment: .leading)
                if !selecting { DeleteLogButton(entry: entry, identifierPrefix: "group.delete-log") }
            }
            Text("Group: \(store.categoryNames(for: entry))")
                .font(.caption).foregroundStyle(.secondary)
            if let mood = entry.mood { Text("Mood: \(mood)/5").font(.caption).foregroundStyle(.secondary) }
            if !selecting {
                suggestion(for: entry)
                Button { categorizing = entry } label: {
                    Label(groupID == "uncategorized" ? "Choose group" : "Change group", systemImage: "folder")
                }.buttonStyle(.borderless).accessibilityIdentifier("group.choose.\(entry.id)")
            }
        }.padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            .onTapGesture { if selecting { toggleSelected(entry.id) } }
            .listRowBackground(SelectionRowBackground(selected: selected.contains(entry.id)))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("group.log.\(entry.id)")
            .accessibilityValue(selected.contains(entry.id) ? "Selected" : "Not selected")
            .swipeActions {
                if !selecting {
                    Button("Delete", role: .destructive) {
                        do { try store.deleteLog(entry) } catch { self.error = error.localizedDescription }
                    }
                }
            }
    }

    private func toggleSelected(_ id: String) { if !selected.insert(id).inserted { selected.remove(id) } }

    @ViewBuilder
    private func suggestion(for entry: CheckIn) -> some View {
        if let suggestion = entry.categorySuggestion {
            Text("Suggested · \(suggestion.reason)").font(.caption).foregroundStyle(.secondary)
            Button("Confirm categories") {
                do { try store.categorize(entry, categoryIDs: store.ledger.effectiveCategoryIDs(for: entry)); error = nil } catch { self.error = error.localizedDescription }
            }.buttonStyle(.bordered).accessibilityIdentifier("group.confirm.\(entry.id)")
        } else if let id = store.ledger.suggestedCategory(for: entry.activity) {
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
    var selecting = false
    var body: some View { NavigationStack { CategoriesView(selecting: selecting) } }
}


struct GroupAssignmentView: View {
    @EnvironmentObject private var store: LedgerStore
    @Environment(\.dismiss) private var dismiss
    let entry: CheckIn
    @State var selection: [String]
    @State private var mood: Int?
    @State private var goalID: String?
    @State private var error: String?
    @State private var loaded = false
    private var currentEntry: CheckIn { store.ledger.activeEntries.first { $0.id == entry.id } ?? entry }
    var body: some View {
        NavigationStack {
            CategorySelectionList(selection: $selection, activity: currentEntry.activity, timestamp: entry.end, mood: $mood,
                                  saveActivity: { try store.updateLogActivity(id: entry.id, activity: $0) })
                .safeAreaInset(edge: .top, spacing: 0) { LogTaskPicker(goalID: $goalID, categoryIDs: $selection).padding(.horizontal) }
                .navigationTitle("Choose groups").navigationBarTitleDisplayMode(.inline)
                .safeAreaInset(edge: .bottom) {
                    if let error { Text(error).font(.footnote).foregroundStyle(.red).padding().background(.regularMaterial) }
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            do { UIApplication.shared.dismissLedgerKeyboard(); try store.reviewLog(entry, categoryIDs: selection, mood: mood, goalID: goalID); dismiss() }
                            catch { self.error = error.localizedDescription }
                        }.accessibilityIdentifier("group-selection.done")
                    }
                }
        }
            .onAppear { if !loaded { mood = entry.mood; goalID = entry.goalID; loaded = true } }
    }
}

private struct LogMoveRequest: Identifiable {
    let id = UUID()
    let ids: Set<String>
}

private struct LogCategoryMoveView: View {
    @EnvironmentObject private var store: LedgerStore
    @Environment(\.dismiss) private var dismiss
    let ids: Set<String>
    let source: String
    let didMove: () -> Void
    @State private var error: String?
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Move \(ids.count) logs from \(store.categoryName(source)). Other labels are kept.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Section("Choose an existing category") {
                    ForEach(store.ledger.orderedCategories) { category in
                        Button(store.ledger.categoryPath(category.id)) {
                            do { try store.moveLogs(ids, from: source, to: category.id); didMove(); dismiss() }
                            catch { self.error = error.localizedDescription }
                        }.accessibilityIdentifier("log-move.\(category.id)")
                    }
                }
                if let error { Text(error).foregroundStyle(.red).accessibilityIdentifier("log-move.error") }
            }.navigationTitle("Move logs").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}
