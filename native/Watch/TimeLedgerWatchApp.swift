import SwiftUI
import WatchKit
import LedgerCore

@main
struct TimeLedgerWatchApp: App {
    @WKApplicationDelegateAdaptor(SiriWatchDelegate.self) private var siriDelegate
    @StateObject private var store = LedgerStore.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var quickLog: WatchQuickLogRequest?
    #if DEBUG
    @State private var testedLaunchRoute = false
    #endif
    var body: some Scene {
        WindowGroup {
            Group {
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--ui-watch-urgent-checkin") {
                    WatchUrgentCheckInFixture()
                } else { appContent }
                #else
                appContent
                #endif
            }.environmentObject(store).tint(.mint)
                .task {
                    store.start()
                    #if !targetEnvironment(simulator)
                    LedgerShortcuts.updateAppShortcutParameters()
                    #endif
                    NotificationScheduler.shared.configureActions()
                    do { try await NotificationScheduler.shared.apply(store.ledger.settings, force: true) } catch { store.report(error) }
                    #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("--ui-timer-fixture") || ProcessInfo.processInfo.arguments.contains("--ui-timer-open") {
                        store.openTimers(dictate: ProcessInfo.processInfo.arguments.contains("--ui-timer-dictation"))
                    }
                    if !testedLaunchRoute, ProcessInfo.processInfo.arguments.contains("--ui-watch-quick-log") {
                        testedLaunchRoute = true; openQuickLog(WatchLogShortcut.url)
                    }
                    #endif
                }
                .onOpenURL(perform: openQuickLog)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        store.refresh()
                        Task { do { try await NotificationScheduler.shared.apply(store.ledger.settings, force: true) } catch { store.report(error) } }
                    }
                }
                .onChange(of: store.ledger.settings) { _, settings in
                    Task { do { try await NotificationScheduler.shared.apply(settings) } catch { store.report(error) } }
                }
                .alert("Couldn’t complete that", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
                    Button("OK") { store.error = nil }
                } message: { Text(store.error ?? "") }
        }
        WKNotificationScene(controller: CheckInNotificationController.self, category: "CHECKIN")
    }
    @ViewBuilder private var appContent: some View {
        if let request = quickLog {
            WatchQuickLogView(id: request.id) { quickLog = nil }
        } else { WatchHomeView() }
    }
    private func openQuickLog(_ url: URL) {
        if TimerQueueShortcut.matches(url) {
            quickLog = nil; store.openTimers(dictate: url.host?.lowercased() == "queue-timer"); return
        }
        guard WatchLogShortcut.matches(url), quickLog == nil else { return }
        store.start(); quickLog = WatchQuickLogRequest()
    }
}

#if DEBUG
private struct WatchUrgentCheckInFixture: View {
    @StateObject private var reply = WatchReplyState()
    var body: some View {
        ScrollView {
            WatchPromptView(reply: reply) {
                do {
                    try LedgerStore.shared.saveQuickSample("Urgent check-in quick reply", id: "ui-urgent-checkin-reply")
                    reply.saved = true
                } catch { reply.error = error.localizedDescription }
            }
        }.onAppear { reply.urgentTaskText = "Reschedule the class I missed when I was sick" }
    }
}
#endif
