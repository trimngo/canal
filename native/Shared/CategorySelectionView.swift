import SwiftUI
import LedgerCore

/// Shared phone/Watch selector. A conflicting selection is replaced only after
/// the user explicitly confirms; the core validates the same rule on save.
struct CategorySelectionPicker: View {
    @EnvironmentObject var store: LedgerStore
    @Binding var selection: [String]
    var activity: String? = nil
    var timestamp: Date? = nil
    @State private var showing = false
    private var title: String {
        selection.isEmpty ? "Uncategorized" : selection.map { store.ledger.categoryPath($0) }.joined(separator: " + ")
    }
    var body: some View {
        Button { showing = true } label: {
            HStack { Text("Categories"); Spacer(); Text(title).foregroundStyle(.secondary).multilineTextAlignment(.trailing) }
        }.sheet(isPresented: $showing) {
            NavigationStack {
                CategorySelectionList(selection: $selection, activity: activity, timestamp: timestamp)
                    .navigationTitle("Choose groups")
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showing = false } } }
            }
        }
    }
}


/// Keeps the picker open while checking groups or creating another one.
struct CategorySelectionList: View {
    @EnvironmentObject private var store: LedgerStore
    @Binding var selection: [String]
    var activity: String? = nil
    var timestamp: Date? = nil
    var mood: Binding<Int?>? = nil
    var editActivity: (() -> Void)? = nil
    var selectionHelp = "Select one or more. Estimated time is divided equally. A parent and its subcategory cannot both be selected."
    @State private var query = ""
    #if os(iOS)
    @FocusState private var searchFocused: Bool
    #endif
    @State private var replacing: String?
    @State private var creating = false
    @State private var groupName = ""
    @State private var error: String?
    var body: some View {
        List {
            if let mood {
                Section("Mood (optional)") { MoodSelectionView(selection: mood) }
            }
            Button("Uncategorized") { selection = []; dismissSearchKeyboard() }
            if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, store.ledger.searchCategories(query).isEmpty {
                Text("No matching categories").foregroundStyle(.secondary).accessibilityIdentifier("category-search.empty")
            }
            ForEach(store.ledger.searchCategories(query)) { category in
                Button {
                    dismissSearchKeyboard()
                    if selection.contains(category.id) { selection.removeAll { $0 == category.id } }
                    else if store.ledger.categoryConflicts(category.id, with: selection).isEmpty { selection.append(category.id) }
                    else { replacing = category.id }
                } label: {
                    HStack {
                        #if os(watchOS)
                        Text(store.ledger.categoryPath(category.id))
                        #else
                        Text(category.name).fontWeight(store.ledger.children(of: category.id).isEmpty ? .regular : .semibold)
                        #endif
                        Spacer()
                        if selection.contains(category.id) { Image(systemName: "checkmark").foregroundStyle(.tint) }
                    }
                    #if os(iOS)
                    .padding(.leading, CGFloat(depth(of: category.id)) * 18)
                    #endif
                }.accessibilityIdentifier("category-select.\(category.id)")
                    .accessibilityLabel(store.ledger.categoryPath(category.id))
                    .accessibilityValue(selection.contains(category.id) ? "Selected" : "Not selected")
                    .accessibilityAddTraits(selection.contains(category.id) ? .isSelected : [])
            }
            Button("Create new group…", systemImage: "plus") {
                dismissSearchKeyboard(); groupName = query.trimmingCharacters(in: .whitespacesAndNewlines); creating = true
            }
                .accessibilityIdentifier("category-select.create")
            if let error { Text(error).foregroundStyle(.red).accessibilityIdentifier("category-select.error") }
            Text(selectionHelp).font(.footnote).foregroundStyle(.secondary)
        }
            #if os(iOS)
            .scrollDismissesKeyboard(.interactively)
            #endif
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 0) {
                    if let activity, !activity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        CategoryEntryContext(activity: activity, timestamp: timestamp, editActivity: editEntry)
                    }
                    #if os(iOS)
                    categorySearch
                    #endif
                }
            }
            .alert("New group", isPresented: $creating) {
                TextField("Group name", text: $groupName)
                Button("Create") {
                    // Close before publishing the new category so a rebuilt
                    // presenting view cannot present this alert again.
                    creating = false
                    do {
                        let id = try store.saveCategory(id: nil, name: groupName)
                        selection.append(id); query = ""; error = nil
                    } catch { self.error = error.localizedDescription }
                }.disabled(groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Cancel", role: .cancel) { }
            }
            .alert("Replace conflicting categories?", isPresented: Binding(get: { replacing != nil }, set: { if !$0 { replacing = nil } })) {
                Button("Replace") {
                    if let id = replacing {
                        let conflicts = Set(store.ledger.categoryConflicts(id, with: selection))
                        selection.removeAll { conflicts.contains($0) }; selection.append(id)
                    }
                    replacing = nil
                }
                Button("Cancel", role: .cancel) { replacing = nil }
            } message: {
                if let id = replacing {
                    Text("Selecting \(store.ledger.categoryPath(id)) replaces \(store.ledger.categoryConflicts(id, with: selection).map { store.categoryName($0) }.joined(separator: ", ")). Other selections are kept.")
                }
            }
    }
    private var editEntry: (() -> Void)? {
        guard let editActivity else { return nil }
        return { dismissSearchKeyboard(); editActivity() }
    }
    private func dismissSearchKeyboard() {
        #if os(iOS)
        searchFocused = false
        #endif
    }
    #if os(iOS)
    private var categorySearch: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
            TextField("Search categories", text: $query).focused($searchFocused)
                .textInputAutocapitalization(.never).autocorrectionDisabled().submitLabel(.search)
                .onSubmit { searchFocused = false }.accessibilityIdentifier("category-search.field")
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .buttonStyle(.plain).accessibilityLabel("Clear category search").accessibilityIdentifier("category-search.clear")
            }
        }.padding(10).background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 16).padding(.vertical, 8).background(.background)
    }
    #endif
    private func depth(of id: String) -> Int {
        let parents = store.ledger.categoryParents
        var depth = 0, current = id
        while let parent = parents[current] { depth += 1; current = parent }
        return depth
    }
}

/// Phone post-processing only; capture and Apple's Watch dictation stay intact.
struct MoodSelectionView: View {
    @Binding var selection: Int?
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                ForEach(1...5, id: \.self) { value in
                    Button { selection = value } label: {
                        Text("\(value)").font(.headline).frame(maxWidth: .infinity, minHeight: 44)
                            .background(selection == value ? Color.accentColor.opacity(0.25) : Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    }.buttonStyle(.borderless)
                        .accessibilityLabel("Mood \(value) of 5")
                        .accessibilityValue(selection == value ? "Selected" : "Not selected")
                        .accessibilityIdentifier("mood.\(value)")
                }
            }
            HStack {
                Text("1 Low · 5 High").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if selection != nil {
                    Button("Clear") { selection = nil }.font(.caption).buttonStyle(.borderless).accessibilityIdentifier("mood.clear")
                }
            }
        }
    }
}

/// Separate from the scrolling checklist so the selected entry is never lost
/// when checking categories, resolving a conflict, or returning from creation.
private struct CategoryEntryContext: View {
    @EnvironmentObject private var store: LedgerStore
    let activity: String
    let timestamp: Date?
    var editActivity: (() -> Void)? = nil
    @State private var expanded = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let timestamp {
                Text("\(store.dayLabel(timestamp)) · \(store.time(timestamp))")
                    .font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("category-context.timestamp")
            }
            if expanded {
                ScrollView {
                    activityText
                }
                #if os(watchOS)
                .frame(height: 80)
                #else
                .frame(height: 160)
                #endif
            } else {
                activityText.lineLimit(3)
            }
            if activity.count > 100 || activity.contains("\n") {
                Button(expanded ? "Show less" : "Read full entry") { expanded.toggle() }
                    .font(.caption).accessibilityIdentifier("category-context.expand")
            }
            Divider()
        }.padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 4)
            .frame(maxWidth: .infinity, alignment: .leading).background(.background)
    }
    private var activityLabel: some View {
        Text(activity).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            .accessibilityIdentifier("category-context.activity")
    }
    @ViewBuilder private var activityText: some View {
        if let editActivity {
            activityLabel.onTapGesture(perform: editActivity)
                .accessibilityAddTraits(.isButton).accessibilityHint("Edit log text")
                .accessibilityAction { editActivity() }
        } else { activityLabel }
    }
}
