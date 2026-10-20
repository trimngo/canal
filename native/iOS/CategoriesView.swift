import SwiftUI
import LedgerCore

struct CategoriesView: View {
    @EnvironmentObject private var store: LedgerStore
    @Environment(\.dismiss) private var dismiss
    @State var selecting = false
    @State private var selected = Set<String>()
    @State private var collapsed = Set<String>()
    @State private var editing: LedgerCategory?
    @State private var creating = false
    @State private var moving = false
    @State private var reviewingUncategorized = false
    @State private var error: String?

    private var visible: [LedgerCategory] {
        let parents = store.ledger.categoryParents
        return store.ledger.orderedCategories.filter { category in
            var node = category.id
            while let parent = parents[node] {
                if collapsed.contains(parent) { return false }; node = parent
            }
            return true
        }
    }
    private func depth(_ id: String) -> Int {
        var node = id, count = 0
        let parents = store.ledger.categoryParents
        while let parent = parents[node] { count += 1; node = parent }
        return count
    }
    var body: some View {
        List {
            Section {
                Text(selecting ? "Select categories, then group them under an existing or new parent." : "Use Select to group several categories at once. Tap a name to rename it or view its logs.")
                    .font(.subheadline).foregroundStyle(.secondary)
                ForEach(visible) { category in row(category) }
                Button("Create category", systemImage: "plus") { creating = true }.accessibilityIdentifier("categories.create")
                if !selecting {
                    Button("Uncategorized · \(store.ledger.groupEntryCounts()["uncategorized", default: 0]) logs") { reviewingUncategorized = true }
                        .accessibilityIdentifier("groups.open.uncategorized")
                }
            } footer: {
                Text("Each parent includes its subcategories’ time. Logs and idea labels keep their categories when you move them. Set life-area percentages in Commitments.")
            }
            CategoryMoveUndoSection()
            if let error { Text(error).foregroundStyle(.red) }
        }.listStyle(.insetGrouped).scrollDismissesKeyboard(.interactively)
            .navigationTitle("Categories").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() }.accessibilityIdentifier("groups.done") }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(selecting ? "Finish selecting" : "Select") { selecting.toggle(); selected = [] }.accessibilityIdentifier("categories.select-mode")
                }
            }
            .safeAreaInset(edge: .bottom) {
                if selecting {
                    Button { moving = true } label: {
                        Text(selected.isEmpty ? "Select categories to group" : "Group \(selected.count) selected…").frame(maxWidth: .infinity).padding(.vertical, 6)
                    }.buttonStyle(.borderedProminent).disabled(selected.isEmpty)
                        .padding().background(.bar).accessibilityIdentifier("categories.group-selected")
                }
            }
            .sheet(item: $editing) { CategoryEditView(category: $0) }
            .sheet(isPresented: $creating) { CategoryEditView(category: nil) }
            .sheet(isPresented: $moving) { CategoryMoveView(ids: selected.sorted()) { selected = [] } }
            .sheet(isPresented: $reviewingUncategorized) { GroupEntriesView(day: Date(), groupID: "uncategorized", initialName: "Uncategorized", allTime: true) }
            .onChange(of: store.ledger.categories.map(\.id)) { _, ids in selected.formIntersection(ids) }
    }
    private func row(_ category: LedgerCategory) -> some View {
        let children = store.ledger.children(of: category.id)
        return HStack(spacing: 8) {
            if selecting {
                Button {
                    if !selected.insert(category.id).inserted { selected.remove(category.id) }
                } label: {
                    HStack {
                        Image(systemName: selected.contains(category.id) ? "checkmark.circle.fill" : "circle")
                        Text(category.name).foregroundStyle(.primary)
                        Spacer()
                    }.contentShape(Rectangle())
                }.buttonStyle(.borderless).accessibilityIdentifier("categories.select.\(category.id)")
                    .accessibilityAddTraits(selected.contains(category.id) ? .isSelected : [])
            } else {
                Button { editing = category } label: {
                    HStack(spacing: 5) {
                        Text(category.name)
                        Text("\(store.ledger.groupEntryCounts()[category.id, default: 0])").font(.caption).foregroundStyle(.secondary)
                    }
                }.buttonStyle(.borderless).foregroundStyle(.primary).accessibilityIdentifier("groups.open.\(category.id)")
                Spacer()
            }
            if !children.isEmpty {
                Button { if !collapsed.insert(category.id).inserted { collapsed.remove(category.id) } } label: {
                    Image(systemName: collapsed.contains(category.id) ? "chevron.right" : "chevron.down").font(.caption)
                }.buttonStyle(.borderless).accessibilityLabel("Expand or collapse \(category.name)")
            }
        }.padding(.leading, CGFloat(min(depth(category.id), 6)) * 16)
            .contextMenu {
                Button("Edit category") { editing = category }
                Button("Move up") { reorder(category, direction: -1) }
                Button("Move down") { reorder(category, direction: 1) }
            }
    }
    private func reorder(_ category: LedgerCategory, direction: Int) {
        let parent = store.ledger.categoryParents[category.id]
        var ids = store.ledger.children(of: parent).map(\.id)
        guard let index = ids.firstIndex(of: category.id), ids.indices.contains(index + direction) else { return }
        ids.swapAt(index, index + direction)
        do { try store.reorderCategories(ids, parent: parent) } catch { self.error = error.localizedDescription }
    }
}

struct CategoryEditView: View {
    @EnvironmentObject var store: LedgerStore
    @Environment(\.dismiss) private var dismiss
    let category: LedgerCategory?
    @State private var name = ""
    @State private var parent = ""
    @State private var deleting = false
    @State private var viewingLogs = false
    @State private var moving = false
    @State private var error: String?
    private var possibleParents: [LedgerCategory] {
        let excluded = Set(category.map { [$0.id] + store.ledger.descendants(of: $0.id).map(\.id) } ?? [])
        return store.ledger.orderedCategories.filter { !excluded.contains($0.id) }
    }
    var body: some View {
        NavigationStack {
            Form {
                TextField("Category name", text: $name).accessibilityIdentifier("categories.name")
                if let category {
                    LabeledContent("Parent", value: store.ledger.categoryParents[category.id].map { store.ledger.categoryPath($0) } ?? "Top level")
                    Button("Move category…") { moving = true }.accessibilityIdentifier("categories.move-single")
                } else {
                    Picker("Parent", selection: $parent) {
                        Text("Top level").tag("")
                        ForEach(possibleParents) { Text(store.ledger.categoryPath($0.id)).tag($0.id) }
                    }.accessibilityIdentifier("categories.parent")
                }
                if let category {
                    Section {
                        Button("View all logs (\(store.ledger.groupEntryCounts()[category.id, default: 0]))") { viewingLogs = true }
                        Button("Delete category", role: .destructive) { deleting = true }.accessibilityIdentifier("group.delete")
                    } footer: {
                        Text("Logs and ideas are kept. Deleted category shares become Uncategorized, and the label is removed from ideas. Children move up one level. Moves preview goal changes before applying them. Earlier budget versions are retained.")
                    }
                }
                if let error { Text(error).foregroundStyle(.red) }
            }.scrollDismissesKeyboard(.interactively).ledgerInputDismissal()
                .navigationTitle(category == nil ? "New category" : "Edit category").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") {
                        do { try store.editCategory(id: category?.id, name: name, parent: category.flatMap { store.ledger.categoryParents[$0.id] } ?? (category == nil && !parent.isEmpty ? parent : nil)); dismiss() } catch { self.error = error.localizedDescription }
                    }.accessibilityIdentifier("categories.save").disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
                }
                .onAppear { name = category?.name ?? ""; parent = category.flatMap { store.ledger.categoryParents[$0.id] } ?? "" }
                .confirmationDialog("Delete \(category?.name ?? "category")?", isPresented: $deleting, titleVisibility: .visible) {
                    Button("Delete category", role: .destructive) {
                        do { if let category { try store.deleteCategory(id: category.id) }; dismiss() } catch { self.error = error.localizedDescription }
                    }
                } message: { Text("Logs and ideas will be kept. This category’s shares become Uncategorized, and its label is removed from ideas. Children are promoted, and its target is removed from the current budget.") }
                .sheet(isPresented: $moving) {
                    if let category { CategoryMoveView(ids: [category.id]) }
                }
                .sheet(isPresented: $viewingLogs) {
                    if let category { GroupEntriesView(day: Date(), groupID: category.id, initialName: category.name, allTime: true) }
                }
        }
    }
}
