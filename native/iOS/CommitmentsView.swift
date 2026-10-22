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
    @State private var multiSelecting = false
    @State private var dirtyGoals = Set<String>()
    @State private var showingHelp = false
    @State private var copyingWeek = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var expanded = Set<String>()
    @State private var actionRequest: CategoryActionRequest?
    @State private var moveSelection: [String] = []
    @State private var deleting: LedgerCategory?
    @State private var confirmingDeletion = false
    @State private var error: String?
    @FocusState private var focusedTarget: String?

    private var roots: [LedgerCategory] { store.ledger.children(of: nil) }
    private var selecting: Bool { multiSelecting || !selected.isEmpty }
    private var balance: AllocationGoalBalance? { plan.values.map { store.ledger.allocationGoalBalance($0) } }

    var body: some View {
        TimelineView(.periodic(from: Date(), by: 60)) { context in
            let today = store.ledger.allocation(on: context.date, now: context.date)
            let week = store.ledger.rollingAllocation(now: context.date)
            planList(today: today, week: week)
        }
        .navigationTitle("Commitments").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if selecting { Button("Done") { finishSelection() }.accessibilityIdentifier("plan.selection-done") }
                if !multiSelecting {
                    Button("Select") { endGoalEditing(); multiSelecting = true }.accessibilityIdentifier("plan.select")
                }
            }
            ToolbarItemGroup(placement: .keyboard) {
                if let id = focusedTarget {
                    Button("Use 7 days") { copyGoal(id) }.accessibilityIdentifier("plan.copy-focused-week")
                }
                Spacer()
                Button("Done") { endGoalEditing() }.accessibilityIdentifier("keyboard.done")
            }
        }
        .safeAreaInset(edge: .bottom) {
            if selecting { selectionActions.padding(.horizontal, 8).padding(.vertical, 6).background(.bar) }
        }
        .onAppear { if !loaded { load(); loaded = true } }
        .onChange(of: store.ledger.currentBudget()?.id) { _, _ in load() }
        .onChange(of: store.ledger.categories) { _, categories in
            selected.formIntersection(categories.map(\.id)); load()
        }
        .onChange(of: focusedTarget) { old, id in
            if let old { persistGoal(old) }
            guard id != nil else { return }
            selected = []; multiSelecting = false
            DispatchQueue.main.async {
                UIApplication.shared.sendAction(#selector(UIResponderStandardEditActions.selectAll(_:)), to: nil, from: nil, for: nil)
            }
        }
        .onChange(of: scenePhase) { _, phase in if phase != .active { persistGoals() } }
        .onDisappear { persistGoals() }
        .confirmationDialog("Use the last seven days as your goals?", isPresented: $copyingWeek, titleVisibility: .visible) {
            Button("Use last seven days") { copyAllGoals() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Replace the current goals with measured percentages, including subcategories. Uncategorized time stays unallocated. Goals stay fixed until you edit them.") }

        .sheet(item: $actionRequest) { request in
            switch request {
            case .move(let ids): CategoryMoveView(ids: ids) { finishSelection() }
            case .name(let category, let parent): CategoryNameView(category: category, parentID: parent) { finishSelection() }
            case .logs(let category):
                GroupEntriesView(day: Date(), groupID: category.id, initialName: category.name, allTime: true)
                    .onAppear { finishSelection() }
            }
        }
        .confirmationDialog("Delete category?", isPresented: $confirmingDeletion, titleVisibility: .visible, presenting: deleting) { category in
            Button("Delete category", role: .destructive) {
                do { try store.deleteCategory(id: category.id); deleting = nil; finishSelection() }
                catch { self.error = error.localizedDescription }
            }
            Button("Cancel", role: .cancel) { deleting = nil }
        } message: { _ in Text("Logs are kept. This category’s shares become Uncategorized, its label is removed from ideas, and children move up one level.") }

    }

    private func planList(today: AllocationPeriod, week: AllocationPeriod) -> some View {
        List {
            allocationSummary
            categoryOutline(today: today, week: week)
            CategoryMoveUndoSection()
            if let error { Text(error).foregroundStyle(.red).accessibilityIdentifier("plan.error") }
        }.listStyle(.plain).listSectionSpacing(0)
            .scrollDismissesKeyboard(.interactively).ledgerInputDismissal(showsKeyboardDone: false)
    }

    private var allocationSummary: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text("Allocation").fontWeight(.semibold)
                    Button { showingHelp = true } label: { Image(systemName: "info.circle").frame(width: 32, height: 32) }
                        .buttonStyle(.borderless).accessibilityLabel("About goals and category actions").accessibilityIdentifier("plan.help")
                        .popover(isPresented: $showingHelp) {
                            ScrollView {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("Goals & categories").font(.headline)
                                    Text("Tap a goal to edit. Changes save automatically. Use 7 days copies measured time into a fixed goal. Other goals stay unchanged.")
                                    Text("Top-level goals total 100%. A child goal is a share of all your time, included within its parent. Leave child goals blank if you prefer.")
                                    Text("Tap a category for actions. Select enables multiple selection. Arrows expand children; moving a parent carries its children.")
                                    Text("Actuals use estimated sample periods. 7 days includes today and the six preceding dates; days with no logs are excluded. Uncategorized still counts toward the measured total.")
                                    Text("Red is below goal, green is at goal at displayed precision, amber is above goal. pp means percentage points. These colors describe alignment, not whether an activity is good or bad.")
                                }.font(.subheadline).padding()
                            }.frame(width: 300, height: 350).presentationCompactAdaptation(.popover)
                        }
                    Spacer()
                    Text(balance.map { "\(percent($0.total))% / 100%" } ?? "Check values")
                        .fontWeight(.semibold).monospacedDigit().accessibilityIdentifier("plan.total")
                }
                if let balance {
                    Text(abs(balance.total - 100) < 0.0000001 ? "100% allocated" : balance.total > 100 ? "\(percent(balance.total - 100))% over allocated" : "\(percent(100 - balance.total))% left to allocate")
                        .font(.caption).foregroundStyle(balance.total > 100 ? Color.red : Color.secondary)
                        .accessibilityIdentifier("plan.balance")
                    if let id = balance.overages.keys.sorted().first {
                        Text("Child goals exceed \(store.categoryName(id)) by \(percent(balance.overages[id]!))%. Saved · allocation unfinished.")
                            .font(.caption).foregroundStyle(.red).accessibilityIdentifier("plan.branch-balance")
                    } else if let id = balance.missingRootGoals.first {
                        Text("Set a parent goal for \(store.categoryName(id)). Saved · allocation unfinished.")
                            .font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("plan.branch-balance")
                    }
                }
                Button("Use last 7 days as goals", systemImage: "arrow.uturn.backward") { endGoalEditing(); copyingWeek = true }
                    .font(.subheadline).buttonStyle(.borderless)
                    .disabled(!store.ledger.rollingAllocation().sufficient || !store.storageAvailable)
                    .accessibilityIdentifier("plan.copy-week")
            }.padding(.vertical, 2)
        }
    }

    private func categoryOutline(today: AllocationPeriod, week: AllocationPeriod) -> some View {
        Section {
            ForEach(outline(today: today, week: week)) { item in
                categoryRow(item, today: today, week: week)
                    .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                    .listRowBackground(SelectionRowBackground(selected: !item.direct && selected.contains(item.category.id)))
            }
            Button("New top-level category", systemImage: "plus") { endGoalEditing(); actionRequest = .name(nil, parent: nil) }
                .accessibilityIdentifier("plan.create-category")
                .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
        } header: {
            if typeSize.isAccessibilitySize { Text("Categories") }
            else { columnHeadings(week: week) }
        }
    }

    private func columnHeadings(week: AllocationPeriod) -> some View {
        HStack(spacing: 4) {
            Text("Category").frame(maxWidth: .infinity, alignment: .leading)
            Text("Goal").frame(width: 52, alignment: .trailing)
            Text("Today").frame(width: 60, alignment: .trailing)
            VStack(alignment: .trailing, spacing: 1) { Text("7 days"); Text("\(week.representedDays) of 7").accessibilityIdentifier("plan.coverage") }.frame(width: 60, alignment: .trailing)
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
        let target = item.direct ? nil : store.ledger.currentGoals()[category.id]
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
                    }
                }
            }
        }.accessibilityElement(children: .contain)
            .accessibilityAddTraits(selected.contains(category.id) && !item.direct ? .isSelected : [])

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
                        selectCategory(category.id)
                    }
                    .accessibilityLabel(item.direct ? "Directly assigned to \(category.name)" : category.name)
                    .accessibilityValue(selected.contains(category.id) && !item.direct ? "Selected" : "Not selected")
                    .accessibilityAction(named: "Select category") { if !item.direct { selectCategory(category.id) } }
                    .accessibilityIdentifier(item.direct ? "plan.direct.\(category.id)" : "plan.name.\(category.id)")
        }.font(item.depth == 0 ? .subheadline.weight(.semibold) : .subheadline)
            .lineLimit(typeSize.isAccessibilitySize ? nil : 2).padding(.leading, CGFloat(item.depth) * 12)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func goal(_ item: CategoryOutlineItem) -> some View {
        if !item.direct {
            HStack(spacing: 0) {
                TextField("—", text: Binding(get: { plan.text[item.category.id] ?? "" }, set: { plan.text[item.category.id] = $0; dirtyGoals.insert(item.category.id) }))
                    .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    .focused($focusedTarget, equals: item.category.id)
                    .disabled(multiSelecting || !store.storageAvailable).allowsHitTesting(!multiSelecting)
                    .accessibilityLabel("\(item.category.name) goal percent")
                    .accessibilityIdentifier("categories.target.\(item.category.id)")
                Text("%").font(.caption2).foregroundStyle(.secondary)
            }.font(.subheadline).frame(width: typeSize.isAccessibilitySize ? 86 : 52).frame(minHeight: 44)
        } else {
            Text("—").font(.caption).foregroundStyle(.secondary)
                .frame(width: typeSize.isAccessibilitySize ? 86 : 52, alignment: .trailing)
                .accessibilityLabel("Direct time is included in the category goal")
        }
    }
    private func percent(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0...2))) }
    private func load() {
        let known = Set(store.ledger.categories.map(\.id))
        dirtyGoals.formIntersection(known)
        var refreshed = AllocationPlanDraft(store.ledger.currentGoals())
        for id in dirtyGoals { refreshed.text[id] = plan.text[id] }
        plan = refreshed
    }
    private func persistGoal(_ id: String) {
        guard dirtyGoals.contains(id) else { return }
        let text = plan.text[id] ?? ""
        var field = AllocationPlanDraft([:]); field.text[id] = text
        guard let values = field.values else { error = "Enter a percentage from 0 to 100 for \(store.categoryName(id))."; return }
        do {
            try store.updateAllocationGoal(categoryID: id, percentage: values[id])
            dirtyGoals.remove(id); error = nil; load()
        } catch { self.error = error.localizedDescription }
    }
    private func persistGoals() { for id in dirtyGoals.sorted() { persistGoal(id) } }
    private func endGoalEditing() { focusedTarget = nil; UIApplication.shared.dismissLedgerKeyboard(); persistGoals() }
    private func copyGoal(_ id: String) {
        guard let value = store.ledger.goalPercentage(for: id, from: store.ledger.rollingAllocation()) else { return }
        dirtyGoals.remove(id)
        do { try store.updateAllocationGoal(categoryID: id, percentage: value); error = nil; load() }
        catch { self.error = error.localizedDescription }
    }
    private func copyAllGoals() {
        guard let values = store.ledger.goalsFromAllocation(store.ledger.rollingAllocation()) else { return }
        do { try store.saveAllocationGoals(values); dirtyGoals = []; error = nil; load() }
        catch { self.error = error.localizedDescription }
    }
    private func groupSelected() {
        endGoalEditing()
        guard dirtyGoals.isEmpty else { return }
        moveSelection = store.ledger.orderedCategories.filter { selected.contains($0.id) }.map(\.id)
        guard !moveSelection.isEmpty else { return }
        actionRequest = .move(moveSelection)
    }
    private func selectCategory(_ id: String) {
        endGoalEditing()
        if multiSelecting { if !selected.insert(id).inserted { selected.remove(id) } }
        else { selected = [id] }
    }
    private func finishSelection() { selected = []; multiSelecting = false }
    private func toggleExpanded(_ id: String) { if !expanded.insert(id).inserted { expanded.remove(id) } }
    private var singleSelection: LedgerCategory? {
        guard selected.count == 1 else { return nil }
        return store.ledger.categories.first { selected.contains($0.id) }
    }
    private var selectionActions: some View {
        VStack(spacing: 4) {
            HStack {
                Text(selected.isEmpty ? "Tap categories to select" : "\(selected.count) selected").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if let category = singleSelection {
                    Button("Use 7-day goal") { copyGoal(category.id); finishSelection() }
                        .font(.caption).disabled(!store.ledger.rollingAllocation().sufficient)
                        .accessibilityIdentifier("plan.copy-selected-week")
                }
            }
            HStack(spacing: 0) {
                if let category = singleSelection {
                    actionButton("Rename", icon: "pencil", id: "plan.rename") { actionRequest = .name(category, parent: store.ledger.categoryParents[category.id]) }
                    actionButton("Add child", icon: "plus", id: "plan.create-child") { actionRequest = .name(nil, parent: category.id) }
                    actionButton("Logs", icon: "list.bullet", id: "plan.view-logs") { actionRequest = .logs(category) }
                }
                actionButton("Move", icon: "folder", id: "plan.group-selected") { groupSelected() }.disabled(selected.isEmpty)
                if let category = singleSelection {
                    actionButton("Delete", icon: "trash", id: "plan.delete") {
                        endGoalEditing()
                        if dirtyGoals.isEmpty { deleting = category; confirmingDeletion = true }
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
