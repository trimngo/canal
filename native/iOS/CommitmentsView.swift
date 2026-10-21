import SwiftUI
import UIKit
import LedgerCore

private enum CategoryActionRequest: Identifiable {
    case name(LedgerCategory?, parent: String?), logs(LedgerCategory), move([String])
    var id: String {
        switch self {
        case .name(let category, let parent): return "name:\(category?.id ?? "new"):\(parent ?? "root")"
        case .logs(let category): return "logs:\(category.id)"
        case .move(let ids): return "move:\(ids.joined(separator: ","))"
        }
    }
}

private struct CategoryOutlineItem: Identifiable {
    let category: LedgerCategory
    let depth: Int
    var direct = false
    var id: String { direct ? "direct:\(category.id)" : category.id }
}

struct CommitmentsView: View {
    @EnvironmentObject private var store: LedgerStore
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var plan = AllocationPlanDraft([:])
    @State private var loaded = false
    @State private var selected = Set<String>()
    @State private var selecting = false
    @State private var expanded = Set<String>()
    @State private var actionRequest: CategoryActionRequest?
    @State private var moveSelection: [String] = []
    @State private var confirmGrouping = false
    @State private var deleting: LedgerCategory?
    @State private var error: String?
    @FocusState private var focusedTarget: String?

    private var roots: [LedgerCategory] { store.ledger.children(of: nil) }
    private var stale: Bool { !(plan.values?.keys.allSatisfy { id in roots.contains { $0.id == id } } ?? true) }
    private var canSave: Bool { plan.isComplete && plan.isDirty && !stale && store.storageAvailable }

    var body: some View {
        TimelineView(.periodic(from: Date(), by: 60)) { context in
            let today = store.ledger.allocation(on: context.date, now: context.date)
            let week = store.ledger.rollingAllocation(now: context.date)
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Your allocation").bold(); Spacer()
                            Text(plan.total.map { "\(percent($0))% / 100%" } ?? "Check percentages")
                                .bold().monospacedDigit().accessibilityIdentifier("plan.total")
                        }
                        if let total = plan.total {
                            Text(abs(total - 100) < 0.0000001 ? "100% assigned" : total > 100 ? "\(percent(total - 100))% over — reduce a goal" : "\(percent(100 - total))% left to assign")
                                .font(.subheadline).foregroundStyle(total > 100 ? Color.red : Color.secondary)
                                .accessibilityIdentifier("plan.balance")
                        } else {
                            Text("Enter percentages between 0 and 100.").font(.subheadline).foregroundStyle(.red)
                        }
                    }.padding(.vertical, 4)
                    if stale {
                        Text("Categories changed while you were editing. Reload the saved plan to continue.").font(.caption).foregroundStyle(.red)
                        Button("Reload saved plan") { load() }.accessibilityIdentifier("plan.reload")
                    }
                    Button("Save plan") { save() }.disabled(!canSave).accessibilityIdentifier("categories.save-targets")
                } footer: {
                    Text("Set top-level category goals totaling 100%. Editing one share leaves the others unchanged.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    ForEach(outline(today: today, week: week)) { item in
                        categoryRow(item, today: today, week: week)
                            .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                            .listRowBackground(!item.direct && selected.contains(item.category.id) ? Color.accentColor.opacity(0.2) : Color.clear)
                    }
                } header: {
                    if typeSize.isAccessibilitySize { Text("Categories") }
                    else { columnHeadings }
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Hold a category for actions. Tap the arrow to expand its children. Moving a parent carries its children.")
                        Text("Actual time: estimated sample periods today, and \(week.representedDays) of the last 7 days. Estimates extend half your notification interval around the first and last logs, capped at now and calendar-day boundaries. pp shows percentage points above or below your goal.")
                            .accessibilityIdentifier("plan.coverage")
                    }.font(.caption).foregroundStyle(.secondary)
                }
                if !selecting {
                    Button("New top-level category", systemImage: "plus") { actionRequest = .name(nil, parent: nil) }
                        .accessibilityIdentifier("plan.create-category")
                }
                CategoryMoveUndoSection()
                if let error { Text(error).foregroundStyle(.red).accessibilityIdentifier("plan.error") }
            }.listStyle(.plain).listSectionSpacing(0)
                .scrollDismissesKeyboard(.interactively).ledgerInputDismissal()
        }
        .navigationTitle("Commitments").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if selecting {
                    Button("Done") { finishSelection() }.accessibilityIdentifier("plan.selection-done")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if selecting { selectionActions.padding(.horizontal, 8).padding(.vertical, 6).background(.bar) }
        }
        .onAppear { if !loaded { load(); loaded = true } }
        .onChange(of: store.ledger.currentBudget()?.id) { _, _ in if !plan.isDirty { load() } }
        .onChange(of: roots.map(\.id)) { _, ids in
            if !plan.isDirty { load() }
        }
        .onChange(of: store.ledger.categories.map(\.id)) { _, ids in selected.formIntersection(ids) }
        .onChange(of: focusedTarget) { _, id in
            guard id != nil else { return }
            DispatchQueue.main.async {
                UIApplication.shared.sendAction(#selector(UIResponderStandardEditActions.selectAll(_:)), to: nil, from: nil, for: nil)
            }
        }
        .sheet(item: $actionRequest) { request in
            switch request {
            case .move(let ids): CategoryMoveView(ids: ids) { finishSelection() }
            case .name(let category, let parent): CategoryNameView(category: category, parentID: parent) { finishSelection() }
            case .logs(let category):
                GroupEntriesView(day: Date(), groupID: category.id, initialName: category.name, allTime: true)
                    .onAppear { finishSelection() }
            }
        }
        .confirmationDialog("Delete category?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("Delete category", role: .destructive) {
                guard let category = deleting else { return }
                do { try store.deleteCategory(id: category.id); deleting = nil; finishSelection() }
                catch { self.error = error.localizedDescription }
            }
            Button("Cancel", role: .cancel) { deleting = nil }
        } message: { Text("Logs are kept. This category’s shares become Uncategorized, its label is removed from ideas, and children move up one level.") }
        .confirmationDialog("Save your goal changes before grouping?", isPresented: $confirmGrouping, titleVisibility: .visible) {
            if canSave { Button("Save and group") { if save() { actionRequest = .move(moveSelection) } } }
            Button("Discard changes and group", role: .destructive) { load(); actionRequest = .move(moveSelection) }
            Button("Keep editing", role: .cancel) {}
        }
    }

    private var columnHeadings: some View {
        HStack(spacing: 4) {
            Text("Category").frame(maxWidth: .infinity, alignment: .leading)
            Text("Goal").frame(width: 52, alignment: .trailing)
            Text("Today").frame(width: 60, alignment: .trailing)
            Text("7 days").frame(width: 60, alignment: .trailing)
        }.font(.caption2).foregroundStyle(.secondary).textCase(nil)
            .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
    }

    private func outline(today: AllocationPeriod, week: AllocationPeriod) -> [CategoryOutlineItem] {
        var result: [CategoryOutlineItem] = []
        func append(_ category: LedgerCategory, depth: Int) {
            result.append(CategoryOutlineItem(category: category, depth: depth))
            let children = store.ledger.children(of: category.id)
            guard expanded.contains(category.id), !children.isEmpty else { return }
            if today.directMinutes[category.id, default: 0] > 0 || week.directMinutes[category.id, default: 0] > 0 {
                result.append(CategoryOutlineItem(category: category, depth: depth + 1, direct: true))
            }
            for child in children { append(child, depth: depth + 1) }
        }
        for category in roots { append(category, depth: 0) }
        return result
    }

    private func categoryRow(_ item: CategoryOutlineItem, today: AllocationPeriod, week: AllocationPeriod) -> some View {
        let category = item.category
        let target = item.depth == 0 ? plan.values?[category.id] : nil
        let todayMinutes = item.direct ? today.directMinutes[category.id, default: 0] : today.total(for: category.id, ledger: store.ledger)
        let weekMinutes = item.direct ? week.directMinutes[category.id, default: 0] : week.total(for: category.id, ledger: store.ledger)
        return Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) { categoryName(item); goal(item) }
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Today").font(.caption)
                            AllocationOutlineValue(title: "Today", period: today, minutes: todayMinutes, target: target, compact: false)
                        }
                        Spacer()
                        VStack(alignment: .leading) {
                            Text("7 days").font(.caption)
                            AllocationOutlineValue(title: "7 days", period: week, minutes: weekMinutes, target: target, compact: false)
                        }
                    }
                }
            } else {
                HStack(spacing: 4) {
                    categoryName(item)
                    HStack(spacing: 4) {
                        goal(item)
                        AllocationOutlineValue(title: "Today", period: today, minutes: todayMinutes, target: target)
                        AllocationOutlineValue(title: "7 days", period: week, minutes: weekMinutes, target: target)
                    }.contentShape(Rectangle()).onTapGesture { if selecting && !item.direct { toggleSelected(category.id) } }
                }
            }
        }.accessibilityElement(children: .contain)
            .accessibilityAddTraits(selected.contains(category.id) && !item.direct ? .isSelected : [])
            .simultaneousGesture(LongPressGesture().onEnded { _ in
                guard !item.direct else { return }
                UIApplication.shared.dismissLedgerKeyboard()
                selecting = true; selected.insert(category.id)
            })
    }

    private func categoryName(_ item: CategoryOutlineItem) -> some View {
        let category = item.category
        let hasChildren = !item.direct && !store.ledger.children(of: category.id).isEmpty
        return HStack(spacing: 0) {
            if hasChildren {
                Button { toggleExpanded(category.id) } label: {
                    Image(systemName: expanded.contains(category.id) ? "chevron.down" : "chevron.right")
                        .font(.caption2).frame(width: 28, height: 44).contentShape(Rectangle())
                }.buttonStyle(.borderless)
                    .accessibilityLabel("\(expanded.contains(category.id) ? "Collapse" : "Expand") \(category.name)")
                    .accessibilityIdentifier("plan.children.\(category.id)")
            } else { Color.clear.frame(width: 28, height: 1).accessibilityHidden(true) }
                Text(item.direct ? "Direct" : category.name)
                    .foregroundStyle(item.direct ? Color.secondary : Color.primary)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
                    .onTapGesture {
                        guard !item.direct else { return }
                        if selecting { toggleSelected(category.id) }
                        else if hasChildren { toggleExpanded(category.id) }
                    }
                    .accessibilityLabel(item.direct ? "Directly assigned to \(category.name)" : category.name)
                    .accessibilityValue(selected.contains(category.id) && !item.direct ? "Selected" : "Not selected")
                    .accessibilityAction(named: "Select category") { if !item.direct { selecting = true; selected.insert(category.id) } }
                    .accessibilityIdentifier(item.direct ? "plan.direct.\(category.id)" : "plan.name.\(category.id)")
        }.font(item.depth == 0 ? .subheadline.weight(.semibold) : .subheadline)
            .lineLimit(typeSize.isAccessibilitySize ? nil : 2).padding(.leading, CGFloat(item.depth) * 12)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func goal(_ item: CategoryOutlineItem) -> some View {
        if item.depth == 0 {
            HStack(spacing: 0) {
                TextField("—", text: Binding(get: { plan.text[item.category.id] ?? "" }, set: { plan.text[item.category.id] = $0 }))
                    .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    .focused($focusedTarget, equals: item.category.id)
                    .disabled(selecting).allowsHitTesting(!selecting)
                    .accessibilityLabel("\(item.category.name) goal percent")
                    .accessibilityIdentifier("categories.target.\(item.category.id)")
                Text("%").font(.caption2).foregroundStyle(.secondary)
            }.font(.subheadline).frame(width: typeSize.isAccessibilitySize ? 86 : 52).frame(minHeight: 44)
        } else {
            Text("—").font(.caption).foregroundStyle(.secondary)
                .frame(width: typeSize.isAccessibilitySize ? 86 : 52, alignment: .trailing)
                .accessibilityLabel("No goal for subcategories")
        }
    }
    private func percent(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0...2))) }
    private func load() { plan = AllocationPlanDraft(store.ledger.currentTargets()); error = nil }
    @discardableResult private func save() -> Bool {
        guard canSave, let values = plan.values else { return false }
        UIApplication.shared.dismissLedgerKeyboard()
        do { try store.saveAllocationPlan(values); load(); return true }
        catch { self.error = error.localizedDescription; return false }
    }
    private func groupSelected() {
        UIApplication.shared.dismissLedgerKeyboard()
        // Freeze the selection while the destination sheet is open. A move or
        // a sync can change the root list before the sheet finishes dismissing.
        moveSelection = store.ledger.orderedCategories.filter { selected.contains($0.id) }.map(\.id)
        guard !moveSelection.isEmpty else { return }
        if plan.isDirty { confirmGrouping = true }
        else { actionRequest = .move(moveSelection) }
    }

    private func finishSelection() { selected = []; selecting = false }
    private func toggleExpanded(_ id: String) { if !expanded.insert(id).inserted { expanded.remove(id) } }
    private func toggleSelected(_ id: String) { if !selected.insert(id).inserted { selected.remove(id) } }
    private var singleSelection: LedgerCategory? {
        guard selected.count == 1 else { return nil }
        return store.ledger.categories.first { selected.contains($0.id) }
    }
    private var selectionActions: some View {
        VStack(spacing: 4) {
            Text(selected.isEmpty ? "Tap categories to select" : "\(selected.count) selected").font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 0) {
                if let category = singleSelection {
                    actionButton("Rename", icon: "pencil", id: "plan.rename") { actionRequest = .name(category, parent: store.ledger.categoryParents[category.id]) }
                    actionButton("Add child", icon: "plus", id: "plan.create-child") { actionRequest = .name(nil, parent: category.id) }
                    actionButton("Logs", icon: "list.bullet", id: "plan.view-logs") { actionRequest = .logs(category) }
                }
                actionButton("Move", icon: "folder", id: "plan.group-selected") { groupSelected() }.disabled(selected.isEmpty)
                if let category = singleSelection {
                    actionButton("Delete", icon: "trash", id: "plan.delete") {
                        if plan.isDirty { error = "Save or reload your goal changes before deleting a category." }
                        else { deleting = category }
                    }.tint(.red)
                }
            }.disabled(!store.storageAvailable)
        }
    }
    private func actionButton(_ title: String, icon: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) { Image(systemName: icon); Text(title).font(.caption2) }
                .frame(maxWidth: .infinity, minHeight: 44)
        }.buttonStyle(.borderless).accessibilityIdentifier(id)
    }
}
