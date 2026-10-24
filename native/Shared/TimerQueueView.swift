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
    @State private var showingQueue = false
    @FocusState private var focused: Bool
    @ObservedObject private var notifications = NotificationScheduler.shared
    #if os(watchOS)
    @ObservedObject private var alarm = WatchTimerAlarm.shared
    #endif
    var body: some View {
        TimelineView(.periodic(from: Date(), by: 1)) { timeline in
            #if os(watchOS)
            if let task = store.ledger.currentTimer, store.ledger.timerControl?.isFinished(at: timeline.date) == true {
                VStack(spacing: 6) {
                    Text(task.title).font(.title3.bold()).multilineTextAlignment(.center).lineLimit(4)
                        .accessibilityIdentifier("timers.current")
                    Text("Finished").foregroundStyle(.orange).accessibilityIdentifier("timers.finished")
                    Button("Done & Next", systemImage: "checkmark") { act("done") }
                        .buttonStyle(.borderedProminent).accessibilityIdentifier("timers.done")
                    Button("Restart", systemImage: "arrow.clockwise") { act("restart") }
                        .buttonStyle(.bordered).accessibilityIdentifier("timers.restart")
                }.padding(.horizontal, 8).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let task = store.ledger.currentTimer, let control = store.ledger.timerControl {
                VStack(spacing: 6) {
                    Text(task.title).font(.headline).multilineTextAlignment(.center).lineLimit(2)
                        .accessibilityIdentifier("timers.current")
                    if let due = control.dueAt {
                        Text(timerInterval: due.addingTimeInterval(-task.duration)...due, countsDown: true)
                            .font(.largeTitle.monospacedDigit()).accessibilityIdentifier("timers.countdown")
                    } else {
                        Text("Paused · \(clock(control.remaining(at: timeline.date)))")
                            .font(.title3.monospacedDigit()).accessibilityIdentifier("timers.paused")
                    }
                    HStack(spacing: 6) {
                        Button(control.pausedRemaining == nil ? "Pause" : "Resume", systemImage: control.pausedRemaining == nil ? "pause" : "play") {
                            act(control.pausedRemaining == nil ? "pause" : "resume")
                        }.labelStyle(.iconOnly).accessibilityIdentifier("timers.pause-resume")
                        Button("Done", systemImage: "checkmark") { act("done") }
                            .labelStyle(.iconOnly).buttonStyle(.borderedProminent)
                            .accessibilityLabel("Done & Next").accessibilityIdentifier("timers.done")
                    }.buttonStyle(.bordered)
                    Button("Queue · \(store.ledger.waitingTimers.count)", systemImage: "list.bullet") { showingQueue = true }
                        .font(.caption).buttonStyle(.plain).frame(minHeight: 32).accessibilityIdentifier("timers.queue")
                    if let inputError { Text(inputError).font(.caption2).foregroundStyle(.red).lineLimit(2) }
                }.padding(.horizontal, 8).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else { queue(at: timeline.date) }
            #else
            queue(at: timeline.date)
            #endif
        }
        .navigationTitle("Timer queue")
        #if !os(watchOS)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("About timers", systemImage: "info.circle") { showingHelp = true }
            }
        }
        #endif
        #if os(watchOS)
        .sheet(isPresented: $showingQueue) {
            NavigationStack {
                TimelineView(.periodic(from: Date(), by: 1)) { timeline in queue(at: timeline.date) }
                    .navigationTitle("Queued tasks")
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { showingQueue = false } } }
            }
        }
        #endif
        .alert("Timer queue", isPresented: $showingHelp) { Button("OK") {} } message: {
            Text("The first task starts immediately. Additional tasks wait. Done & Next completes the task and starts the next timer; Restart repeats its full duration. Timer time is not logged as activity.\n\nOn Watch, the system alarm has Stop and Open buttons. Stop silences it; Open returns to these controls. Repeating haptics are system-limited to about 30 minutes. Start or change Watch alarms while Dash is open on the Watch.\n\nThe phone mirrors the last synced timer. Open Dash on iPhone once to start its Lock Screen Live Activity; updates need a connection. The Watch runs independently.")
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
                            Button("Done & Next", systemImage: "checkmark") { act("done") }
                                .buttonStyle(.borderedProminent).accessibilityIdentifier("timers.done")
                            if control.isFinished(at: now) {
                                Button("Restart", systemImage: "arrow.clockwise") { act("restart") }
                                    .accessibilityIdentifier("timers.restart")
                            } else {
                                Button(control.pausedRemaining == nil ? "Pause" : "Resume", systemImage: control.pausedRemaining == nil ? "pause" : "play") {
                                    act(control.pausedRemaining == nil ? "pause" : "resume")
                                }.accessibilityIdentifier("timers.pause-resume")
                                #if os(watchOS)
                                Button("Restart", systemImage: "arrow.clockwise") { act("restart") }
                                Button("Skip task") { remove(task.id) }
                                #else
                                Menu("More", systemImage: "ellipsis") {
                                    Button("Restart") { act("restart") }
                                    Button("Skip task") { remove(task.id) }
                                }
                                #endif
                            }
                        } else {
                            Text("Use your Watch for Done & Next, Restart, or Pause.").font(.caption).foregroundStyle(.secondary)
                        }
                        #if os(watchOS)
                        if control.owner != store.writer {
                            Button("Use Watch for alerts") { act("here") }.accessibilityIdentifier("timers.use-watch")
                        }
                        if !alarm.status.isEmpty { Text(alarm.status).font(.caption2).foregroundStyle(.secondary).accessibilityIdentifier("timers.alarm-status") }
                        #else
                        Text(control.onWatch ? "Running on Apple Watch · last synced state" : "Running on iPhone")
                            .font(.caption).foregroundStyle(.secondary)
                        #endif
                    }.buttonStyle(.borderless)
                } else if !store.ledger.waitingTimers.isEmpty {
                    Button("Start next task") { act("start") }.accessibilityIdentifier("timers.start")
                }
                Section("Add a timer") {
                    #if os(watchOS)
                    Button("Dictate task & time", systemImage: "mic.fill") { dictate() }
                        .accessibilityIdentifier("timers.dictate")
                    #endif
                    TextField("Guitar for 20 minutes", text: $draft, axis: .vertical)
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
                #if os(watchOS)
                NavigationLink("Alarm settings", destination: TimerAlarmSettingsView())
                    .accessibilityIdentifier("timers.alarm-settings")
                #endif
            }
    }
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
                    controller.presentTextInputController(withSuggestions: nil, allowedInputMode: .plain) { results in
                        inputOpen = false
                        if let text = results?.first as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { draft = text; save() }
                    }
                    return
                }
                do { try await Task.sleep(for: .milliseconds(100)) } catch { inputOpen = false; return }
            }
            inputOpen = false; inputError = "Input is not ready. Tap Dictate task & time to try again."
        }
    }
    #endif
}

#if os(watchOS)
private struct TimerAlarmSettingsView: View {
    @AppStorage("timers.haptic-pattern") private var pattern = "standard"
    @AppStorage("timers.haptic-repeat") private var interval = 3.0
    var body: some View {
        NavigationStack {
            Form {
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
            }.navigationTitle("Alarm settings")
                .onChange(of: pattern) { _, _ in WatchTimerAlarm.shared.refreshHaptics() }
                .onChange(of: interval) { _, _ in WatchTimerAlarm.shared.refreshHaptics() }
        }
    }
}
#endif
