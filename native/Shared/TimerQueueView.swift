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
    @State private var queueAtTop = true
    @State private var queueRestingTop: CGFloat?
    @State private var queueDragStartedAtTop: Bool?
    @State private var queueDragStart: Date?
    #endif
    var body: some View {
        Group {
            #if os(watchOS)
            if watchShowsQueue { watchQueue() }
            else {
                TimelineView(.periodic(from: Date(), by: 1)) { timeline in watchCurrentTimer(at: timeline.date) }
            }
            #else
            TimelineView(.periodic(from: Date(), by: 1)) { timeline in queue(at: timeline.date) }
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
        GeometryReader { geometry in
        ScrollView {
        VStack(spacing: 6) {
            if let task = store.ledger.currentTimer, let control = store.ledger.timerControl {
                watchTaskTitle(task.title, identifier: "timers.current")
                watchDial(duration: task.duration, control: control, at: now, size: geometry.size.height - 72)
                    .simultaneousGesture(showQueueGesture)
                HStack {
                    Button(doneTitle, systemImage: "checkmark.circle.fill") { act("done") }
                        .labelStyle(.iconOnly).font(.title2).foregroundStyle(.mint)
                        .accessibilityIdentifier("timers.done")
                    Spacer()
                    watchRestartButton.font(.title2)
                }.buttonStyle(.plain).frame(minHeight: 32)
            } else if let next = store.ledger.waitingTimers.first {
                watchTaskTitle(next.title, identifier: "timers.ready")
                watchDial(duration: next.duration, control: nil, at: now, size: geometry.size.height - 72)
                    .simultaneousGesture(showQueueGesture)
                Button("Start", systemImage: "play.fill") { act("start") }
                    .buttonStyle(.borderedProminent).accessibilityIdentifier("timers.start")
            } else {
                Text("No timers yet").font(.title3).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: geometry.size.height, alignment: .center)
                    .contentShape(Rectangle()).simultaneousGesture(showQueueGesture)
            }
            if alarm.needsAlarmUpdate {
                Text(alarm.status).font(.caption2).foregroundStyle(.orange).lineLimit(2)
                    .accessibilityIdentifier("timers.alarm-update")
            }
            if let inputError { Text(inputError).font(.caption2).foregroundStyle(.red) }
        }.frame(maxWidth: .infinity, minHeight: geometry.size.height)
            .padding(.horizontal, 8).padding(.bottom, 4)
        }.background(.black)
            .accessibilityAction(named: "Show timer queue") { showTimerQueue?() }
        }
    }
    private func watchTaskTitle(_ title: String, identifier: String) -> some View {
        Text(title).font(.system(size: 20, weight: .semibold))
            .multilineTextAlignment(.center).lineLimit(nil).fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity).accessibilityIdentifier(identifier)
    }
    private var showQueueGesture: some Gesture {
        DragGesture(minimumDistance: 35).onEnded { value in
            if value.translation.height < -45, abs(value.translation.height) > abs(value.translation.width) * 1.3 {
                showTimerQueue?()
            }
        }
    }
    private func watchQueue() -> some View {
        let waiting = store.ledger.waitingTimers
        return List {
            if let task = store.ledger.currentTimer, let control = store.ledger.timerControl {
                // Keep countdown updates inside this fixed row. Refreshing the
                // entire List every second interferes with native row dragging.
                TimelineView(.periodic(from: Date(), by: 1)) { timeline in
                VStack(alignment: .leading, spacing: 1) {
                    Text(task.title).font(.system(size: 16, weight: .semibold)).lineLimit(1)
                        .accessibilityIdentifier("timers.queue-current")
                    Text(control.isFinished(at: timeline.date) ? "Now · Finished" : "Now · " + clock(control.remaining(at: timeline.date)))
                        .font(.system(size: 13, design: .rounded).monospacedDigit())
                        .foregroundStyle(.mint)
                }.frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                }
                    .background(queueTopMarker)
                    .listRowInsets(EdgeInsets(top: 0, leading: 6, bottom: 0, trailing: 6))
                    .moveDisabled(true)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button("Delete", systemImage: "trash", role: .destructive) { remove(task.id) }
                            .accessibilityIdentifier("timers.delete.\(task.id)")
                    }
            }
            ForEach(waiting) { task in
                VStack(alignment: .leading, spacing: 1) {
                    Text(task.title).font(.system(size: 16, weight: .medium)).lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("timers.waiting.\(task.id)")
                    Text(clock(task.duration)).font(.system(size: 13, design: .rounded).monospacedDigit())
                        .accessibilityIdentifier("timers.duration.\(task.id)")
                }.foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                    .background {
                        if store.ledger.currentTimer == nil, task.id == waiting.first?.id { queueTopMarker }
                    }
                    .contentShape(Rectangle())
                    .listRowInsets(EdgeInsets(top: 0, leading: 6, bottom: 0, trailing: 6))
                    .accessibilityAction(named: "Move earlier") { moveWaitingTimer(task.id, by: -1) }
                    .accessibilityAction(named: "Move later") { moveWaitingTimer(task.id, by: 1) }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button("Delete", systemImage: "trash", role: .destructive) { remove(task.id) }
                            .accessibilityIdentifier("timers.delete.\(task.id)")
                    }
            }.onMove { offsets, destination in
                var ids = waiting.map(\.id)
                ids.move(fromOffsets: offsets, toOffset: destination)
                do { try store.reorderTimers(ids) } catch { inputError = error.localizedDescription }
            }
            if store.ledger.currentTimer == nil, waiting.isEmpty {
                Text("No queued timers").foregroundStyle(.secondary)
            }
        }.listStyle(.plain)
            .environment(\.defaultMinListRowHeight, 40)
            .contentMargins(.vertical, 0, for: .scrollContent)
            .coordinateSpace(name: "watch.timer-queue")
            .onPreferenceChange(WatchTimerQueueTopKey.self) { top in
                guard let top else { queueAtTop = false; return }
                if queueRestingTop == nil { queueRestingTop = top }
                queueAtTop = top >= (queueRestingTop ?? top) - 2
            }
            .simultaneousGesture(returnToTimerGesture)
            .accessibilityIdentifier("timers.queue-list")
            .accessibilityAction(named: "Show current timer") { showCurrentTimer?() }
            .alert("Timer queue", isPresented: Binding(get: { inputError != nil }, set: { if !$0 { inputError = nil } })) {
                Button("OK") { inputError = nil }
            } message: { Text(inputError ?? "") }
    }
    private var queueTopMarker: some View {
        GeometryReader { geometry in
            Color.clear.preference(key: WatchTimerQueueTopKey.self, value: geometry.frame(in: .named("watch.timer-queue")).minY)
        }
    }
    private var returnToTimerGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if queueDragStartedAtTop == nil {
                    queueDragStartedAtTop = queueAtTop
                    queueDragStart = value.time
                }
            }
            .onEnded { value in
                defer { queueDragStartedAtTop = nil; queueDragStart = nil }
                // A held row belongs to native reordering, never page navigation.
                guard value.time.timeIntervalSince(queueDragStart ?? value.time) < 0.6 else { return }
                let delta = value.translation
                let swipeRight = delta.width > 55 && delta.width > abs(delta.height) * 1.3
                let swipeDownAtTop = queueDragStartedAtTop == true && delta.height > 45 && delta.height > abs(delta.width) * 1.3
                if swipeRight || swipeDownAtTop { showCurrentTimer?() }
            }
    }
    private func moveWaitingTimer(_ id: String, by delta: Int) {
        var ids = store.ledger.waitingTimers.map(\.id)
        guard let from = ids.firstIndex(of: id), ids.indices.contains(from + delta) else { return }
        ids.swapAt(from, from + delta)
        do { try store.reorderTimers(ids) } catch { inputError = error.localizedDescription }
    }
    private func watchDial(duration: TimeInterval, control: TimerQueueControl?, at now: Date, size: CGFloat) -> some View {
        let size = min(132, max(96, size))
        let remaining = control?.remaining(at: now) ?? duration
        let fraction = min(1, max(0, remaining / max(1, duration)))
        let finished = control?.isFinished(at: now) == true
        return ZStack {
            Circle().stroke(Color.secondary.opacity(0.22), lineWidth: 7)
            Circle().trim(from: 0, to: fraction)
                .stroke(finished ? Color.orange : Color.mint, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .accessibilityLabel("Timer progress").accessibilityValue("\(Int((1 - fraction) * 100)) percent complete")
                .accessibilityIdentifier("timers.progress")
            VStack(spacing: 2) {
            Group {
                if finished {
                    Text("Finished").foregroundStyle(.orange).accessibilityIdentifier("timers.finished")
                } else if let due = control?.dueAt {
                    Text(timerInterval: due.addingTimeInterval(-duration)...due, countsDown: true)
                        .accessibilityIdentifier("timers.countdown")
                } else if control != nil {
                    Text(clock(remaining)).foregroundStyle(.secondary).accessibilityIdentifier("timers.paused")
                } else {
                    Text(clock(duration)).foregroundStyle(.secondary).accessibilityIdentifier("timers.duration-ready")
                }
            }.font(.system(size: 30, weight: .medium, design: .rounded).monospacedDigit())
                .lineLimit(1).minimumScaleFactor(0.5).frame(maxWidth: .infinity)
            if let control, !finished {
                Button(control.pausedRemaining == nil ? "Pause timer" : "Resume timer", systemImage: control.pausedRemaining == nil ? "pause.circle" : "play.circle") {
                    act(control.pausedRemaining == nil ? "pause" : "resume")
                }.labelStyle(.iconOnly).font(.title3).buttonStyle(.plain).frame(width: 40, height: 32)
                    .accessibilityIdentifier("timers.pause-resume")
            }
            }.padding(10)
        }.frame(width: size, height: size).padding(4).contentShape(Rectangle())
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
private struct WatchTimerQueueTopKey: PreferenceKey {
    static var defaultValue: CGFloat? { nil }
    static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) { value = nextValue() ?? value }
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
                Text("Stop silences the system alarm. Open shows the timer controls and applies any synced changes. The Watch runs the timer without your phone.")
                    .font(.caption2).foregroundStyle(.secondary)
                Text("After changing a timer on iPhone, reopen Dash on Watch to update its repeating alarm. Until then, the previous Watch alarm can still ring at its original time.")
                    .font(.caption2).foregroundStyle(.secondary)
                Text("To keep Dash visible longer when you raise your wrist, set Watch Settings → General → Return to Clock → Dash to After 1 hour.")
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
