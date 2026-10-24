import AppIntents
import LedgerCore

struct CaptureThoughtIntent: AppIntent {
    static var title: LocalizedStringResource = "Capture a thought"
    static var description = IntentDescription("Save a thought or task to your Dash inbox. It does not count as time spent.")
    static var openAppWhenRun = false

    @Parameter(title: "What do you want to capture?")
    var text: String

    static var parameterSummary: some ParameterSummary {
        Summary("Capture \(\.$text)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = LedgerStore.shared; store.start()
        try store.addCapture(text)
        return .result(dialog: "Saved to your Dash inbox.")
    }
}

struct LogActivityIntent: AppIntent {
    static var title: LocalizedStringResource = "Log an activity"
    static var description = IntentDescription("Record what you are doing right now in Dash, with a timestamp.")
    static var openAppWhenRun = false

    @Parameter(title: "What are you doing?") var activity: String

    static var parameterSummary: some ParameterSummary { Summary("Log \(\.$activity)") }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try LedgerStore.shared.saveQuickSample(activity)
        return .result(dialog: "Activity logged in Dash.")
    }
}

struct LedgerShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: CaptureThoughtIntent(), phrases: [
            "Capture in \(.applicationName)", "Add a thought to \(.applicationName)",
            "Create a \(.applicationName) task"
        ], shortTitle: "Capture a thought", systemImageName: "tray.and.arrow.down")
        AppShortcut(intent: LogActivityIntent(), phrases: [
            "Log in \(.applicationName)", "Log an activity in \(.applicationName)"
        ], shortTitle: "Log an activity", systemImageName: "clock")
        AppShortcut(intent: QueueTimerIntent(), phrases: [
            "Queue a timer in \(.applicationName)", "Add a timer to \(.applicationName)"
        ], shortTitle: "Queue a timer", systemImageName: "timer")
    }
}

struct QueueTimerIntent: AppIntent {
    static var title: LocalizedStringResource = "Queue a timer"
    static var description = IntentDescription("Add a task and duration, for example: Practice guitar for twenty minutes. Further tasks wait until you choose Done & Next.")
    static var openAppWhenRun = true
    @Parameter(title: "Task and duration") var task: String
    static var parameterSummary: some ParameterSummary { Summary("Queue \(\.$task)") }
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = LedgerStore.shared; store.start(); try store.addTimer(task); store.openTimers()
        return .result(dialog: "Added to your timer queue.")
    }
}
