import SwiftUI
import LedgerCore
#if os(watchOS)
import WatchKit
#endif

struct TimerQueueView: View {
    @EnvironmentObject private var store: LedgerStore
    var watchShowsQueue = false
    var showCurrentTimer: (() -> Void)? = nil
    @State private var draft = ""
    @State private var inputError: String?
    @State private var inputOpen = false
    @State private var inputRequest = UUID()
    @State private var showingHelp = false
    @FocusState private var focused: Bool
    @ObservedObject private var notifications = NotificationScheduler.shared
    #if os(watchOS)
    @ObservedObject private var alarm = WatchTimerAlarm.shared
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
        .navigationTitle("Timer queue")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("About timers", systemImage: "info.circle") { showingHelp = true }
            }
        }
        #endif
        .alert("Timer queue", isPresented: $showingHelp) { Button("OK") {} } message: {
            Text("Tasks use five minutes unless you include a duration. The first task starts immediately. Additional tasks wait. Done & Next completes the task and starts the next timer; Restart repeats its full duration. Timer time is not logged as activity.\n\nOn Watch, the system alarm has Stop and Open buttons. Stop silences it; Open returns to these controls. Repeating haptics are system-limited to about 30 minutes. Start or change Watch alarms while Dash is open on the Watch.\n\nThe phone mirrors the last synced timer. Open Dash on iPhone once to start its Lock Screen Live Activity; updates need a connection. The Watch runs independently.")
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
        }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(.horizontal, 8).padding(.bottom, 4)
            .accessibilityIdentifier("timers.current-screen")
    }
    private func watchQueue(at now: Date) -> some View {
        List {
            if let task = store.ledger.currentTimer, let control = store.ledger.timerControl {
                VStack(alignment: .leading, spacing: 4) {
                    Text(task.title).font(.system(size: 20, weight: .semibold)).lineLimit(2)
                        .accessibilityIdentifier("timers.queue-current")
                    watchCountdown(task, control: control, at: now, large: false)
                    watchProgress(task, control: control, at: now)
                }.padding(.vertical, 2)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button("Delete", systemImage: "trash", role: .destructive) { remove(task.id) }
                            .accessibilityIdentifier("timers.delete.\(task.id)")
                    }
            }
            ForEach(store.ledger.waitingTimers) { task in
                VStack(alignment: .leading, spacing: 3) {
                    Text(task.title).font(.system(size: 19, weight: .medium)).lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("timers.waiting.\(task.id)")
                    Text(clock(task.duration)).font(.system(size: 23, design: .rounded).monospacedDigit())
                        .accessibilityIdentifier("timers.duration.\(task.id)")
                }.foregroundStyle(.secondary).padding(.vertical, 2)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button("Delete", systemImage: "trash", role: .destructive) { remove(task.id) }
                            .accessibilityIdentifier("timers.delete.\(task.id)")
                    }
            }
            if store.ledger.currentTimer == nil, store.ledger.waitingTimers.isEmpty {
                Text("No queued timers").foregroundStyle(.secondary)
            }
            if let inputError { Text(inputError).font(.caption2).foregroundStyle(.red) }
            if alarm.status.contains("unavailable") || alarm.status.hasPrefix("Open Dash") {
                Text(alarm.status).font(.caption2).foregroundStyle(.orange).accessibilityIdentifier("timers.alarm-status")
            }
            if let control = store.ledger.timerControl, store.ledger.currentTimer != nil, control.owner != store.writer {
                Button("Use Watch for alerts") { act("here") }.accessibilityIdentifier("timers.use-watch")
            }
            NavigationLink(destination: TimerSettingsView()) {
                Label("Timer settings", systemImage: "slider.horizontal.3").font(.caption)
            }.accessibilityIdentifier("timers.alarm-settings")
        }.listStyle(.carousel).accessibilityIdentifier("timers.queue-screen")
            // Up is navigation on this page, even when more rows remain.
            // The Digital Crown still scrolls the full queue; horizontal row
            // swipes retain their native Delete action.
            .simultaneousGesture(DragGesture(minimumDistance: 35).onEnded { value in
                if value.translation.height < -45, abs(value.translation.height) > abs(value.translation.width) * 1.3 {
                    showCurrentTimer?()
                }
            })
            .accessibilityAction(named: "Show current timer") { showCurrentTimer?() }
    }
    private func watchCountdown(_ task: QueuedTimer, control: TimerQueueControl, at now: Date, large: Bool) -> some View {
        Button {
            if !control.isFinished(at: now) { act(control.pausedRemaining == nil ? "pause" : "resume") }
        } label: {
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
        }.buttonStyle(.plain).disabled(control.isFinished(at: now))
            .accessibilityLabel(control.pausedRemaining == nil ? "Pause timer" : "Resume timer")
            .accessibilityIdentifier("timers.pause-resume")
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
            List {
                if let task = store.ledger.currentTimer, let control = store.ledger.timerControl {
                    Section("Now") {
                        Text(task.title).font(.title3.weight(.semibold)).accessibilityIdentifier("timers.current")
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
                        if canControl {
                            Button(doneTitle, systemImage: "checkmark") { act("done") }
                                .buttonStyle(.borderedProminent).accessibilityIdentifier("timers.done")
                            if control.isFinished(at: now) {
                                Button("Restart", systemImage: "arrow.clockwise") { act("restart") }
                                    .accessibilityIdentifier("timers.restart")
                            } else {
                                Button(control.pausedRemaining == nil ? "Pause" : "Resume", systemImage: control.pausedRemaining == nil ? "pause" : "play") {
                                    act(control.pausedRemaining == nil ? "pause" : "resume")
                                }.accessibilityIdentifier("timers.pause-resume")
                                Menu("More", systemImage: "ellipsis") {
                                    Button("Restart") { act("restart") }
                                    Button("Skip task") { remove(task.id) }
                                }
                            }
                        } else {
                            Text("Use your Watch for Done & Next, Restart, or Pause.").font(.caption).foregroundStyle(.secondary)
                        }
                        Text(control.onWatch ? "Running on Apple Watch · last synced state" : "Running on iPhone")
                            .font(.caption).foregroundStyle(.secondary)
                    }.buttonStyle(.borderless)
                } else if !store.ledger.waitingTimers.isEmpty {
                    if canControl {
                        Button("Start next task") { act("start") }.accessibilityIdentifier("timers.start")
                    } else {
                        Text("Start the next task on your Apple Watch.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section("Add a timer") {
                    TextField("Task · 5 minutes unless specified", text: $draft, axis: .vertical)
                        .focused($focused).submitLabel(.done).onSubmit(save)
                        .accessibilityIdentifier("timers.draft")
                    if !draft.isEmpty {
                        Button("Queue timer", action: save).disabled(!store.storageAvailable)
                            .accessibilityIdentifier("timers.add")
                    }
                    if let inputError { Text(inputError).font(.caption).foregroundStyle(.red) }
                }
                Section("Up next · \(store.ledger.waitingTimers.count)") {
                    if store.ledger.waitingTimers.isEmpty { Text("No queued tasks").foregroundStyle(.secondary) }
                    ForEach(store.ledger.waitingTimers) { task in
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(task.title).accessibilityIdentifier("timers.waiting.\(task.id)")
                                Text(clock(task.duration)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Delete", systemImage: "trash") { remove(task.id) }
                                .labelStyle(.iconOnly).buttonStyle(.borderless)
                                .accessibilityIdentifier("timers.delete.\(task.id)")
                        }
                    }
                }
                if store.ledger.currentTimer != nil, !notifications.permissionGranted {
                    Button("Enable timer notifications") { requestAlerts() }.font(.caption)
                }
            }
    }
    #endif
    private var doneTitle: String { store.ledger.settings.timerAutoStartNext ? "Done & Next" : "Done" }
    private var canControl: Bool { LedgerStore.isWatch || store.ledger.timerControl?.onWatch != true }
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
