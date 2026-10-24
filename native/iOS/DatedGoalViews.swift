import SwiftUI
import LedgerCore

struct DatedGoalEditorView: View {
    @EnvironmentObject private var store: LedgerStore
    @Environment(\.dismiss) private var dismiss
    let goal: DatedGoal?
    @State private var name: String
    @State private var hours: String
    @State private var categoryID: String?
    @State private var startDate: Date
    @State private var deadline: Date
    @State private var error: String?
    @State private var deleting = false
    let didSave: () -> Void

    init(goal: DatedGoal? = nil, categoryID: String? = nil, didSave: @escaping () -> Void = {}) {
        self.goal = goal; self.didSave = didSave
        _name = State(initialValue: goal?.name ?? "")
        _hours = State(initialValue: goal.map { ($0.targetMinutes / 60).formatted(.number.grouping(.never).precision(.fractionLength(0...2))) } ?? "")
        _categoryID = State(initialValue: goal?.categoryID ?? categoryID)
        let start = goal?.startDate ?? Date()
        _startDate = State(initialValue: start)
        _deadline = State(initialValue: goal?.deadline ?? Calendar.current.date(byAdding: .day, value: 7, to: start)!)
    }
    private var minutes: Double? { Double(hours.replacingOccurrences(of: ",", with: ".")).map { $0 * 60 } }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Goal name", text: $name).accessibilityIdentifier("dated-goal.name")
                    HStack { Text("Hours"); TextField("4", text: $hours).keyboardType(.decimalPad).multilineTextAlignment(.trailing).accessibilityIdentifier("dated-goal.hours") }
                    Picker("Category", selection: $categoryID) {
                        Text("Standalone goal").tag(nil as String?)
                        ForEach(store.ledger.orderedCategories) { Text(store.ledger.categoryPath($0.id)).tag(Optional($0.id)) }
                    }.accessibilityIdentifier("dated-goal.category")
                    DatePicker("Start", selection: $startDate).accessibilityIdentifier("dated-goal.start")
                    DatePicker("Deadline", selection: $deadline).accessibilityIdentifier("dated-goal.deadline")
                } footer: { Text("Progress comes from logs assigned to this goal. Pace uses Monday–Friday and your day window; work logged on any day counts.") }
                if let error { Text(error).foregroundStyle(.red).accessibilityIdentifier("dated-goal.error") }
                if goal != nil {
                    Button("Delete goal", role: .destructive) { deleting = true }.accessibilityIdentifier("dated-goal.delete")
                }
            }.ledgerInputDismissal()
                .onAppear {
                    if let categoryID, !store.ledger.categories.contains(where: { $0.id == categoryID }) { self.categoryID = nil }
                }
                .navigationTitle(goal == nil ? "Add goal" : "Edit goal").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            UIApplication.shared.dismissLedgerKeyboard()
                            do {
                                guard let minutes else { throw DatedGoalError.invalidGoal }
                                try store.saveDatedGoal(id: goal?.id, name: name, categoryID: categoryID, targetMinutes: minutes, startDate: startDate, deadline: deadline)
                                didSave(); dismiss()
                            } catch { self.error = error.localizedDescription }
                        }.disabled(!store.storageAvailable).accessibilityIdentifier("dated-goal.save")
                    }
                }
                .confirmationDialog("Delete this goal?", isPresented: $deleting, titleVisibility: .visible) {
                    Button("Delete goal", role: .destructive) {
                        do { if let goal { try store.deleteDatedGoal(goal.id) }; didSave(); dismiss() }
                        catch { self.error = error.localizedDescription }
                    }
                } message: { Text("Your logs and category totals are kept.") }
        }
    }
}

/// A goal assignment augments the category selection; it never changes capture.
struct LogGoalPicker: View {
    @EnvironmentObject private var store: LedgerStore
    @Binding var goalID: String?
    @Binding var categoryIDs: [String]
    var body: some View {
        if !store.ledger.activeDatedGoals.isEmpty || goalID != nil {
            Picker("Goal", selection: Binding(get: { goalID }, set: choose)) {
                Text("No goal").tag(nil as String?)
                if let goalID, !store.ledger.activeDatedGoals.contains(where: { $0.id == goalID }) {
                    Text((store.ledger.datedGoals ?? []).first(where: { $0.id == goalID }).map { $0.name + " (deleted)" } ?? "Saved goal")
                        .tag(Optional(goalID))
                }
                ForEach(store.ledger.activeDatedGoals) { Text($0.name).tag(Optional($0.id)) }
            }.pickerStyle(.menu).font(.subheadline).accessibilityIdentifier("log-review.goal")
        }
    }
    private func choose(_ id: String?) {
        goalID = id
        guard let goal = store.ledger.activeDatedGoals.first(where: { $0.id == id }),
              let category = goal.categoryID, store.ledger.categories.contains(where: { $0.id == category }) else { return }
        let family = Set([category] + store.ledger.descendants(of: category).map(\.id))
        guard Set(categoryIDs).isDisjoint(with: family) else { return }
        let conflicts = Set(store.ledger.categoryConflicts(category, with: categoryIDs))
        categoryIDs.removeAll { conflicts.contains($0) }; categoryIDs.append(category)
    }
}

struct CommitmentsView: View {
    @EnvironmentObject private var store: LedgerStore
    @State private var editing = false
    @State private var editingWindow = false
    @State private var selectedCategory: CategoryDetailRequest?
    @State private var editingGoal: DatedGoal?
    @State private var progress: [DatedGoalProgress] = []
    @State private var daily: DailyGoalsReport?
    @State private var today = AllocationPeriod()
    @State private var calculationID = UUID()
    private var categoryIDs: [String] {
        let ids = Set((daily?.commitments.map(\.id) ?? []) + progress.compactMap { $0.goal.categoryID })
        return store.ledger.orderedCategories.map(\.id).filter(ids.contains)
    }
    var body: some View {
        TimelineView(.periodic(from: Date(), by: 60)) { clock in
            List {
                if let daily {
                    Section { DailyGoalCapacityView(report: daily) { editingWindow = true }.padding(.vertical, 4) }
                } else {
                    Button("Set day window") { editingWindow = true }
                }
                ForEach(categoryIDs, id: \.self) { id in
                    Section {
                        if let target = daily?.commitments.first(where: { $0.id == id }) { categoryProgress(target) }
                        ForEach(progress.filter { $0.goal.categoryID == id }) { row in
                            datedProgress(row, now: clock.date).padding(.leading, 12)
                        }
                    } header: {
                        Button {
                            selectedCategory = CategoryDetailRequest(id: id, name: store.ledger.categories.first { $0.id == id }?.name ?? "Category")
                        } label: {
                            HStack { Text(store.ledger.categoryPath(id)); Spacer(); Image(systemName: "chevron.right") }.contentShape(Rectangle())
                        }.textCase(nil).accessibilityIdentifier("commitments.category.\(id)")
                    }
                }
                let standalone = progress.filter { row in row.goal.categoryID == nil || !store.ledger.categories.contains(where: { $0.id == row.goal.categoryID }) }
                if !standalone.isEmpty {
                    Section("Goals") { ForEach(standalone) { datedProgress($0, now: clock.date) } }
                }
                if categoryIDs.isEmpty && progress.isEmpty {
                    Text("Favorite a category target or add a goal in Edit goals.").foregroundStyle(.secondary)
                    Button("Choose favorites") { editing = true }
                }
            }.listStyle(.plain)
                .onChange(of: Int(clock.date.timeIntervalSince1970 / 60)) { _, _ in calculationID = UUID() }
        }
        .navigationTitle("Commitments").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Edit goals") { editing = true }.accessibilityIdentifier("goals.edit") } }
        .sheet(isPresented: $editing) {
            NavigationStack { GoalEditorView().toolbar { ToolbarItem(placement: .topBarLeading) { Button("Close") { editing = false } } } }
        }
        .sheet(item: $editingGoal) { DatedGoalEditorView(goal: $0) }
        .sheet(item: $selectedCategory) { CategoryDetailView(request: $0) }
        .sheet(isPresented: $editingWindow) { NavigationStack { DayWindowSettingsView() } }
        .task(id: calculationID) {
            let ledger = store.ledger, now = reportDate(Date())
            let work = Task.detached(priority: .userInitiated) {
                (ledger.datedGoalProgress(now: now), ledger.dailyGoals(now: now, favoritesOnly: true), ledger.allocation(on: now, now: now))
            }
            let result = await withTaskCancellationHandler(operation: { await work.value }, onCancel: { work.cancel() })
            if !Task.isCancelled { progress = result.0; daily = result.1; today = result.2 }
        }
        .onChange(of: store.ledger) { _, _ in calculationID = UUID() }
    }
    private func reportDate(_ date: Date) -> Date {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("--ui-daily-goals") }) {
            return ISO8601DateFormatter().date(from: "2026-10-22T17:30:00Z")!
        }
        #endif
        return date
    }
    @ViewBuilder private func categoryProgress(_ row: DailyGoalProgress) -> some View {
        if let daily {
            DailyCategoryGoalRow(goal: row, report: daily, showsName: false,
                unreviewedMinutes: today.unreviewed(for: row.id, ledger: store.ledger)) {
                    selectedCategory = CategoryDetailRequest(id: row.id, name: row.category.name)
                }
        }
    }
    private func datedProgress(_ row: DatedGoalProgress, now: Date) -> some View {
        Button { editingGoal = row.goal } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Label(row.goal.name, systemImage: "target").font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                    Spacer(minLength: 8)
                    Text(row.goal.deadline, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day()).font(.caption).foregroundStyle(.secondary)
                }
                ProgressView(value: row.fraction).tint(row.isMet ? .green : .teal)
                HStack {
                    Text("\(store.duration(row.actualMinutes)) of \(store.duration(row.goal.targetMinutes))")
                    Spacer()
                    Text(row.isMet ? "Met" : "\(store.duration(row.remainingMinutes)) left")
                }.font(.caption).foregroundStyle(.primary)
                Text(paceLabel(row, now: now)).font(.caption2).foregroundStyle(row.differenceMinutes < -1 ? Color.orange : Color.secondary)
            }.padding(.vertical, 4).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier("dated-goals.progress.\(row.id)")
    }
    private func paceLabel(_ row: DatedGoalProgress, now: Date) -> String {
        if row.isMet { return "Goal met" }
        if row.goal.deadline <= now { return "Overdue · \(store.duration(row.remainingMinutes)) remaining" }
        let status = abs(row.differenceMinutes) < 1 ? "On pace" : "\(store.duration(abs(row.differenceMinutes))) \(row.differenceMinutes > 0 ? "ahead" : "behind")"
        if let needed = row.dailyMinutesNeeded { return "\(status) · \(store.duration(needed))/workday needed" }
        return "\(status) · No workdays remain before the deadline"
    }
}
