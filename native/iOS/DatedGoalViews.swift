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
        if !store.ledger.activeDatedGoals.isEmpty {
            Picker("Goal", selection: Binding(get: { goalID }, set: choose)) {
                Text("No goal").tag(nil as String?)
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
    @State private var editingGoal: DatedGoal?
    @State private var progress: [DatedGoalProgress] = []
    @State private var calculationID = UUID()
    var body: some View {
        TimelineView(.periodic(from: Date(), by: 60)) { clock in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let window = store.ledger.goalDayWindow(on: clock.date, now: clock.date) {
                        Text("\(store.duration(window.remainingMinutes)) left today").font(.title2.bold())
                    }
                    let unfinished = progress.filter { !$0.isMet }
                    let needed = unfinished.compactMap(\.dailyMinutesNeeded).reduce(0, +)
                    if needed > 0 {
                        Text("\(store.duration(needed))/workday needed across your goals")
                            .font(.subheadline).foregroundStyle(.secondary).accessibilityIdentifier("dated-goals.daily-demand")
                    }
                    if store.ledger.activeDatedGoals.isEmpty {
                        ContentUnavailableView {
                            Label("Add a goal", systemImage: "target")
                        } description: { Text("Set hours and a deadline in Edit goals. Logs will track your progress.") }
                        actions: { Button("Edit goals") { editing = true } }
                    }
                    ForEach(progress) { row in
                        Button { editingGoal = row.goal } label: {
                            VStack(alignment: .leading, spacing: 7) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(row.goal.name).font(.headline).foregroundStyle(.primary)
                                    Spacer(minLength: 8)
                                    Text(row.goal.deadline, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                if let category = row.goal.categoryID, store.ledger.categories.contains(where: { $0.id == category }) {
                                    Text(store.ledger.categoryPath(category)).font(.caption).foregroundStyle(.secondary)
                                }
                                ProgressView(value: row.fraction).tint(row.isMet ? .green : .teal)
                                HStack {
                                    Text("\(store.duration(row.actualMinutes)) of \(store.duration(row.goal.targetMinutes))")
                                    Spacer()
                                    Text(row.isMet ? "Met" : "\(store.duration(row.remainingMinutes)) left")
                                }.font(.subheadline).foregroundStyle(.primary)
                                Text(paceLabel(row, now: clock.date)).font(.caption)
                                    .foregroundStyle(row.differenceMinutes < -1 ? Color.orange : Color.secondary)
                            }.padding(.vertical, 8).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityIdentifier("dated-goals.progress.\(row.id)")
                        Divider()
                    }
                    NavigationLink("Category targets") { CategoryTargetsTodayView() }
                        .accessibilityIdentifier("dated-goals.category-targets")
                }.padding(20)
            }.onChange(of: Int(clock.date.timeIntervalSince1970 / 60)) { _, _ in calculationID = UUID() }
        }
        .navigationTitle("Commitments").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Edit goals") { editing = true }.accessibilityIdentifier("goals.edit") } }
        .sheet(isPresented: $editing) {
            NavigationStack { GoalEditorView().toolbar { ToolbarItem(placement: .topBarLeading) { Button("Close") { editing = false } } } }
        }
        .sheet(item: $editingGoal) { DatedGoalEditorView(goal: $0) }
        .task(id: calculationID) {
            let ledger = store.ledger
            let job = Task.detached(priority: .userInitiated) { ledger.datedGoalProgress() }
            let rows = await withTaskCancellationHandler(operation: { await job.value }, onCancel: { job.cancel() })
            if !Task.isCancelled { progress = rows }
        }
        .onChange(of: store.ledger) { _, _ in calculationID = UUID() }
    }
    private func paceLabel(_ row: DatedGoalProgress, now: Date) -> String {
        if row.isMet { return "Goal met" }
        if row.goal.deadline <= now { return "Overdue · \(store.duration(row.remainingMinutes)) remaining" }
        let status = abs(row.differenceMinutes) < 1 ? "On pace" : "\(store.duration(abs(row.differenceMinutes))) \(row.differenceMinutes > 0 ? "ahead" : "behind")"
        if let needed = row.dailyMinutesNeeded { return "\(status) · \(store.duration(needed))/workday needed" }
        return "\(status) · No workdays remain before the deadline"
    }
}
