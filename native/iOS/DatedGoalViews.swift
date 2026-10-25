import SwiftUI
import UIKit
import LedgerCore

struct TaskPlanningView: View {
    private enum TimingChoice: String, CaseIterable { case automatic = "Automatic", noDate = "No date", asap = "ASAP", due = "Due date" }
    @EnvironmentObject private var store: LedgerStore
    @Environment(\.dismiss) private var dismiss
    let capture: Capture
    @State private var hours: String
    @State private var timingChoice: TimingChoice
    @State private var dueDate: Date
    @State private var hasStart: Bool
    @State private var startDate: Date
    @State private var error: String?
    @State private var loggedMinutes: Double?
    @State private var ranking = false
    @State private var snoozing = false
    @FocusState private var hoursFocused: Bool
    init(capture: Capture) {
        self.capture = capture
        _hours = State(initialValue: capture.workPlan?.estimatedMinutes.map { ($0 / 60).formatted(.number.grouping(.never).precision(.fractionLength(0...2))) } ?? "")
        _timingChoice = State(initialValue: capture.timing.map { $0.kind == .dueDate ? .due : $0.kind == .asap ? .asap : .noDate } ?? .automatic)
        _dueDate = State(initialValue: capture.timing?.dueAt ?? Calendar.current.date(byAdding: .day, value: 7, to: Date())!)
        _hasStart = State(initialValue: capture.workPlan?.startDate != nil)
        _startDate = State(initialValue: capture.workPlan?.startDate ?? capture.createdAt)
    }
    private var current: Capture { store.ledger.captures.first { $0.id == capture.id } ?? capture }
    private var listName: String {
        if current.isDone { return "Completed" }
        if current.isReference == true { return "Reference" }
        if current.isSnoozed(at: Date()) { return "Snoozed" }
        if store.inbox.ranked.contains(where: { $0.id == capture.id }) { return "Top priorities" }
        if store.inbox.backlog.contains(where: { $0.id == capture.id }) { return "Backlog" }
        if store.inbox.inProgress.contains(where: { $0.id == capture.id }) { return "In progress" }
        return "New ideas"
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    InlineEntryText(text: current.text, identifier: "task-planning.title", displayLineLimit: nil) {
                        try store.updateCaptureText(capture, text: $0)
                    }
                    if let loggedMinutes { Text("Time logged: \(store.duration(loggedMinutes))").font(.subheadline).accessibilityIdentifier("task-planning.logged") }
                }
                Section("Categories") {
                    CaptureCategoryButton(capture: current, identifier: "task-planning.categories", showsAllCategories: true)
                    if let suggestion = current.categorySuggestion {
                        Text("Suggested · " + suggestion.reason).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section("Notes") {
                    InlineEntryText(text: current.notes ?? "", identifier: "task-planning.notes", allowEmpty: true, displayLineLimit: nil) {
                        try store.updateCapture(current, text: current.text, notes: $0)
                    }
                }
                Section {
                    HStack { Text("Estimated work (hours)"); TextField("Optional", text: $hours).keyboardType(.decimalPad).multilineTextAlignment(.trailing).focused($hoursFocused).accessibilityIdentifier("task-planning.hours") }
                    Picker("Timing", selection: $timingChoice) {
                        ForEach(TimingChoice.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }.accessibilityIdentifier("task-planning.timing")
                    if timingChoice == .due { DatePicker("Due", selection: $dueDate).accessibilityIdentifier("task-planning.due") }
                    Toggle("Set a start date", isOn: $hasStart).accessibilityIdentifier("task-planning.has-start")
                    if hasStart { DatePicker("Start", selection: $startDate).accessibilityIdentifier("task-planning.start") }
                } footer: {
                    Text("A due date and work estimate put this task in Focus. Without a start override, pacing starts when the task was created inside your daily window, or at the next opening. Every day counts, including weekends. All linked logs count at any time.")
                }
                Section("Details") {
                    LabeledContent("List", value: listName)
                    LabeledContent("Created", value: current.createdAt.formatted(date: .abbreviated, time: .shortened))
                    if (store.ledger.reminderImports ?? []).contains(where: { $0.captureID == capture.id }) { Text("Imported from Reminders") }
                    if let rank = store.inbox.ranked.firstIndex(where: { $0.id == capture.id }) { LabeledContent("Overall priority", value: "#\(rank + 1)") }
                    if let due = current.snoozeReturnDate(), current.isSnoozed(at: Date()) { LabeledContent("Returns", value: due.formatted(date: .abbreviated, time: .shortened)) }
                    if let urgency = store.ledger.urgency(for: current), urgency.isSuggested {
                        Text("Suggested ASAP · " + urgency.reason.rawValue).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section {
                    Button(current.isDone ? "Reopen idea" : "Mark done") { perform { try store.setCaptureDone(current, done: !current.isDone) } }
                        .accessibilityIdentifier("task-planning.complete")
                    if !current.isDone {
                        Button(current.isReference == true ? "Move to New Ideas" : "Move to Reference") {
                            perform { try store.setCaptureReference(current, reference: current.isReference != true) }
                        }.accessibilityIdentifier("task-planning.reference")
                        if current.isReference != true {
                            Button(current.isSnoozed(at: Date()) ? "Change snooze" : "Snooze") { snoozing = true }
                                .accessibilityIdentifier("task-planning.snooze")
                            if current.isSnoozed(at: Date()) {
                                Button("Bring back now") { perform { try store.bringBackCapture(current) } }
                                    .accessibilityIdentifier("task-planning.bring-back")
                            } else {
                                Button("Re-rank this idea") {
                                    do { try store.rerankCapture(capture.id); ranking = true } catch { self.error = error.localizedDescription }
                                }.accessibilityIdentifier("task-planning.rerank")
                            }
                        }
                    }
                    Button("Delete idea", role: .destructive) { perform { try store.deleteCapture(current) } }
                        .accessibilityIdentifier("task-planning.delete")
                }
                if let error { Text(error).foregroundStyle(.red).accessibilityIdentifier("task-planning.error") }
            }.scrollDismissesKeyboard(.interactively).ledgerInputDismissal()
                .navigationTitle("Edit idea").navigationBarTitleDisplayMode(.inline)
                .onChange(of: hoursFocused) { _, focused in
                    if focused { DispatchQueue.main.async { UIApplication.shared.sendAction(#selector(UIResponderStandardEditActions.selectAll(_:)), to: nil, from: nil, for: nil) } }
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).disabled(!store.storageAvailable).accessibilityIdentifier("task-planning.save") }
                }
                .task {
                    let ledger = store.ledger
                    loggedMinutes = await Task.detached(priority: .userInitiated) { ledger.taskLoggedMinutes()[capture.id, default: 0] }.value
                }
                .sheet(isPresented: $snoozing) { CaptureSnoozeView(capture: current) }
                .sheet(isPresented: $ranking) { RankingView() }
        }
    }
    private func perform(_ action: () throws -> Void) {
        do { try action(); dismiss() } catch { self.error = error.localizedDescription }
    }
    private func save() {
        do {
            let text = hours.trimmingCharacters(in: .whitespacesAndNewlines)
            let minutes = text.isEmpty ? nil : Double(text.replacingOccurrences(of: ",", with: ".")).map { $0 * 60 }
            if !text.isEmpty, minutes == nil { throw TaskPlanError.invalidEstimate }
            if minutes != nil, timingChoice == .due, hasStart, dueDate <= startDate {
                error = "Choose a due date after the task’s start date."; return
            }
            let timing: CaptureTiming?
            switch timingChoice { case .automatic: timing = nil; case .noDate: timing = .noDate; case .asap: timing = .asap; case .due: timing = .due(dueDate) }
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
    var showsDeadline = false
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if showsDeadline {
                Text("Due \(row.goal.deadline.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary)
            }
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
        return row.dailyMinutesNeeded.map { "\(status) · \(store.duration($0))/day needed" } ?? status
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
                    Text(row.goal.name).font(.subheadline.weight(.medium)).lineLimit(2).foregroundStyle(.primary)
                    Spacer(minLength: 8)
                    Text(row.goal.deadline, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day()).font(.caption).foregroundStyle(.secondary)
                }
                FocusTaskProgressView(row: row)
            }.padding(.vertical, 4).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier("focus-task.progress.\(row.id)")
    }
}
