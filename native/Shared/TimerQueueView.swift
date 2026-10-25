import SwiftUI
import LedgerCore
#if os(watchOS)
import WatchKit
#endif

struct TimerQueueView: View {
    @EnvironmentObject private var store: LedgerStore
    var watchShowsQueue = false
    var showCurrentTimer: (() -> Void)? = nil
    var showTimerQueue: (() -> Void)? = nil
    @State private var draft = ""
    @State private var inputError: String?
    @State private var inputOpen = false
    @State private var inputRequest = UUID()
    @State private var showingHelp = false
    @State private var editingTimer: QueuedTimer?
    @FocusState private var focused: Bool
    @ObservedObject private var notifications = NotificationScheduler.shared
    #if os(iOS)
    @State private var timerEditMode: EditMode = .inactive
    #endif
    #if os(watchOS)
    @ObservedObject private var alarm = WatchTimerAlarm.shared
    @State private var queuePosition = 0.0
    @State private var queueReorder: [String]?
    @State private var draggingTimer: String?
    @State private var dragY: CGFloat = 0
    @State private var rowFrames: [String: CGRect] = [:]
    @State private var suppressPageSwipeUntil = Date.distantPast
    @GestureState private var reorderGestureActive = false
    @FocusState private var queueFocused: Bool
    #endif
    var body: some View {
        TimelineView(.periodic(from: Date(), by: 1)) { timeline in
            #if os(watchOS)
            if watchShowsQueue { watchQueue(at: timeline.date) }
            else { watchCurrentTimer(at: timeline.date) }
            #else
            queue(at: timeline.date)
            #endif
        }
        #if os(watchOS)
        .navigationTitle("")
        #else
        .navigationTitle("Timers")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("About timers", systemImage: "info.circle") { showingHelp = true }
            }
        }
        #endif
        .sheet(item: $editingTimer) { task in
            NavigationStack { TimerEditorView(task: task) }
        }
        .alert("Timer queue", isPresented: $showingHelp) { Button("OK") {} } message: {
            Text("Tasks use five minutes unless you include a duration. The first task starts immediately. Additional tasks wait. Done & Next completes the task and starts the next timer; Restart repeats its full duration. Timer time is not logged as activity.\n\nOn Watch, the system alarm has Stop and Open buttons. Stop silences it; Open returns to these controls. Repeating haptics are system-limited to about 30 minutes. Start or change Watch alarms while Dash is open on the Watch.\n\nBoth devices share one queue. Using timer controls or changing the running duration makes this device responsible for alerts. Opening the screen or reordering does not move alerts. Sync requires a connection; the Watch continues independently. Open Dash on iPhone once to start its Lock Screen Live Activity.")
        }
        .task {
            store.refreshTimerSupport(force: true); await notifications.refreshStatus()
            #if os(watchOS)
            if !watchShowsQueue, store.timerDictationRequested { dictate() }
            #endif
        }
        .onChange(of: store.timerRequestID) { _, _ in
            #if os(watchOS)
            if !watchShowsQueue, store.timerDictationRequested { dictate() }
            #else
            focused = store.timerDictationRequested; store.timerDictationRequested = false
            #endif
        }
    }
    #if os(watchOS)
    private func watchCurrentTimer(at now: Date) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let task = store.ledger.currentTimer, let control = store.ledger.timerControl {
                Spacer(minLength: 0)
                Text(task.title).font(.system(size: 24, weight: .semibold)).lineLimit(3).minimumScaleFactor(0.75)
                    .frame(maxWidth: .infinity, alignment: .leading).accessibilityIdentifier("timers.current")
                watchCountdown(task, control: control, at: now, large: true)
                watchProgress(task, control: control, at: now)
                Spacer(minLength: 0)
                HStack {
                    Button(doneTitle, systemImage: "checkmark.circle.fill") { act("done") }
                        .labelStyle(.iconOnly).font(.title2).foregroundStyle(.mint)
                        .accessibilityIdentifier("timers.done")
                    Spacer()
                    watchRestartButton.font(.title2)
                }.buttonStyle(.plain)
            } else if let next = store.ledger.waitingTimers.first {
                Spacer(minLength: 0)
                Text(next.title).font(.title2.bold()).accessibilityIdentifier("timers.ready")
                Text(clock(next.duration)).font(.largeTitle.monospacedDigit()).foregroundStyle(.secondary)
                Button("Start", systemImage: "play.fill") { act("start") }
                    .buttonStyle(.borderedProminent).accessibilityIdentifier("timers.start")
                Spacer(minLength: 0)
            } else {
                Spacer()
                Text("No timers yet").font(.title3).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                Spacer()
            }
            if let inputError { Text(inputError).font(.caption2).foregroundStyle(.red) }
        }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(.horizontal, 8).padding(.bottom, 4).background(.black)
            .contentShape(Rectangle())
            .simultaneousGesture(DragGesture(minimumDistance: 35).onEnded { value in
                if value.translation.height > 45, abs(value.translation.height) > abs(value.translation.width) * 1.3 {
                    showTimerQueue?()
                }
            })
    }
    private func watchQueue(at now: Date) -> some View {
        let scrollIDs = watchQueueScrollIDs
        return ScrollViewReader { proxy in
        List {
            if let task = store.ledger.currentTimer, let control = store.ledger.timerControl {
                VStack(alignment: .leading, spacing: 4) {
                    Text(task.title).font(.system(size: 20, weight: .semibold)).lineLimit(2)
                        .accessibilityIdentifier("timers.queue-current")
                    watchCountdown(task, control: control, at: now, large: false)
                    watchProgress(task, control: control, at: now)
                }.padding(.vertical, 2).id(task.id)
                    .simultaneousGesture(queueReturnGesture)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button("Delete", systemImage: "trash", role: .destructive) { remove(task.id) }
                            .accessibilityIdentifier("timers.delete.\(task.id)")
                    }
            }
            ForEach(watchWaitingTimers) { task in
                VStack(alignment: .leading, spacing: 3) {
                    Text(task.title).font(.system(size: 19, weight: .medium)).lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("timers.waiting.\(task.id)")
                    Text(clock(task.duration)).font(.system(size: 23, design: .rounded).monospacedDigit())
                        .accessibilityIdentifier("timers.duration.\(task.id)")
                }.foregroundStyle(draggingTimer == task.id ? .primary : .secondary).padding(.vertical, 2).contentShape(Rectangle()).id(task.id)
                    .background(GeometryReader { geometry in
                        Color.clear.preference(key: TimerRowFrames.self, value: [task.id: geometry.frame(in: .named("timer.queue"))])
                    })
                    .listRowBackground(draggingTimer == task.id ? Color.mint.opacity(0.3) : nil)
                    .offset(y: draggingTimer == task.id ? dragY - (rowFrames[task.id]?.midY ?? dragY) : 0)
                    .zIndex(draggingTimer == task.id ? 1 : 0)
                    .simultaneousGesture(queueReturnGesture)
                    .simultaneousGesture(timerReorderGesture(task.id))
                    .accessibilityAction(named: "Move earlier") { moveWaitingTimer(task.id, by: -1) }
                    .accessibilityAction(named: "Move later") { moveWaitingTimer(task.id, by: 1) }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button("Delete", systemImage: "trash", role: .destructive) { remove(task.id) }
                            .accessibilityIdentifier("timers.delete.\(task.id)")
                    }
            }
            if store.ledger.currentTimer == nil, store.ledger.waitingTimers.isEmpty {
                Text("No queued timers").foregroundStyle(.secondary).id("empty")
            }
            if let inputError { Text(inputError).font(.caption2).foregroundStyle(.red).id("input-error") }
            if alarm.status.contains("unavailable") || alarm.status.hasPrefix("Open Dash") {
                Text(alarm.status).font(.caption2).foregroundStyle(.orange).id("alarm-status").accessibilityIdentifier("timers.alarm-status")
            }
            if let control = store.ledger.timerControl, store.ledger.currentTimer != nil, control.owner != store.writer {
                Button("Use Watch for alerts") { act("here") }.id("use-watch").accessibilityIdentifier("timers.use-watch")
            }
            NavigationLink(destination: TimerSettingsView()) {
                Label("Timer settings", systemImage: "slider.horizontal.3").font(.caption)
            }.id("settings").accessibilityIdentifier("timers.alarm-settings")
        }.listStyle(.carousel).scrollDisabled(true).coordinateSpace(name: "timer.queue")
            .onPreferenceChange(TimerRowFrames.self) { rowFrames = $0 }
            .onChange(of: reorderGestureActive) { _, active in
                if !active, draggingTimer != nil {
                    draggingTimer = nil; queueReorder = nil; suppressPageSwipeUntil = Date().addingTimeInterval(0.5)
                }
            }
            // Touch swipes navigate pages. Crown rotation scrolls rows without
            // the List's native vertical pan swallowing the return gesture.
            .focusable().focused($queueFocused).focusEffectDisabled()
            .digitalCrownRotation($queuePosition, from: 0, through: Double(max(1, scrollIDs.count - 1)), by: 1,
                                  sensitivity: .low, isContinuous: false, isHapticFeedbackEnabled: true)
            .onChange(of: queuePosition) { _, value in
                let index = min(max(0, Int(value.rounded())), scrollIDs.count - 1)
                proxy.scrollTo(scrollIDs[index], anchor: .top)
            }
            .onAppear {
                queuePosition = 0; queueFocused = true
                #if DEBUG
                // XCTest has no Crown-rotation action. Start this fixture at
                // the first upcoming row; the test still performs a real drag.
                if ProcessInfo.processInfo.arguments.contains("--ui-timer-scroll-upcoming"), scrollIDs.count > 1 {
                    Task { @MainActor in
                        await Task.yield(); proxy.scrollTo(scrollIDs[1], anchor: .top); queuePosition = 1
                    }
                }
                #endif
            }
            .onDisappear { queueFocused = false; draggingTimer = nil; queueReorder = nil }
            // Up is navigation on this page, even when more rows remain.
            // The Digital Crown still scrolls the full queue; horizontal row
            // swipes retain their native Delete action.
            .simultaneousGesture(queueReturnGesture)
            .accessibilityAction(named: "Show current timer") { showCurrentTimer?() }
        }
    }
    private var queueReturnGesture: some Gesture {
        DragGesture(minimumDistance: 35).onEnded { value in
            if draggingTimer == nil, Date() > suppressPageSwipeUntil,
               value.translation.height < -45, abs(value.translation.height) > abs(value.translation.width) * 1.3 {
                showCurrentTimer?()
            }
        }
    }
    private var watchWaitingTimers: [QueuedTimer] {
        let waiting = store.ledger.waitingTimers
        guard let order = queueReorder else { return waiting }
        let tasks = Dictionary(uniqueKeysWithValues: waiting.map { ($0.id, $0) })
        return order.compactMap { tasks[$0] } + waiting.filter { !order.contains($0.id) }
    }
    private func timerReorderGesture(_ id: String) -> some Gesture {
        LongPressGesture(minimumDuration: 0.4).sequenced(before: DragGesture(minimumDistance: 1, coordinateSpace: .named("timer.queue")))
            .updating($reorderGestureActive) { value, active, _ in
                switch value {
                case .first(true), .second(true, _): active = true
                default: break
                }
            }
            .onChanged { value in
                switch value {
                // A short swipe must remain navigation. Start reordering only
                // after the hold has succeeded and the row actually moves.
                case .second(true, let drag?):
                    beginTimerDrag(id); dragY = drag.location.y
                    guard var ids = queueReorder, let from = ids.firstIndex(of: id) else { return }
                    for (target, other) in ids.enumerated() where other != id {
                        guard let frame = rowFrames[other] else { continue }
                        if (target < from && dragY < frame.midY) || (target > from && dragY > frame.midY) {
                            ids.remove(at: from); ids.insert(id, at: target)
                            withAnimation(.easeInOut(duration: 0.15)) { queueReorder = ids }
                            break
                        }
                    }
                default: break
                }
            }.onEnded { _ in
                guard draggingTimer == id else { return }
                if let ids = queueReorder { do { try store.reorderTimers(ids) } catch { inputError = error.localizedDescription } }
                draggingTimer = nil; queueReorder = nil; suppressPageSwipeUntil = Date().addingTimeInterval(0.5)
            }
    }
    private func beginTimerDrag(_ id: String) {
        guard draggingTimer == nil else { return }
        draggingTimer = id; queueReorder = store.ledger.waitingTimers.map(\.id)
        dragY = rowFrames[id]?.midY ?? 0
        suppressPageSwipeUntil = Date().addingTimeInterval(60)
        WKInterfaceDevice.current().play(.click)
    }
    private func moveWaitingTimer(_ id: String, by delta: Int) {
        var ids = store.ledger.waitingTimers.map(\.id)
        guard let from = ids.firstIndex(of: id), ids.indices.contains(from + delta) else { return }
        ids.swapAt(from, from + delta)
        do { try store.reorderTimers(ids) } catch { inputError = error.localizedDescription }
    }
    private var watchQueueScrollIDs: [String] {
        var ids = store.ledger.currentTimer.map { [$0.id] } ?? []
        ids += store.ledger.waitingTimers.map(\.id)
        if ids.isEmpty { ids.append("empty") }
        if inputError != nil { ids.append("input-error") }
        if alarm.status.contains("unavailable") || alarm.status.hasPrefix("Open Dash") { ids.append("alarm-status") }
        if let control = store.ledger.timerControl, store.ledger.currentTimer != nil, control.owner != store.writer { ids.append("use-watch") }
        return ids + ["settings"]
    }
    private func watchCountdown(_ task: QueuedTimer, control: TimerQueueControl, at now: Date, large: Bool) -> some View {
        HStack(spacing: 6) {
            Group {
                if control.isFinished(at: now) {
                    Text("Finished").foregroundStyle(.orange).accessibilityIdentifier("timers.finished")
                } else if let due = control.dueAt {
                    Text(timerInterval: due.addingTimeInterval(-task.duration)...due, countsDown: true)
                        .accessibilityIdentifier("timers.countdown")
                } else {
                    Text(clock(control.remaining(at: now))).foregroundStyle(.secondary).accessibilityIdentifier("timers.paused")
                }
            }.font(.system(size: large ? 42 : 28, weight: .medium, design: .rounded).monospacedDigit())
                .lineLimit(1).minimumScaleFactor(0.6).frame(maxWidth: .infinity, alignment: .leading)
            if !control.isFinished(at: now) {
                Button(control.pausedRemaining == nil ? "Pause timer" : "Resume timer", systemImage: control.pausedRemaining == nil ? "pause.circle" : "play.circle") {
                    act(control.pausedRemaining == nil ? "pause" : "resume")
                }.labelStyle(.iconOnly).font(.title3).buttonStyle(.plain).frame(width: 32, height: 40)
                    .accessibilityIdentifier("timers.pause-resume")
            }
        }
    }
    private func watchProgress(_ task: QueuedTimer, control: TimerQueueControl, at now: Date) -> some View {
        let progress = min(1, max(0, 1 - control.remaining(at: now) / max(1, task.duration)))
        return ProgressView(value: progress).progressViewStyle(.linear).tint(control.isFinished(at: now) ? .orange : .mint)
            .accessibilityLabel("Timer progress").accessibilityValue("\(Int(progress * 100)) percent complete")
            .accessibilityIdentifier("timers.progress")
    }
    @ViewBuilder private var watchRestartButton: some View {
        let button = Button("Restart", systemImage: "arrow.clockwise") { act("restart") }
            .labelStyle(.iconOnly).accessibilityIdentifier("timers.restart")
        if #available(watchOS 11.0, *) {
            button.handGestureShortcut(.primaryAction, isEnabled: !inputOpen)
        } else { button }
    }
    #endif
    #if !os(watchOS)
    private func queue(at now: Date) -> some View {
            let waiting = store.ledger.waitingTimers
            return List {
                Section {
                    TextField("Task · 5 minutes unless specified", text: $draft, axis: .vertical)
                        .focused($focused).submitLabel(.done).onSubmit(save)
                        .accessibilityIdentifier("timers.draft")
                    if !draft.isEmpty {
                        Button("Add timer", action: save).disabled(!store.storageAvailable)
                            .accessibilityIdentifier("timers.add")
                    }
                    if let inputError { Text(inputError).font(.caption).foregroundStyle(.red) }
                }
                if let task = store.ledger.currentTimer, let control = store.ledger.timerControl {
                    Section("Now") {
                        Button { editingTimer = task } label: {
                            HStack { Text(task.title).font(.title3.weight(.semibold)).foregroundStyle(.primary); Spacer(); Image(systemName: "pencil").font(.caption) }
                        }.accessibilityLabel(task.title).accessibilityIdentifier("timers.current")
                        if control.isFinished(at: now) {
                            Text("Finished").font(.title2.bold()).foregroundStyle(.orange)
                                .accessibilityIdentifier("timers.finished")
                        } else if let due = control.dueAt {
                            Text(timerInterval: due.addingTimeInterval(-task.duration)...due, countsDown: true)
                                .font(.largeTitle.monospacedDigit()).accessibilityIdentifier("timers.countdown")
                        } else {
                            Text("Paused · \(clock(control.remaining(at: now)))")
                                .font(.title2.monospacedDigit()).accessibilityIdentifier("timers.paused")
                        }
                        ProgressView(value: min(1, max(0, 1 - control.remaining(at: now) / max(1, task.duration))))
                            .tint(control.isFinished(at: now) ? .orange : .mint).accessibilityIdentifier("timers.progress")
                        HStack {
                            Button(doneTitle, systemImage: "checkmark") { act("done") }
                                .buttonStyle(.borderedProminent).accessibilityIdentifier("timers.done")
                            Spacer()
                            if !control.isFinished(at: now) {
                                Button(control.pausedRemaining == nil ? "Pause" : "Resume", systemImage: control.pausedRemaining == nil ? "pause" : "play") {
                                    act(control.pausedRemaining == nil ? "pause" : "resume")
                                }.labelStyle(.iconOnly).accessibilityIdentifier("timers.pause-resume")
                            }
                            Button("Restart", systemImage: "arrow.clockwise") { act("restart") }
                                .labelStyle(.iconOnly).accessibilityIdentifier("timers.restart")
                        }
                        Text(control.onWatch ? "Alerts on Apple Watch" : "Alerts on iPhone")
                            .font(.caption).foregroundStyle(.secondary)
                    }.swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button("Delete", systemImage: "trash", role: .destructive) { remove(task.id) }
                            .accessibilityIdentifier("timers.delete.\(task.id)")
                    }.buttonStyle(.borderless)
                } else if !store.ledger.waitingTimers.isEmpty {
                    Button("Start next task", systemImage: "play.fill") { act("start") }.accessibilityIdentifier("timers.start")
                }
                Section("Up next · \(store.ledger.waitingTimers.count)") {
                    if store.ledger.waitingTimers.isEmpty { Text("No queued tasks").foregroundStyle(.secondary) }
                    ForEach(waiting) { task in
                        Button { editingTimer = task } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(task.title).accessibilityIdentifier("timers.waiting.\(task.id)")
                                Text(clock(task.duration)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "pencil").font(.caption).foregroundStyle(.secondary)
                        }.foregroundStyle(.primary)
                        }.buttonStyle(.plain).swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button("Delete", systemImage: "trash", role: .destructive) { remove(task.id) }
                                .accessibilityIdentifier("timers.delete.\(task.id)")
                        }
                    }.onMove { offsets, destination in
                        var ids = waiting.map(\.id); ids.move(fromOffsets: offsets, toOffset: destination)
                        do { try store.reorderTimers(ids) } catch { inputError = error.localizedDescription }
                    }
                }
                if store.ledger.currentTimer != nil, !notifications.permissionGranted {
                    Button("Enable timer notifications") { requestAlerts() }.font(.caption)
                }
                NavigationLink("Timer settings", destination: TimerSettingsView())
            }.environment(\.editMode, $timerEditMode)
                .toolbar {
                    Button(timerEditMode.isEditing ? "Done" : "Edit") {
                        withAnimation { timerEditMode = timerEditMode.isEditing ? .inactive : .active }
                    }.accessibilityIdentifier("timers.reorder")
                }
    }
    #endif
    private var doneTitle: String { store.ledger.settings.timerAutoStartNext ? "Done & Next" : "Done" }
    private func clock(_ seconds: Double) -> String {
        let value = max(0, Int(seconds.rounded(.up)))
        return value >= 3600 ? String(format: "%d:%02d:%02d", value / 3600, (value % 3600) / 60, value % 60) : String(format: "%d:%02d", value / 60, value % 60)
    }
    private func save() {
        do {
            try store.addTimer(draft); draft = ""; inputError = nil; focused = false
            #if os(watchOS)
            WKInterfaceDevice.current().play(.success)
            #endif
            requestAlerts()
        } catch { inputError = error.localizedDescription }
    }
    private func act(_ action: String) {
        do { try store.changeTimer(action); inputError = nil } catch { inputError = error.localizedDescription }
    }
    private func remove(_ id: String) {
        do { try store.deleteTimer(id) } catch { inputError = error.localizedDescription }
    }
    private func requestAlerts() {
        Task {
            do { _ = try await notifications.permission(); store.refreshTimerSupport(force: true) }
            catch { inputError = error.localizedDescription }
        }
    }
    #if os(watchOS)
    private func dictate() {
        // A system presentation can be dropped during a Watch page transition.
        // If that happens, another tap can recover instead of leaving + locked.
        let request = UUID(); inputRequest = request
        if inputOpen { WKApplication.shared().visibleInterfaceController?.dismissTextInputController() }
        store.timerDictationRequested = false; inputOpen = true
        inputError = nil
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-timer-dictation") {
            draft = "Practice guitar for twenty minutes"; inputOpen = false; save(); return
        }
        #endif
        Task { @MainActor in
            // Let the button's state update and page transition finish before
            // asking WatchKit to present its system text-entry controller.
            do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
            for _ in 0..<20 {
                guard inputRequest == request, !Task.isCancelled else { return }
                if WKApplication.shared().applicationState == .active, let controller = WKApplication.shared().visibleInterfaceController {
                    var suggestions: [String]?
                    #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("--ui-timer-system-input") { suggestions = ["Stretch"] }
                    #endif
                    // Present directly from the main timer screen. A SwiftUI sheet
                    // above the hosting controller would cover this system input UI.
                    controller.presentTextInputController(withSuggestions: suggestions, allowedInputMode: .plain) { results in
                        guard inputRequest == request else { return }
                        inputOpen = false
                        if let text = results?.first as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { draft = text; save() }
                    }
                    return
                }
                do { try await Task.sleep(for: .milliseconds(100)) } catch { inputOpen = false; return }
            }
            guard inputRequest == request else { return }
            inputOpen = false; inputError = "Input is not ready. Tap Add timer to try again."
        }
    }
    #endif
}

#if os(watchOS)
private struct TimerRowFrames: PreferenceKey {
    static var defaultValue: [String: CGRect] { [:] }
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) { value.merge(nextValue(), uniquingKeysWith: { _, new in new }) }
}
private struct CompactTimerButtonStyle: ButtonStyle {
    var prominent = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.frame(maxWidth: .infinity).frame(height: 32)
            .foregroundStyle(prominent ? Color.black : Color.mint)
            .background(Capsule().fill(prominent ? Color.mint : Color.mint.opacity(0.18)))
            .opacity(configuration.isPressed ? 0.65 : 1)
    }
}
#endif

private struct TimerEditorView: View {
    @EnvironmentObject private var store: LedgerStore
    @Environment(\.dismiss) private var dismiss
    let task: QueuedTimer
    @State private var title: String
    @State private var minutes: String
    @State private var error: String?
    init(task: QueuedTimer) {
        self.task = task
        _title = State(initialValue: task.title)
        _minutes = State(initialValue: String(format: "%g", task.duration / 60))
    }
    var body: some View {
        Form {
            TextField("Task", text: $title, axis: .vertical).accessibilityIdentifier("timers.edit-title")
            TextField("Minutes", text: $minutes)
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
                .accessibilityIdentifier("timers.edit-minutes")
            if store.ledger.currentTimer?.id == task.id {
                Text("Changing the duration keeps time already elapsed.").font(.caption).foregroundStyle(.secondary)
            }
            if let error { Text(error).foregroundStyle(.red) }
        }.navigationTitle("Edit timer")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        do {
                            guard let value = Double(minutes.replacingOccurrences(of: ",", with: ".")) else { throw TimerQueueError.invalidDuration }
                            try store.editTimer(task.id, title: title, duration: value * 60); dismiss()
                        } catch { self.error = error.localizedDescription }
                    }.accessibilityIdentifier("timers.edit-save")
                }
            }
    }
}

struct TimerSettingsView: View {
    @EnvironmentObject private var store: LedgerStore
    #if os(watchOS)
    @AppStorage("timers.haptic-pattern") private var pattern = "standard"
    @AppStorage("timers.haptic-repeat") private var interval = 3.0
    @ObservedObject private var alarm = WatchTimerAlarm.shared
    #endif
    var body: some View {
            Form {
                Section {
                    Toggle("Start next after Done", isOn: Binding(get: { store.ledger.settings.timerAutoStartNext }, set: { value in
                        var settings = store.ledger.settings; settings.timerAutoStartNext = value
                        do { try store.saveSettings(settings) } catch { store.report(error) }
                    })).accessibilityIdentifier("timers.auto-next")
                } footer: {
                    Text("When enabled, the checkmark completes this task and starts the next queued timer. When off, the next task waits for Start next. Expiry always waits for you to confirm. Restart repeats the current timer.")
                }
                #if os(watchOS)
                if !alarm.status.isEmpty { Text(alarm.status).font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("timers.alarm-status") }
                Picker("Alert pattern", selection: $pattern) {
                    Text("Standard pulse").tag("standard")
                    Text("Attention pulse").tag("attention")
                    Text("Light tap").tag("light")
                }.accessibilityIdentifier("timers.haptic-pattern")
                Picker("Repeat every", selection: $interval) {
                    ForEach([2.0, 3, 5, 10], id: \.self) { Text("\(Int($0)) seconds").tag($0) }
                }
                Button("Preview alert pattern") { WKInterfaceDevice.current().play(pattern == "attention" ? .retry : pattern == "light" ? .click : .notification) }.accessibilityIdentifier("timers.haptic-preview")
                Text("Alarm sound follows your Watch’s system settings. Repeating haptics use the Watch’s system alarm, limited to about 30 minutes.")
                    .font(.caption2).foregroundStyle(.secondary)
                Text("Stop silences the system alarm. Open shows the expired task with Done & Next and Restart. The Watch runs the timer without your phone.")
                    .font(.caption2).foregroundStyle(.secondary)
                Text("Double-tap restarts the timer while this app’s timer screen is open. The background alarm screen uses Apple’s gesture behavior.").font(.caption2).foregroundStyle(.secondary)
                #endif
            }.navigationTitle("Timer settings")
                #if os(watchOS)
                .onChange(of: pattern) { _, _ in WatchTimerAlarm.shared.refreshHaptics() }
                .onChange(of: interval) { _, _ in WatchTimerAlarm.shared.refreshHaptics() }
                #endif
    }
}
