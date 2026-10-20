import SwiftUI
import UIKit
import LedgerCore

struct CommitmentsView: View {
    @EnvironmentObject private var store: LedgerStore
    @State private var plan = AllocationPlanDraft([:])
    @State private var loaded = false
    @State private var pinned = Set<String>()
    @State private var expanded = Set<String>()
    @State private var organizing = false
    @State private var confirmOrganize = false
    @State private var creating = false
    @State private var name = ""
    @State private var error: String?
    @FocusState private var focusedTarget: String?

    private var roots: [LedgerCategory] { store.ledger.children(of: nil) }
    private var areas: [LedgerCategory] {
        roots.filter { plan.text[$0.id] != nil || pinned.contains($0.id) || !store.ledger.children(of: $0.id).isEmpty }
    }
    private var loose: [LedgerCategory] { roots.filter { root in !areas.contains { $0.id == root.id } } }
    private var stale: Bool { !(plan.values?.keys.allSatisfy { id in roots.contains { $0.id == id } } ?? true) }
    private var canSave: Bool { plan.isComplete && plan.isDirty && !stale && store.storageAvailable }

    var body: some View {
        TimelineView(.periodic(from: Date(), by: 60)) { context in
            let today = store.ledger.allocation(on: context.date, now: context.date)
            let week = store.ledger.rollingAllocation(now: context.date)
            List {
                Section {
                    Text("How do you want to divide your time?").font(.headline)
                    Text("Group detailed categories into a few broad life areas, then give each a share. Choose as many areas as you need.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    HStack {
                        Text("Total").bold(); Spacer()
                        Text(plan.total.map { "\(percent($0))% / 100%" } ?? "Check percentages")
                            .bold().monospacedDigit().accessibilityIdentifier("plan.total")
                    }
                    if let total = plan.total {
                        Text(abs(total - 100) < 0.0000001 ? "100% assigned" : total > 100 ? "\(percent(total - 100))% over — reduce a goal" : "\(percent(100 - total))% left to assign")
                            .foregroundStyle(total > 100 ? Color.red : Color.secondary)
                            .accessibilityIdentifier("plan.balance")
                    } else {
                        Text("Enter percentages between 0 and 100.").foregroundStyle(.red)
                    }
                    if stale {
                        Text("Categories changed while you were editing. Reload the saved plan to continue.").font(.caption).foregroundStyle(.red)
                        Button("Reload saved plan") { load() }.accessibilityIdentifier("plan.reload")
                    }
                    Button("Save plan") { save() }.disabled(!canSave).accessibilityIdentifier("categories.save-targets")
                } footer: {
                    Text("Changing one goal leaves the others unchanged. Save when the total is exactly 100%. Earlier plans are kept.")
                }
                Section {
                    ForEach(areas) { category in areaRow(category, today: today, week: week) }
                    Menu {
                        ForEach(loose) { category in
                            Button(category.name) { pinned.insert(category.id) }
                        }
                        Button("Create life area", systemImage: "plus") { name = ""; creating = true }
                    } label: { Label("Add life area", systemImage: "plus") }.accessibilityIdentifier("plan.add-area")
                } header: { Text("Life areas") } footer: {
                    Text("Actual time: today since your first log, and \(week.representedDays) of the last 7 days. Hours are estimates from your logs. A difference from a goal is not a score.")
                        .accessibilityIdentifier("plan.coverage")
                }
                if !loose.isEmpty {
                    Section {
                        DisclosureGroup("Categories to organize (\(loose.count))") {
                            ForEach(loose) { category in
                                HStack {
                                    Text(category.name); Spacer()
                                    Button("Use as life area") { pinned.insert(category.id) }.font(.caption).buttonStyle(.borderless)
                                }
                            }
                            Button("Group categories into life areas") { openOrganizer() }
                        }.accessibilityIdentifier("plan.loose-categories")
                    } footer: {
                        Text("These categories are still tracked. Use Organize to select several and group them under a life area.")
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
                Button("Organize", systemImage: "folder.badge.plus") { openOrganizer() }.accessibilityIdentifier("plan.organize")
            }
        }
        .onAppear { if !loaded { load(); loaded = true } }
        .onChange(of: store.ledger.currentBudget()?.id) { _, _ in if !plan.isDirty { load() } }
        .onChange(of: roots.map(\.id)) { _, _ in if !plan.isDirty { load() } }
        .onChange(of: focusedTarget) { _, id in
            guard id != nil else { return }
            DispatchQueue.main.async {
                UIApplication.shared.sendAction(#selector(UIResponderStandardEditActions.selectAll(_:)), to: nil, from: nil, for: nil)
            }
        }
        .sheet(isPresented: $organizing) { GroupManagerView(selecting: true) }
        .confirmationDialog("Save your goal changes before organizing?", isPresented: $confirmOrganize, titleVisibility: .visible) {
            if canSave { Button("Save and organize") { if save() { organizing = true } } }
            Button("Discard changes and organize", role: .destructive) { load(); organizing = true }
            Button("Keep editing", role: .cancel) {}
        }
        .alert("New life area", isPresented: $creating) {
            TextField("Name", text: $name).accessibilityIdentifier("plan.area-name")
            Button("Create") {
                creating = false
                do { let id = try store.saveCategory(id: nil, name: name); pinned.insert(id) }
                catch { self.error = error.localizedDescription }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func areaRow(_ category: LedgerCategory, today: AllocationPeriod, week: AllocationPeriod) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(category.name).font(.headline)
                Spacer(minLength: 4)
                TextField("—", text: Binding(get: { plan.text[category.id] ?? "" }, set: { plan.text[category.id] = $0 }))
                    .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 68)
                    .focused($focusedTarget, equals: category.id)
                    .accessibilityLabel("\(category.name) goal percent").accessibilityIdentifier("categories.target.\(category.id)")
                Text("%").foregroundStyle(.secondary)
            }
            AllocationValues(today: today, week: week, todayMinutes: today.total(for: category.id, ledger: store.ledger), weekMinutes: week.total(for: category.id, ledger: store.ledger), target: plan.values?[category.id])
            let children = store.ledger.children(of: category.id)
            if !children.isEmpty {
                DisclosureGroup(isExpanded: Binding(get: { expanded.contains(category.id) }, set: { if $0 { expanded.insert(category.id) } else { expanded.remove(category.id) } })) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Directly assigned to \(category.name)").font(.caption.bold())
                        AllocationValues(today: today, week: week, todayMinutes: today.directMinutes[category.id, default: 0], weekMinutes: week.directMinutes[category.id, default: 0], target: nil)
                        ForEach(children) { child in AllocationCategoryRow(category: child, today: today, week: week) }
                    }.padding(.vertical, 4)
                } label: { Text("\(children.count) subcategories").font(.caption) }
                .accessibilityIdentifier("plan.children.\(category.id)")
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
    private func openOrganizer() {
        UIApplication.shared.dismissLedgerKeyboard()
        if plan.isDirty { confirmOrganize = true } else { organizing = true }
    }
}
