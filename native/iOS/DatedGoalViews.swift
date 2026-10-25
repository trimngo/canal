import SwiftUI
import LedgerCore

struct TaskPlanningView: View {
    @EnvironmentObject private var store: LedgerStore
    @Environment(\.dismiss) private var dismiss
    let capture: Capture
    @State private var hours: String
    @State private var hasDueDate: Bool
    @State private var dueDate: Date
    @State private var hasStart: Bool
    @State private var startDate: Date
    @State private var error: String?
    @State private var loggedMinutes: Double?
    init(capture: Capture) {
        self.capture = capture
        _hours = State(initialValue: capture.workPlan.map { ($0.estimatedMinutes / 60).formatted(.number.grouping(.never).precision(.fractionLength(0...2))) } ?? "")
        _hasDueDate = State(initialValue: capture.timing?.kind == .dueDate)
        _dueDate = State(initialValue: capture.timing?.dueAt ?? Calendar.current.date(byAdding: .day, value: 7, to: Date())!)
        _hasStart = State(initialValue: capture.workPlan?.startDate != nil)
        _startDate = State(initialValue: capture.workPlan?.startDate ?? capture.createdAt)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    InlineEntryText(text: store.ledger.captures.first { $0.id == capture.id }?.text ?? capture.text, identifier: "task-planning.title") {
                        try store.updateCaptureText(capture, text: $0)
                    }
                    if let loggedMinutes { Text("Time logged: \(store.duration(loggedMinutes))").font(.subheadline).accessibilityIdentifier("task-planning.logged") }
                }
                Section {
                    HStack { Text("Estimated work (hours)"); TextField("Optional", text: $hours).keyboardType(.decimalPad).multilineTextAlignment(.trailing).accessibilityIdentifier("task-planning.hours") }
                    Toggle("Due date", isOn: $hasDueDate).accessibilityIdentifier("task-planning.has-due-date")
                    if hasDueDate { DatePicker("Due", selection: $dueDate).accessibilityIdentifier("task-planning.due") }
                    Toggle("Set a start date", isOn: $hasStart).accessibilityIdentifier("task-planning.has-start")
                    if hasStart { DatePicker("Start", selection: $startDate).accessibilityIdentifier("task-planning.start") }
                } footer: {
                    Text("A due date and work estimate put this task in Focus. A blank start uses its creation date. Pace follows workdays; all linked logs count, including work outside the day window.")
                }
                InlineCaptureNotes(capture: capture, identifier: "task-planning.notes", initiallyExpanded: true)
                if let error { Text(error).foregroundStyle(.red).accessibilityIdentifier("task-planning.error") }
            }.scrollDismissesKeyboard(.interactively).ledgerInputDismissal()
                .navigationTitle("Task details").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).disabled(!store.storageAvailable).accessibilityIdentifier("task-planning.save") }
                }
                .task {
                    let ledger = store.ledger
                    loggedMinutes = await Task.detached(priority: .userInitiated) { ledger.taskLoggedMinutes()[capture.id, default: 0] }.value
                }
        }
    }
    private func save() {
        do {
            let text = hours.trimmingCharacters(in: .whitespacesAndNewlines)
            let minutes = text.isEmpty ? nil : Double(text.replacingOccurrences(of: ",", with: ".")).map { $0 * 60 }
            if !text.isEmpty, minutes == nil { throw TaskPlanError.invalidEstimate }
            if minutes != nil, hasDueDate, dueDate <= (hasStart ? startDate : capture.createdAt) {
                error = "Choose a due date after the task’s start (or creation) date."; return
            }
            let timing: CaptureTiming? = hasDueDate ? .due(dueDate) : (capture.timing?.kind == .dueDate ? .noDate : capture.timing)
            try store.saveTaskPlanning(capture, timing: timing, estimatedMinutes: minutes, startDate: hasStart ? startDate : nil)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

struct LogTaskPicker: View {
    @EnvironmentObject private var store: LedgerStore
    @Binding var goalID: String?
    @Binding var categoryIDs: [String]
    @State private var choosing = false
    @State private var search = ""
    var body: some View {
        Button { choosing = true } label: {
            HStack {
                Label("Task", systemImage: "checklist")
                Spacer()
                Text(goalID.flatMap { id in store.ledger.captures.first { $0.id == id }?.text } ?? (goalID == nil ? "None" : "Saved task"))
                    .lineLimit(1).foregroundStyle(.secondary)
                Image(systemName: "chevron.up.chevron.down").font(.caption)
            }
        }.font(.subheadline).accessibilityIdentifier("log-review.task")
        .sheet(isPresented: $choosing) {
            NavigationStack {
                List {
                    Button("No task") { choose(nil) }
                    ForEach(store.ledger.captures.filter { $0.deletedAt == nil && (search.isEmpty || $0.text.localizedCaseInsensitiveContains(search)) }.sorted { $0.createdAt > $1.createdAt }) { task in
                        Button { choose(task.id) } label: {
                            HStack { Text(task.text); Spacer(); if goalID == task.id { Image(systemName: "checkmark") } }
                        }.accessibilityIdentifier("log-review.task-option.\(task.id)")
                    }
                }.searchable(text: $search, prompt: "Find an Inbox task")
                    .navigationTitle("Link to task").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { choosing = false } } }
            }
        }
    }
    private func choose(_ id: String?) {
        goalID = id; choosing = false
        guard let task = store.ledger.captures.first(where: { $0.id == id }) else { return }
        for category in store.ledger.categoryIDs(for: task) {
            let family = Set([category] + store.ledger.descendants(of: category).map(\.id))
            if Set(categoryIDs).isDisjoint(with: family) {
                let conflicts = Set(store.ledger.categoryConflicts(category, with: categoryIDs))
                categoryIDs.removeAll { conflicts.contains($0) }; categoryIDs.append(category)
            }
        }
    }
}

struct PacedProgressBar: View {
    let actual: Double
    let expected: Double
    var tint: Color = .teal
    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.16))
                Capsule().fill(tint).frame(width: proxy.size.width * min(1, max(0, actual)))
                Rectangle().fill(Color.primary).frame(width: 2, height: 14)
                    .offset(x: min(max(0, proxy.size.width - 2), proxy.size.width * min(1, max(0, expected))))
            }.frame(height: 8)
        }.frame(height: 14)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Progress and expected pace")
            .accessibilityValue("\(Int(actual * 100)) percent complete; \(Int(expected * 100)) percent expected by now")
            .accessibilityIdentifier("focus.pace-bar")
    }
}

struct FocusTaskProgressView: View {
    @EnvironmentObject private var store: LedgerStore
    let row: DatedGoalProgress
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            PacedProgressBar(actual: row.fraction, expected: row.expectedMinutes / row.goal.targetMinutes, tint: row.isMet ? .green : .teal)
            HStack {
                Text("\(store.duration(row.actualMinutes)) / \(store.duration(row.goal.targetMinutes))")
                Spacer()
                Text(row.isMet ? "Work estimate reached" : "\(store.duration(row.remainingMinutes)) left")
            }.font(.caption)
            Text(pace).font(.caption2).foregroundStyle(.secondary)
        }.accessibilityIdentifier("focus.progress.\(row.id)")
    }
    private var pace: String {
        if row.isMet { return "Work estimate reached" }
        if row.goal.deadline <= Date() { return "Overdue · \(store.duration(row.remainingMinutes)) remaining" }
        let status = abs(row.differenceMinutes) < 1 ? "On pace" : "\(store.duration(abs(row.differenceMinutes))) \(row.differenceMinutes > 0 ? "ahead" : "behind")"
        return row.dailyMinutesNeeded.map { "\(status) · \(store.duration($0))/workday needed" } ?? status
    }
}

struct CommitmentsView: View {
    @EnvironmentObject private var store: LedgerStore
    @State private var editing = false
    @State private var editingWindow = false
    @State private var selectedCategory: CategoryDetailRequest?
    @State private var editingTask: Capture?
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
                    Section("Focus") { ForEach(standalone) { datedProgress($0, now: clock.date) } }
                }
                if categoryIDs.isEmpty && progress.isEmpty {
                    Text("Favorite a category target, or give an Inbox task a due date and work estimate.").foregroundStyle(.secondary)
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
        .sheet(item: $editingTask) { TaskPlanningView(capture: $0) }
        .sheet(item: $selectedCategory) { CategoryDetailView(request: $0) }
        .sheet(isPresented: $editingWindow) { NavigationStack { DayWindowSettingsView() } }
        .task(id: calculationID) {
            let ledger = store.ledger, now = reportDate(Date())
            let work = Task.detached(priority: .userInitiated) {
                (ledger.focusTaskProgress(now: now), ledger.dailyGoals(now: now, favoritesOnly: true), ledger.allocation(on: now, now: now))
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
        Button {
            editingTask = store.ledger.captures.first { $0.id == row.id }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(row.goal.name).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                    Spacer(minLength: 8)
                    Text(row.goal.deadline, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day()).font(.caption).foregroundStyle(.secondary)
                }
                FocusTaskProgressView(row: row)
            }.padding(.vertical, 4).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier("focus-task.progress.\(row.id)")
    }
}
