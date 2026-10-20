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
    var selectionHelp = "Select one or more. Estimated time is divided equally. A parent and its subcategory cannot both be selected."
    @State private var replacing: String?
    @State private var creating = false
    @State private var groupName = ""
    @State private var error: String?
    var body: some View {
        List {
            Button("Uncategorized") { selection = [] }
            ForEach(store.ledger.orderedCategories) { category in
                Button {
                    if selection.contains(category.id) { selection.removeAll { $0 == category.id } }
                    else if store.ledger.categoryConflicts(category.id, with: selection).isEmpty { selection.append(category.id) }
                    else { replacing = category.id }
                } label: {
                    HStack {
                        Text(store.ledger.categoryPath(category.id))
                        Spacer()
                        if selection.contains(category.id) { Image(systemName: "checkmark").foregroundStyle(.tint) }
                    }
                }.accessibilityIdentifier("category-select.\(category.id)")
                    .accessibilityValue(selection.contains(category.id) ? "Selected" : "Not selected")
                    .accessibilityAddTraits(selection.contains(category.id) ? .isSelected : [])
            }
            Button("Create new group…", systemImage: "plus") { groupName = ""; creating = true }
                .accessibilityIdentifier("category-select.create")
            if let error { Text(error).foregroundStyle(.red).accessibilityIdentifier("category-select.error") }
            Text(selectionHelp).font(.footnote).foregroundStyle(.secondary)
        }
            .safeAreaInset(edge: .top, spacing: 0) {
                if let activity, !activity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    CategoryEntryContext(activity: activity, timestamp: timestamp)
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
                        selection.append(id); error = nil
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
}

/// Separate from the scrolling checklist so the selected entry is never lost
/// when checking categories, resolving a conflict, or returning from creation.
private struct CategoryEntryContext: View {
    @EnvironmentObject private var store: LedgerStore
    let activity: String
    let timestamp: Date?
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
                    Text(activity).frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("category-context.activity")
                }
                #if os(watchOS)
                .frame(height: 80)
                #else
                .frame(height: 160)
                #endif
            } else {
                Text(activity).lineLimit(3).frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("category-context.activity")
            }
            if activity.count > 100 || activity.contains("\n") {
                Button(expanded ? "Show less" : "Read full entry") { expanded.toggle() }
                    .font(.caption).accessibilityIdentifier("category-context.expand")
            }
            Divider()
        }.padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 4)
            .frame(maxWidth: .infinity, alignment: .leading).background(.background)
    }
}
