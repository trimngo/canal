import SwiftUI
import UIKit
import LedgerCore

private func percentageText(_ value: Double) -> String {
    value.formatted(.number.precision(.fractionLength(0...2)))
}

struct CategoriesView: View {
    @EnvironmentObject var store: LedgerStore
    @Environment(\.dismiss) private var dismiss
    @State private var drafts: [String: String] = [:]
    @State private var original: [String: String] = [:]
    @State private var originalValues: [String: Double] = [:]
    @State private var loaded = false
    @FocusState private var focusedTarget: String?
    @State private var collapsed = Set<String>()
    @State private var editing: LedgerCategory?
    @State private var creating = false
    @State private var reviewingUncategorized = false
    @State private var discard = false
    @State private var error: String?
    private var top: [LedgerCategory] { store.ledger.children(of: nil) }
    private var dirty: Bool { drafts != original }
    private var values: [String: Double]? {
        var result: [String: Double] = [:]
        for category in top {
            let text = (drafts[category.id] ?? "").trimmingCharacters(in: .whitespaces)
            if text.isEmpty { continue }
            if drafts[category.id] == original[category.id], let unchanged = originalValues[category.id] { result[category.id] = unchanged; continue }
            guard text.range(of: "^(?:[0-9]+(?:[.,][0-9]*)?|[.,][0-9]+)$", options: .regularExpression) != nil,
                  let value = Double(text.replacingOccurrences(of: ",", with: ".")), value.isFinite else { return nil }
            result[category.id] = value
        }
        return result
    }
    private var total: Double { values?.values.reduce(0, +) ?? 0 }
    private var valid: Bool { guard let values else { return false }; return (try? Ledger.validateTargets(values)) != nil }
    private var visible: [LedgerCategory] {
        let parents = store.ledger.categoryParents
        return store.ledger.orderedCategories.filter { category in
            var node = category.id
            while let parent = parents[node] { if collapsed.contains(parent) { return false }; node = parent }
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
                ForEach(visible) { category in categoryRow(category) }
                Button("Create category", systemImage: "plus") { creating = true }
                    .accessibilityIdentifier("categories.create")
                Button("Uncategorized · \(store.ledger.groupEntryCounts()["uncategorized", default: 0]) logs") { reviewingUncategorized = true }
                    .accessibilityIdentifier("groups.open.uncategorized")
            } header: { Text("Categories & long-term targets") } footer: {
                Text("Only top-level categories have targets. Subcategory time rolls up to its parent. A log can also be assigned directly to a parent. Tap a name to edit or move it; use its menu to reorder siblings.")
            }
            Section {
                HStack { Text("Allocated"); Spacer(); Text("\(percentageText(total))%").bold() }
                HStack {
                    Text(total > 100 ? "Over-allocated" : "Unallocated target")
                    Spacer(); Text("\(percentageText(abs(100 - total)))%")
                }.foregroundStyle(total > 100 ? Color.red : Color.secondary)
                if !valid { Text("Enter valid percentages totaling at most 100%. Your entries will stay here while you correct them.").foregroundStyle(.red).font(.footnote) }
                Button("Save targets") {
                    do {
                        if let values { try store.saveTargets(values); original = drafts; originalValues = values; error = nil }
                    } catch { self.error = error.localizedDescription }
                }.disabled(!valid || !dirty).accessibilityIdentifier("categories.save-targets")
                if let budget = store.ledger.currentBudget() {
                    Text("Current targets since \(budget.effectiveAt.formatted(date: .abbreviated, time: .shortened)). Earlier versions are preserved.").font(.caption).foregroundStyle(.secondary)
                }
            } footer: {
                Text("Unallocated is the part of your waking time without a target, not an activity. Changing one percentage leaves all other targets unchanged. Daily equivalents use your typical waking schedule.")
            }
            Section { NavigationLink("Waking schedule") { WakingScheduleView() } }
            if let error { Text(error).foregroundStyle(.red) }
        }
        .scrollDismissesKeyboard(.interactively).ledgerInputDismissal()
        .navigationTitle("Categories").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { if dirty { discard = true } else { dismiss() } }.accessibilityIdentifier("groups.done") } }
        .interactiveDismissDisabled(dirty)
        .confirmationDialog("Discard unsaved target changes?", isPresented: $discard, titleVisibility: .visible) {
            Button("Discard changes", role: .destructive) { dismiss() }
            Button("Keep editing", role: .cancel) {}
        }
        .sheet(item: $editing) { CategoryEditView(category: $0) }
        .sheet(isPresented: $creating) { CategoryEditView(category: nil) }
        .sheet(isPresented: $reviewingUncategorized) { GroupEntriesView(day: Date(), groupID: "uncategorized", initialName: "Uncategorized", allTime: true) }
                .onChange(of: focusedTarget) { _, id in
            guard id != nil else { return }
            DispatchQueue.main.async {
                UIApplication.shared.sendAction(#selector(UIResponderStandardEditActions.selectAll(_:)), to: nil, from: nil, for: nil)
            }
        }
        .onAppear { if !loaded { loadTargets(); loaded = true } }
        .onChange(of: store.ledger.currentBudget()?.id) { _, _ in if !dirty { loadTargets() } }
        .onChange(of: top.map(\.id)) { _, _ in
            let ids = Set(top.map(\.id))
            drafts = drafts.filter { ids.contains($0.key) }; original = original.filter { ids.contains($0.key) }; originalValues = originalValues.filter { ids.contains($0.key) }
            let current = store.ledger.currentTargets()
            for id in ids where drafts[id] == nil {
                let text = current[id].map(percentageText) ?? ""
                drafts[id] = text; original[id] = text; originalValues[id] = current[id]
            }
        }
    }
    private func loadTargets() {
        let current = store.ledger.currentTargets(); originalValues = current
        drafts = Dictionary(uniqueKeysWithValues: top.map { ($0.id, current[$0.id].map(percentageText) ?? "") }); original = drafts
    }
    private func categoryRow(_ category: LedgerCategory) -> some View {
        let isTop = store.ledger.categoryParents[category.id] == nil
        let hasChildren = !store.ledger.children(of: category.id).isEmpty
        let counts = store.ledger.groupEntryCounts()
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if hasChildren {
                    Button { if !collapsed.insert(category.id).inserted { collapsed.remove(category.id) } } label: {
                        Image(systemName: collapsed.contains(category.id) ? "chevron.right" : "chevron.down").font(.caption)
                    }.buttonStyle(.borderless).accessibilityLabel("Expand or collapse \(category.name)")
                }
                Button { editing = category } label: {
                    HStack(spacing: 4) { Text(category.name); Text("\(counts[category.id, default: 0])").font(.caption).foregroundStyle(.secondary) }
                }.buttonStyle(.borderless).foregroundStyle(.primary).accessibilityIdentifier("groups.open.\(category.id)")
                Spacer(minLength: 2)
                if isTop {
                    TextField("—", text: Binding(get: { drafts[category.id] ?? "" }, set: { drafts[category.id] = $0 }))
                        .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 64)
                        .focused($focusedTarget, equals: category.id)
                        .accessibilityLabel("\(category.name) target percent").accessibilityIdentifier("categories.target.\(category.id)")
                    Text("%").foregroundStyle(.secondary)
                }
            }
            if isTop, let percent = values?[category.id], (0...100).contains(percent) {
                Text("≈ \(store.duration(store.ledger.typicalWakingMinutes * percent / 100)) per waking day")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.padding(.leading, CGFloat(min(depth(category.id), 6)) * 14)
            .contextMenu {
                Button("Move up") { reorder(category, direction: -1) }
                Button("Move down") { reorder(category, direction: 1) }
                Button("Edit category") { editing = category }
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
    @State private var error: String?
    private var possibleParents: [LedgerCategory] {
        let excluded = Set(category.map { [$0.id] + store.ledger.descendants(of: $0.id).map(\.id) } ?? [])
        return store.ledger.orderedCategories.filter { !excluded.contains($0.id) }
    }
    var body: some View {
        NavigationStack {
            Form {
                TextField("Category name", text: $name).accessibilityIdentifier("categories.name")
                Picker("Parent", selection: $parent) {
                    Text("Top level").tag("")
                    ForEach(possibleParents) { Text(store.ledger.categoryPath($0.id)).tag($0.id) }
                }.accessibilityIdentifier("categories.parent")
                if let category {
                    Section {
                        Button("View all logs (\(store.ledger.groupEntryCounts()[category.id, default: 0]))") { viewingLogs = true }
                        Button("Delete category", role: .destructive) { deleting = true }.accessibilityIdentifier("group.delete")
                    } footer: {
                        Text("Logs and timestamps are kept. Deleted category shares become Uncategorized, and children move up one level. Moving a category under a parent removes its top-level target; earlier budget versions are retained.")
                    }
                }
                if let error { Text(error).foregroundStyle(.red) }
            }.scrollDismissesKeyboard(.interactively).ledgerInputDismissal()
                .navigationTitle(category == nil ? "New category" : "Edit category").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") {
                        do { try store.editCategory(id: category?.id, name: name, parent: parent.isEmpty ? nil : parent); dismiss() } catch { self.error = error.localizedDescription }
                    }.accessibilityIdentifier("categories.save").disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
                }
                .onAppear { name = category?.name ?? ""; parent = category.flatMap { store.ledger.categoryParents[$0.id] } ?? "" }
                .confirmationDialog("Delete \(category?.name ?? "category")?", isPresented: $deleting, titleVisibility: .visible) {
                    Button("Delete category", role: .destructive) {
                        do { if let category { try store.deleteCategory(id: category.id) }; dismiss() } catch { self.error = error.localizedDescription }
                    }
                } message: { Text("Historical logs will be kept. This category’s shares become Uncategorized. Children are promoted, and its target is removed from the current budget.") }
                .sheet(isPresented: $viewingLogs) {
                    if let category { GroupEntriesView(day: Date(), groupID: category.id, initialName: category.name, allTime: true) }
                }
        }
    }
}
