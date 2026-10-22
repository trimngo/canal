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
    @State private var reference = AllocationReference()
    @AppStorage("goals.display-unit") private var displayUnit = AllocationDisplayUnit.percent
    // Keep the existing preference key so upgrades preserve the filter choice.
    @AppStorage("commitments.hide-zero-time") private var hideBlankGoals = true
    @State private var loaded = false
    @State private var selected = Set<String>()
    @State private var multiSelecting = false
    @State private var dirtyGoals = Set<String>()
    @State private var showingHelp = false
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
    private var percentageGoals: [String: Double]? {
        guard let values = plan.values else { return nil }
        if displayUnit == .percent { return values }
        guard reference.averageDayMinutes != nil else { return store.ledger.editableAllocationGoals() }
        var result: [String: Double] = [:]
        for (id, hours) in values {
            guard let value = reference.percentage(forDailyHours: hours), value <= 100 + 0.0000001 else { return nil }
            result[id] = min(100, value)
        }
        return result
    }
    private var displayedGoals: [String: Double] { percentageGoals.map { store.ledger.calculatedAllocationGoals($0) } ?? store.ledger.currentGoals() }

    var body: some View {
        TimelineView(.periodic(from: Date(), by: 60)) { context in
            let today = store.ledger.allocation(on: context.date, now: context.date)
            let week = reference.period
            planList(today: today, week: week)
                .onChange(of: store.ledger.reportingDay(containing: context.date)) { _, _ in refreshReference(); load() }
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
        .safeAreaInset(edge: .top, spacing: 0) { displayControls }
        .safeAreaInset(edge: .bottom) {
            if selecting { selectionActions.padding(.horizontal, 8).padding(.vertical, 6).background(.bar) }
        }
        .onAppear { if !loaded { refreshReference(); load(); loaded = true } }
        .onChange(of: store.ledger.currentBudget()?.id) { _, _ in load() }
        .onChange(of: store.ledger.categories) { _, categories in
            selected.formIntersection(categories.map(\.id)); refreshReference(); load()
        }
        .onChange(of: store.ledger.entries) { _, _ in refreshReference(); load() }
        .onChange(of: store.ledger.logDeletions) { _, _ in refreshReference(); load() }
        .onChange(of: store.ledger.settings) { _, _ in refreshReference(); load() }
        .onChange(of: focusedTarget) { old, id in
            if let old { persistGoal(old) }
            guard id != nil else { refreshReference(); load(); return }
            selected = []; multiSelecting = false
            DispatchQueue.main.async {
                UIApplication.shared.sendAction(#selector(UIResponderStandardEditActions.selectAll(_:)), to: nil, from: nil, for: nil)
            }
        }
        .onChange(of: scenePhase) { _, phase in if phase != .active { persistGoals() } }
        .onDisappear { persistGoals() }
        .sheet(item: $actionRequest) { request in
            switch request {
            case .move(let ids): CategoryMoveView(ids: ids) { finishSelection() }
            case .name(let category, let parent):
                CategoryNameView(category: category, parentID: parent) {
                    finishSelection()
                    if category == nil {
                        hideBlankGoals = false
                        if let parent { expanded.insert(parent) }
                    }
                }
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
            categoryOutline(today: today, week: week)
            CategoryMoveUndoSection()
            if let error { Text(error).foregroundStyle(.red).accessibilityIdentifier("plan.error") }
        }.listStyle(.plain).listSectionSpacing(0)
            .scrollDismissesKeyboard(.interactively).ledgerInputDismissal(showsKeyboardDone: false)
    }

    private var displayControls: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Picker("Display unit", selection: Binding(get: { displayUnit }, set: switchUnit)) {
                    ForEach(AllocationDisplayUnit.allCases, id: \.self) { unit in Text(unit.label).tag(unit) }
                }.pickerStyle(.segmented).frame(width: 144).accessibilityIdentifier("plan.unit")
                Spacer(minLength: 0)
                Button { endGoalEditing(); finishSelection(); hideBlankGoals.toggle() } label: {
                    Label("Hide blank", systemImage: "line.3.horizontal.decrease")
                        .font(.subheadline).lineLimit(1).minimumScaleFactor(0.8)
                }.buttonStyle(.bordered).tint(hideBlankGoals ? Color.accentColor : Color.secondary)
                    .accessibilityLabel("Hide categories with blank goals")
                    .accessibilityValue(hideBlankGoals ? "On" : "Off")
                    .accessibilityAddTraits(hideBlankGoals ? .isSelected : [])
                    .accessibilityIdentifier("plan.hide-blank-goals")
                Button { showingHelp = true } label: { Image(systemName: "info.circle").frame(width: 32, height: 36) }
                    .accessibilityLabel("About goals and category actions").accessibilityIdentifier("plan.help")
                    .popover(isPresented: $showingHelp) { goalHelp }
            }.padding(.horizontal, 12).padding(.vertical, 6)
            Divider()
        }.background(.bar)
    }

    private var goalHelp: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Goals & categories").font(.headline)
                Text("Choose % to compare balance or Time to judge hours. Each cell shows one unit. Time goals use decimal hours per day; today shows time so far and 7 days shows an average per recorded day.")
                if let minutes = reference.averageDayMinutes {
                    Text("Hours use an average recorded day of \(store.duration(minutes)), from \(reference.period.representedDays) of the previous seven completed dates. These are estimates from your logs, not a wake/sleep schedule. Missing days are excluded.")
                } else {
                    Text("A completed date with logs is needed to convert goals into hours. You can still edit percentages and see today’s time.")
                }
                Text("A goal stays a fixed percentage. Editing its hours equivalent converts it into that percentage; switching units never changes the saved goal. Hours equivalents can change as your recent recorded-day average changes.")
                Text("Hide blank removes only categories without a goal, regardless of time logged. A goal of 0% stays visible, as do parents with child goals. Direct rows have no separate goal and are hidden by this filter. Turn the filter off to see every category; nothing is deleted.")
                Text("Leave goals blank for activities you only want to observe. Goals save individually when you finish editing.")
                Text("Edit goals on categories without children. Each parent adds up its children’s goals. Direct time counts toward the parent’s actual time without a separate goal.")
                Text("Tap a category for actions. Select enables multiple selection. Arrows expand children; moving a parent carries its children. Use 7 days copies measured shares into fixed goals.")
                Text("Red is below goal, green is at goal, amber is above goal. In Time mode, today’s accumulated time is compared with the daily goal equivalent; in % mode, proportions are compared.")
            }.font(.subheadline).padding()
        }.frame(width: 300, height: 350).presentationCompactAdaptation(.popover)
    }

    private func amount(_ percentage: Double) -> String {
        if displayUnit == .percent { return "\(percent(percentage))%" }
        guard let minutes = reference.dailyMinutes(for: percentage) else { return "—" }
        return store.duration(minutes).replacingOccurrences(of: " 0m", with: "")
    }
    private func switchUnit(_ next: AllocationDisplayUnit) {
        guard next != displayUnit else { return }
        endGoalEditing()
        guard dirtyGoals.isEmpty else { return }
        refreshReference(); displayUnit = next; load()
    }
    private func refreshReference() {
        guard focusedTarget == nil, dirtyGoals.isEmpty else { return }
        reference = store.ledger.completedAllocationReference()
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
            Text(displayUnit == .time ? "Goal/day" : "Goal").frame(width: 52, alignment: .trailing)
            Text("Today").frame(width: 60, alignment: .trailing)
            VStack(alignment: .trailing, spacing: 1) { Text(displayUnit == .time ? "7d avg" : "7 days"); Text("\(week.representedDays) of 7").accessibilityIdentifier("plan.coverage") }.frame(width: 60, alignment: .trailing)
        }.font(.caption2).foregroundStyle(.secondary).textCase(nil)
            .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
    }

    private func outline(today: AllocationPeriod, week: AllocationPeriod) -> [CategoryOutlineItem] {
        var retainedGoals = displayedGoals
        for id in dirtyGoals { retainedGoals[id] = 0 }
        let visible = store.ledger.activeCategoryIDs(in: [], includingGoals: retainedGoals)
        var result: [CategoryOutlineItem] = []
        func append(_ category: LedgerCategory, depth: Int) {
            guard !hideBlankGoals || visible.contains(category.id) else { return }
            result.append(CategoryOutlineItem(category: category, depth: depth))
            let children = store.ledger.children(of: category.id)
            guard expanded.contains(category.id), !children.isEmpty else { return }
            if !hideBlankGoals && (today.directMinutes[category.id, default: 0] > 0 || week.directMinutes[category.id, default: 0] > 0) {
                result.append(CategoryOutlineItem(category: category, depth: depth + 1, direct: true))
            }
            for child in children { append(child, depth: depth + 1) }
        }
        for category in roots { append(category, depth: 0) }
        return result
    }

    private func categoryRow(_ item: CategoryOutlineItem, today: AllocationPeriod, week: AllocationPeriod) -> some View {
        let category = item.category
        let target = item.direct ? nil : displayedGoals[category.id]
        let todayMinutes = item.direct ? today.directMinutes[category.id, default: 0] : today.total(for: category.id, ledger: store.ledger)
        let weekMinutes = item.direct ? week.directMinutes[category.id, default: 0] : week.total(for: category.id, ledger: store.ledger)
        return Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) { categoryName(item); goal(item) }
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Today").font(.caption)
                            AllocationOutlineValue(title: "Today", period: today, minutes: todayMinutes, target: target, unit: displayUnit, reference: reference, compact: false).accessibilityIdentifier("plan.actual.today.\(item.id)")
                        }
                        Spacer()
                        VStack(alignment: .leading) {
                            Text(displayUnit == .time ? "7-day average per day" : "7 days").font(.caption)
                            AllocationOutlineValue(title: "7 days", period: week, minutes: weekMinutes, target: target, unit: displayUnit, reference: reference, dailyAverage: true, compact: false).accessibilityIdentifier("plan.actual.week.\(item.id)")
                        }
                    }
                }
            } else {
                HStack(spacing: 4) {
                    categoryName(item)
                    HStack(spacing: 4) {
                        goal(item)
                        AllocationOutlineValue(title: "Today", period: today, minutes: todayMinutes, target: target, unit: displayUnit, reference: reference).accessibilityIdentifier("plan.actual.today.\(item.id)")
                        AllocationOutlineValue(title: "7 days", period: week, minutes: weekMinutes, target: target, unit: displayUnit, reference: reference, dailyAverage: true).accessibilityIdentifier("plan.actual.week.\(item.id)")
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
        if !item.direct && !store.ledger.children(of: item.category.id).isEmpty {
            Text(displayedGoals[item.category.id].map(amount) ?? "—")
                .font(.subheadline.weight(.semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
                .frame(width: typeSize.isAccessibilitySize ? 86 : 52, alignment: .trailing)
                .frame(minHeight: 44)
                .accessibilityLabel("\(item.category.name) calculated goal \(displayUnit == .percent ? "percent" : "hours per day")")
                .accessibilityValue(displayedGoals[item.category.id].flatMap { displayUnit == .percent ? percent($0) : reference.dailyMinutes(for: $0).map { percent($0 / 60) } } ?? "No goal")
                .accessibilityHint("Sum of child goals. Expand to edit the children.")
                .accessibilityIdentifier("categories.calculated-goal.\(item.category.id)")
        } else if !item.direct {
            HStack(spacing: 0) {
                TextField("—", text: Binding(get: { plan.text[item.category.id] ?? "" }, set: { if plan.text[item.category.id] != $0 { plan.text[item.category.id] = $0; dirtyGoals.insert(item.category.id) } }))
                    .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    .focused($focusedTarget, equals: item.category.id)
                    .disabled(multiSelecting || !store.storageAvailable || (displayUnit == .time && reference.averageDayMinutes == nil)).allowsHitTesting(!multiSelecting)
                    .accessibilityLabel("\(item.category.name) goal \(displayUnit == .percent ? "percent" : "hours per day")")
                    .accessibilityIdentifier("categories.target.\(item.category.id)")
                if !(plan.text[item.category.id] ?? "").isEmpty || focusedTarget == item.category.id {
                    Text(displayUnit == .percent ? "%" : "h").font(.caption2).foregroundStyle(.secondary)
                }
            }.font(.subheadline).frame(width: typeSize.isAccessibilitySize ? 86 : 52).frame(minHeight: 44)
        } else {
            Text("—").font(.caption).foregroundStyle(.secondary)
                .frame(width: typeSize.isAccessibilitySize ? 86 : 52, alignment: .trailing)
                .accessibilityLabel("Direct time has no separate goal")
                .accessibilityIdentifier("categories.direct-goal.\(item.category.id)")
        }
    }
    private func percent(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0...2))) }
    private func load() {
        let known = Set(store.ledger.categories.filter { store.ledger.children(of: $0.id).isEmpty }.map(\.id))
        dirtyGoals.formIntersection(known)
        let values = store.ledger.editableAllocationGoals()
        let shown = displayUnit == .percent ? values : values.compactMapValues { reference.dailyMinutes(for: $0).map { $0 / 60 } }
        var refreshed = AllocationPlanDraft(shown, maximumFractionDigits: 2)
        for id in dirtyGoals { refreshed.text[id] = plan.text[id] }
        plan = refreshed
    }
    private func persistGoal(_ id: String) {
        guard dirtyGoals.contains(id) else { return }
        let text = plan.text[id] ?? ""
        var field = AllocationPlanDraft([:]); field.text[id] = text
        guard let values = field.values else { error = "Enter a valid \(displayUnit == .percent ? "percentage" : "number of daily hours") for \(store.categoryName(id))."; return }
        let percentage = values[id].flatMap { displayUnit == .percent ? $0 : reference.percentage(forDailyHours: $0) }
        if values[id] != nil, (percentage == nil || percentage! > 100 + 0.0000001) {
            error = displayUnit == .time ? "Enter hours up to the average recorded day (\(reference.averageDayMinutes.map(store.duration) ?? "no reference yet"))." : "Enter a percentage from 0 to 100."
            return
        }
        do {
            try store.updateAllocationGoal(categoryID: id, percentage: percentage.map { min(100, $0) })
            dirtyGoals.remove(id); error = nil; load()
        } catch { self.error = error.localizedDescription }
    }
    private func persistGoals() { for id in dirtyGoals.sorted() { persistGoal(id) } }
    private func endGoalEditing() { focusedTarget = nil; UIApplication.shared.dismissLedgerKeyboard(); persistGoals() }
    private func copyGoal(_ id: String) {
        guard let value = store.ledger.goalPercentage(for: id, from: reference.period) else { return }
        dirtyGoals.remove(id)
        do { try store.updateAllocationGoal(categoryID: id, percentage: value); error = nil; load() }
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
                if let category = singleSelection, store.ledger.children(of: category.id).isEmpty {
                    Button("Use 7-day goal") { copyGoal(category.id); finishSelection() }
                        .font(.caption).disabled(!reference.period.sufficient)
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
