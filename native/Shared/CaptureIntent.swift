import AppIntents
import LedgerCore

struct CaptureThoughtIntent: AppIntent {
    static var title: LocalizedStringResource = "Capture a thought"
    static var description = IntentDescription("Save a thought or task to your Time Ledger inbox. It does not count as time spent.")
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
        return .result(dialog: "Saved to your Time Ledger inbox.")
    }
}

struct LedgerShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: CaptureThoughtIntent(), phrases: [
            "Capture in \(.applicationName)", "Add a thought to \(.applicationName)",
            "Create a \(.applicationName) task"
        ], shortTitle: "Capture a thought", systemImageName: "tray.and.arrow.down")
    }
}
