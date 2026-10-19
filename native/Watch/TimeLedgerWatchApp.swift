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
            WatchHomeView().environmentObject(store).tint(.mint)
                .task {
                    store.start(); LedgerShortcuts.updateAppShortcutParameters()
                    NotificationScheduler.shared.configureActions()
                    #if DEBUG
                    if !testedLaunchRoute, ProcessInfo.processInfo.arguments.contains("--ui-watch-quick-log") {
                        testedLaunchRoute = true; openQuickLog(WatchLogShortcut.url)
                    }
                    #endif
                }
                .onOpenURL(perform: openQuickLog)
                .sheet(item: $quickLog) { request in WatchQuickLogView(id: request.id) }
                .onChange(of: scenePhase) { _, phase in if phase == .active { store.refresh() } }
                .alert("Couldn’t complete that", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
                    Button("OK") { store.error = nil }
                } message: { Text(store.error ?? "") }
        }
        WKNotificationScene(controller: CheckInNotificationController.self, category: "CHECKIN")
    }
    private func openQuickLog(_ url: URL) {
        guard WatchLogShortcut.matches(url), quickLog == nil else { return }
        store.start(); quickLog = WatchQuickLogRequest()
    }
}
