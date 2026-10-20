import SwiftUI
import UIKit
import LedgerCore

struct CommitmentsView: View {
    @EnvironmentObject private var store: LedgerStore
    @State private var plan = AllocationPlanDraft([:])
    @State private var loaded = false
    @State private var selected = Set<String>()
    @State private var expanded = Set<String>()
    @State private var moving = false
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
                }
                Section {
                    ForEach(roots) { category in categoryRow(category, today: today, week: week) }
                } header: { Text("Categories") } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Select circles to group categories under a parent. Tap a parent’s name to see its children.")
                        Text("Actual time: today since your first log, and \(week.representedDays) of the last 7 days. Hours are estimates from your logs. A difference from a goal is not a score.")
                            .accessibilityIdentifier("plan.coverage")
                    }
                }
                CategoryMoveUndoSection()
                if let error { Text(error).foregroundStyle(.red).accessibilityIdentifier("plan.error") }
            }.listStyle(.insetGrouped).listSectionSpacing(12)
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
        .sheet(isPresented: $moving) { CategoryMoveView(ids: moveSelection) { selected = [] } }
        .sheet(isPresented: $managingCategories) { GroupManagerView() }
        .confirmationDialog("Save your goal changes before grouping?", isPresented: $confirmGrouping, titleVisibility: .visible) {
            if canSave { Button("Save and group") { if save() { moving = true } } }
            Button("Discard changes and group", role: .destructive) { load(); moving = true }
            Button("Keep editing", role: .cancel) {}
        }
    }

    private func categoryRow(_ category: LedgerCategory, today: AllocationPeriod, week: AllocationPeriod) -> some View {
        let children = store.ledger.children(of: category.id)
        let isExpanded = expanded.contains(category.id)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button {
                    if !selected.insert(category.id).inserted { selected.remove(category.id) }
                } label: {
                    Image(systemName: selected.contains(category.id) ? "checkmark.circle.fill" : "circle")
                        .font(.title3).frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                }.buttonStyle(.borderless)
                    .accessibilityLabel("Select \(category.name) for grouping")
                    .accessibilityValue(selected.contains(category.id) ? "Selected" : "Not selected")
                    .accessibilityAddTraits(selected.contains(category.id) ? .isSelected : [])
                    .accessibilityIdentifier("plan.select.\(category.id)")
                if children.isEmpty {
                    Text(category.name).font(.headline).frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Button {
                        if !expanded.insert(category.id).inserted { expanded.remove(category.id) }
                    } label: {
                        HStack(spacing: 6) {
                            Text(category.name).font(.headline)
                            Spacer(minLength: 2)
                            Image(systemName: isExpanded ? "chevron.down" : "chevron.right").font(.caption)
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain)
                        .accessibilityLabel("\(isExpanded ? "Collapse" : "Expand") \(category.name)")
                        .accessibilityValue("\(children.count) subcategories")
                        .accessibilityIdentifier("plan.children.\(category.id)")
                }
                TextField("—", text: Binding(get: { plan.text[category.id] ?? "" }, set: { plan.text[category.id] = $0 }))
                    .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 60)
                    .focused($focusedTarget, equals: category.id)
                    .accessibilityLabel("\(category.name) goal percent").accessibilityIdentifier("categories.target.\(category.id)")
                Text("%").foregroundStyle(.secondary)
            }
            AllocationValues(today: today, week: week, todayMinutes: today.total(for: category.id, ledger: store.ledger), weekMinutes: week.total(for: category.id, ledger: store.ledger), target: plan.values?[category.id])
            if isExpanded && !children.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Directly assigned to \(category.name)").font(.caption.bold())
                    AllocationValues(today: today, week: week, todayMinutes: today.directMinutes[category.id, default: 0], weekMinutes: week.directMinutes[category.id, default: 0], target: nil)
                    ForEach(children) { child in AllocationCategoryRow(category: child, today: today, week: week) }
                }.padding(.vertical, 4).padding(.leading, 16)
            }
            Button("Use remaining") { plan.useRemaining(for: category.id) }
                .font(.caption).buttonStyle(.borderless).accessibilityIdentifier("plan.remaining.\(category.id)")
        }.padding(.vertical, 4)
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
        if plan.isDirty { confirmGrouping = true } else { moving = true }
    }
}
