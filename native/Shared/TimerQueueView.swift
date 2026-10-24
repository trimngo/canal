import SwiftUI
import LedgerCore
#if os(watchOS)
import WatchKit
#endif

struct TimerQueueView: View {
    @EnvironmentObject private var store: LedgerStore
    @State private var draft = ""
    @State private var inputError: String?
    @State private var inputOpen = false
    @State private var showingHelp = false
    @FocusState private var focused: Bool
    @ObservedObject private var notifications = NotificationScheduler.shared
    #if os(watchOS)
    @ObservedObject private var alarm = WatchTimerAlarm.shared
    #endif
    var body: some View {
        TimelineView(.periodic(from: Date(), by: 1)) { timeline in
            #if os(watchOS)
            watchTimers(at: timeline.date)
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
            if store.timerDictationRequested { dictate() }
            #endif
        }
        .onChange(of: store.timerRequestID) { _, _ in
            #if os(watchOS)
            if store.timerDictationRequested { dictate() }
            #else
            focused = store.timerDictationRequested; store.timerDictationRequested = false
            #endif
        }
    }
    #if os(watchOS)
    private func watchTimers(at now: Date) -> some View {
        VStack(spacing: 4) {
          ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                if let task = store.ledger.currentTimer, let control = store.ledger.timerControl {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(task.title).font(.headline).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier("timers.current")
                        if control.isFinished(at: now) {
                            Text("Finished").font(.system(size: 12, weight: .semibold)).foregroundStyle(.orange).accessibilityIdentifier("timers.finished")
                        } else if let due = control.dueAt {
                            Text(timerInterval: due.addingTimeInterval(-task.duration)...due, countsDown: true)
                                .font(.title3.monospacedDigit()).accessibilityIdentifier("timers.countdown")
                        } else {
                            Text("Paused · \(clock(control.remaining(at: now)))").font(.caption.monospacedDigit()).lineLimit(2)
                                .accessibilityIdentifier("timers.paused")
                        }
                    }
                    let progress = min(1, max(0, 1 - control.remaining(at: now) / max(1, task.duration)))
                    ProgressView(value: progress).progressViewStyle(.linear).tint(control.isFinished(at: now) ? .orange : .mint)
                        .frame(height: 4).clipped()
                        .accessibilityLabel("Timer progress").accessibilityValue("\(Int(progress * 100)) percent complete")
                        .accessibilityIdentifier("timers.progress")
                    HStack(spacing: 6) {
                        if !control.isFinished(at: now) {
                            Button(control.pausedRemaining == nil ? "Pause" : "Resume", systemImage: control.pausedRemaining == nil ? "pause" : "play") {
                                act(control.pausedRemaining == nil ? "pause" : "resume")
                            }.labelStyle(.iconOnly).accessibilityIdentifier("timers.pause-resume")
                        }
                        watchRestartButton
                        Button(doneTitle, systemImage: "checkmark") { act("done") }
                            .labelStyle(.iconOnly).buttonStyle(CompactTimerButtonStyle(prominent: true)).accessibilityIdentifier("timers.done")
                    }.buttonStyle(CompactTimerButtonStyle())
                    Divider()
                } else if !store.ledger.waitingTimers.isEmpty {
                    Button("Start next task") { act("start") }.buttonStyle(CompactTimerButtonStyle(prominent: true)).accessibilityIdentifier("timers.start")
                } else { Text("No timers yet").foregroundStyle(.secondary) }
                let waiting = store.ledger.waitingTimers
                if waiting.isEmpty, store.ledger.currentTimer != nil {
                    Text("No upcoming timers").font(.caption2).foregroundStyle(.secondary)
                }
                ForEach(waiting) { task in
                    HStack(spacing: 4) {
                        Text(task.title).font(.subheadline).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier("timers.waiting.\(task.id)")
                        Text(clock(task.duration)).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                            .accessibilityIdentifier("timers.duration.\(task.id)")
                        Button("Delete", systemImage: "trash") { remove(task.id) }
                            .labelStyle(.iconOnly).buttonStyle(.plain).frame(width: 32, height: 32)
                            .accessibilityIdentifier("timers.delete.\(task.id)")
                    }
                    Divider()
                }
                if let inputError { Text(inputError).font(.caption2).foregroundStyle(.red) }
                if !draft.isEmpty {
                    TextField("Timer task", text: $draft, axis: .vertical).onSubmit(save).accessibilityIdentifier("timers.draft")
                    Button("Queue timer", action: save).buttonStyle(CompactTimerButtonStyle()).accessibilityIdentifier("timers.add")
                }
                if let control = store.ledger.timerControl, store.ledger.currentTimer != nil {
                    Button("Skip current task") { if let id = store.ledger.currentTimer?.id { remove(id) } }.font(.caption).buttonStyle(.plain).frame(minHeight: 32)
                    if control.owner != store.writer {
                        Button("Use Watch for alerts") { act("here") }.font(.caption).buttonStyle(.plain).frame(minHeight: 32).accessibilityIdentifier("timers.use-watch")
                    }
                    if !alarm.status.isEmpty { Text(alarm.status).font(.caption2).foregroundStyle(.secondary).accessibilityIdentifier("timers.alarm-status") }
                }
                NavigationLink("Timer settings", destination: TimerSettingsView()).font(.caption)
                    .buttonStyle(.plain).frame(minHeight: 32)
                    .accessibilityIdentifier("timers.alarm-settings")
            }.padding(.leading, 6).padding(.trailing, 12)
          }.frame(maxWidth: .infinity, maxHeight: .infinity)
          Button("Add timer", systemImage: "mic.fill") { dictate() }
              .font(.caption).buttonStyle(CompactTimerButtonStyle(prominent: true))
              .disabled(inputOpen || !store.storageAvailable).accessibilityIdentifier("timers.dictate")
              .padding(.horizontal, 6).padding(.bottom, 2)
        }
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
        guard !inputOpen else { return }
        store.timerDictationRequested = false; inputOpen = true
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-timer-dictation") {
            draft = "Practice guitar for twenty minutes"; inputOpen = false; save(); return
        }
        #endif
        Task { @MainActor in
            for _ in 0..<20 {
                if WKApplication.shared().applicationState == .active, let controller = WKApplication.shared().visibleInterfaceController {
                    var suggestions: [String]?
                    #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("--ui-timer-system-input") { suggestions = ["Stretch"] }
                    #endif
                    // Present directly from the main timer screen. A SwiftUI sheet
                    // above the hosting controller would cover this system input UI.
                    controller.presentTextInputController(withSuggestions: suggestions, allowedInputMode: .plain) { results in
                        inputOpen = false
                        if let text = results?.first as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { draft = text; save() }
                    }
                    return
                }
                do { try await Task.sleep(for: .milliseconds(100)) } catch { inputOpen = false; return }
            }
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
                Picker("Haptic pattern", selection: $pattern) {
                    Text("Standard").tag("standard")
                    Text("Attention").tag("attention")
                    Text("Light tap").tag("light")
                }
                Picker("Repeat every", selection: $interval) {
                    ForEach([2.0, 3, 5, 10], id: \.self) { Text("\(Int($0)) seconds").tag($0) }
                }
                Button("Preview haptic") { WKInterfaceDevice.current().play(pattern == "attention" ? .retry : pattern == "light" ? .click : .notification) }
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
