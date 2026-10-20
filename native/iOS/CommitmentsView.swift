import SwiftUI
import UIKit
import LedgerCore

private struct CategoryGroupingRequest: Identifiable {
    let id = UUID()
    let categoryIDs: [String]
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
    @State private var expanded = Set<String>()
    @State private var groupingRequest: CategoryGroupingRequest?
    @State private var moveSelection: [String] = []
    @State private var confirmGrouping = false
    @State private var managingCategories = false
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
                    }
                } header: {
                    if typeSize.isAccessibilitySize { Text("Categories") }
                    else { columnHeadings }
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Select circles to group categories under a parent. Tap a parent’s name to see its children.")
                        Text("Actual time: today since your first log, and \(week.representedDays) of the last 7 days. Times are estimates; pp shows percentage points above or below your goal.")
                            .accessibilityIdentifier("plan.coverage")
                    }.font(.caption).foregroundStyle(.secondary)
                }
                CategoryMoveUndoSection()
                if let error { Text(error).foregroundStyle(.red).accessibilityIdentifier("plan.error") }
            }.listStyle(.plain).listSectionSpacing(0)
                .scrollDismissesKeyboard(.interactively).ledgerInputDismissal()
        }
        .navigationTitle("Commitments").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Manage") { UIApplication.shared.dismissLedgerKeyboard(); managingCategories = true }
                    .accessibilityLabel("Manage categories").accessibilityIdentifier("plan.manage-categories")
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !selected.isEmpty {
                HStack(spacing: 12) {
                    Button("Clear") { selected = [] }.accessibilityIdentifier("plan.clear-selection")
                    Button { groupSelected() } label: {
                        Text("Group \(selected.count) selected").frame(maxWidth: .infinity).padding(.vertical, 6)
                    }.buttonStyle(.borderedProminent).disabled(!store.storageAvailable)
                        .accessibilityIdentifier("plan.group-selected")
                }.padding().background(.bar)
            }
        }
        .onAppear { if !loaded { load(); loaded = true } }
        .onChange(of: store.ledger.currentBudget()?.id) { _, _ in if !plan.isDirty { load() } }
        .onChange(of: roots.map(\.id)) { _, ids in
            selected.formIntersection(ids)
            if !plan.isDirty { load() }
        }
        .onChange(of: focusedTarget) { _, id in
            guard id != nil else { return }
            DispatchQueue.main.async {
                UIApplication.shared.sendAction(#selector(UIResponderStandardEditActions.selectAll(_:)), to: nil, from: nil, for: nil)
            }
        }
        .sheet(item: $groupingRequest) { request in
            CategoryMoveView(ids: request.categoryIDs) { selected = [] }
        }
        .sheet(isPresented: $managingCategories) { GroupManagerView() }
        .confirmationDialog("Save your goal changes before grouping?", isPresented: $confirmGrouping, titleVisibility: .visible) {
            if canSave { Button("Save and group") { if save() { groupingRequest = CategoryGroupingRequest(categoryIDs: moveSelection) } } }
            Button("Discard changes and group", role: .destructive) { load(); groupingRequest = CategoryGroupingRequest(categoryIDs: moveSelection) }
            Button("Keep editing", role: .cancel) {}
        }
    }

    private var columnHeadings: some View {
        HStack(spacing: 4) {
            Color.clear.frame(width: 44, height: 1)
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
                    HStack(spacing: 4) { selection(item); categoryName(item); goal(item) }
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
                    }.padding(.leading, 48)
                }
            } else {
                HStack(spacing: 4) {
                    selection(item)
                    categoryName(item)
                    goal(item)
                    AllocationOutlineValue(title: "Today", period: today, minutes: todayMinutes, target: target)
                    AllocationOutlineValue(title: "7 days", period: week, minutes: weekMinutes, target: target)
                }
            }
        }.accessibilityElement(children: .contain)
    }

    @ViewBuilder private func selection(_ item: CategoryOutlineItem) -> some View {
        if item.depth == 0 {
            Button {
                if !selected.insert(item.category.id).inserted { selected.remove(item.category.id) }
            } label: {
                Image(systemName: selected.contains(item.category.id) ? "checkmark.circle.fill" : "circle")
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }.buttonStyle(.borderless)
                .accessibilityLabel("Select \(item.category.name) for grouping")
                .accessibilityValue(selected.contains(item.category.id) ? "Selected" : "Not selected")
                .accessibilityAddTraits(selected.contains(item.category.id) ? .isSelected : [])
                .accessibilityIdentifier("plan.select.\(item.category.id)")
        } else { Color.clear.frame(width: 44, height: 1).accessibilityHidden(true) }
    }

    private func categoryName(_ item: CategoryOutlineItem) -> some View {
        let category = item.category
        let hasChildren = !item.direct && !store.ledger.children(of: category.id).isEmpty
        return Group {
            if hasChildren {
                Button {
                    if !expanded.insert(category.id).inserted { expanded.remove(category.id) }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: expanded.contains(category.id) ? "chevron.down" : "chevron.right")
                            .font(.caption2).frame(width: 10)
                        Text(category.name).multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }.frame(minHeight: 44).contentShape(Rectangle())
                }.buttonStyle(.plain)
                    .accessibilityLabel("\(expanded.contains(category.id) ? "Collapse" : "Expand") \(category.name)")
                    .accessibilityIdentifier("plan.children.\(category.id)")
            } else {
                Text(item.direct ? "Direct" : category.name)
                    .foregroundStyle(item.direct ? Color.secondary : Color.primary)
                    .padding(.leading, 14).frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                    .accessibilityLabel(item.direct ? "Directly assigned to \(category.name)" : category.name)
                    .accessibilityIdentifier(item.direct ? "plan.direct.\(category.id)" : "plan.name.\(category.id)")
            }
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
        moveSelection = roots.filter { selected.contains($0.id) }.map(\.id)
        guard !moveSelection.isEmpty else { return }
        if plan.isDirty { confirmGrouping = true }
        else { groupingRequest = CategoryGroupingRequest(categoryIDs: moveSelection) }
    }
}
